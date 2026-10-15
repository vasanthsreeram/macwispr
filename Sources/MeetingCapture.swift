import AVFoundation
import Accelerate
import AudioToolbox
import CoreAudio
import MacWisprCore

/// Converts any device format to 16 kHz mono Float32 and appends it to a PCM file.
/// Pads with silence when the device stalls, so both meeting tracks stay on the
/// same wall-clock timeline and transcript timestamps line up.
final class MeetingTrackSink: @unchecked Sendable {
    let writer: PCM16FileWriter
    private let startedAt: Date
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var level: Float = 0
    private var peak: Float = 0
    private static let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init(url: URL, startedAt: Date) throws {
        writer = try PCM16FileWriter(url: url)
        self.startedAt = startedAt
    }

    /// Recent RMS (0…1) for the UI meter.
    var currentLevel: Float {
        lock.lock(); defer { lock.unlock() }
        return level
    }

    /// Loudest sample seen; 0 means the track was digital silence.
    var peakLevel: Float {
        lock.lock(); defer { lock.unlock() }
        return peak
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        if let ch = buffer.floatChannelData {
            var rms: Float = 0
            var mx: Float = 0
            vDSP_rmsqv(ch[0], 1, &rms, vDSP_Length(frames))
            vDSP_maxmgv(ch[0], 1, &mx, vDSP_Length(frames))
            lock.lock()
            level = rms
            peak = max(peak, mx)
            lock.unlock()
        }
        let samples = convert(buffer)
        guard !samples.isEmpty else { return }
        let expectedEnd = Int(Date().timeIntervalSince(startedAt) * 16_000)
        let gap = expectedEnd - samples.count - writer.sampleCount
        if gap > 8_000 { writer.appendSilence(gap) }
        writer.append(samples)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let format = buffer.format
        if converter == nil || converterInputFormat != format {
            converter = AVAudioConverter(from: format, to: Self.target)
            converter?.downmix = true
            converterInputFormat = format
        }
        guard let converter else { return [] }
        let ratio = 16_000 / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: capacity) else { return [] }
        var fed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, s in
            if fed { s.pointee = .noDataNow; return nil }
            fed = true
            s.pointee = .haveData
            return buffer
        }
        guard status != .error, let ch = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    func close() {
        writer.close()
    }
}

/// Microphone side of a meeting ("the room"). Separate engine from dictation so
/// ⌥Space keeps working during a meeting.
final class MeetingMicCapture {
    private let engine = AVAudioEngine()
    private var tapped = false

    func start(deviceUID: String?, sink: MeetingTrackSink) throws {
        if let uid = deviceUID?.trimmingCharacters(in: .whitespaces), !uid.isEmpty,
           let deviceID = AudioInputDevices.deviceID(forUID: uid),
           let unit = engine.inputNode.audioUnit
        {
            var dev = deviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MeetingCaptureError.message("No microphone input available. Check the microphone and MacWispr's Microphone permission.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            sink.consume(buffer)
        }
        tapped = true
        try engine.start()
    }

    func stop() {
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        engine.stop()
    }
}

enum MeetingCaptureError: LocalizedError {
    case message(String)
    case osStatus(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .osStatus(let what, let s): return "\(what) failed (OSStatus \(s))"
        }
    }
}

/// System audio from every other app (Zoom, Meet in a browser, Teams…) via a
/// Core Audio process tap. Needs macOS 14.2+ and the "System Audio Recording"
/// permission, which macOS asks for on first use.
@available(macOS 14.2, *)
final class SystemAudioCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "macwispr.meeting.systemaudio", qos: .userInitiated)

    func start(sink: MeetingTrackSink) throws {
        // Leave MacWispr's own chimes out of the recording.
        var excluded: [AudioObjectID] = []
        if let me = Self.processObjectID(pid: getpid()) { excluded.append(me) }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        desc.uuid = UUID()
        desc.name = "MacWispr Meeting"
        desc.muteBehavior = .unmuted
        desc.isPrivate = true

        var err = AudioHardwareCreateProcessTap(desc, &tapID)
        guard err == noErr else { throw MeetingCaptureError.osStatus("Creating the system audio tap", err) }

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacWispr Meeting Tap",
            kAudioAggregateDeviceUIDKey: "com.macwispr.meeting.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        err = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard err == noErr else {
            stop()
            throw MeetingCaptureError.osStatus("Creating the system audio device", err)
        }

        var asbd = try Self.tapFormat(tapID)
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            stop()
            throw MeetingCaptureError.message("System audio has an unsupported format.")
        }
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInput, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInput, deallocator: nil) else { return }
            sink.consume(buffer)
        }
        guard err == noErr else {
            stop()
            throw MeetingCaptureError.osStatus("Starting system audio", err)
        }
        err = AudioDeviceStart(aggregateID, procID)
        guard err == noErr else {
            stop()
            throw MeetingCaptureError.osStatus("Starting system audio", err)
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func processObjectID(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidValue = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &object
        )
        return err == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard err == noErr else { throw MeetingCaptureError.osStatus("Finding the output device", err) }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        err = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard err == noErr, let uid else { throw MeetingCaptureError.osStatus("Reading the output device", err) }
        return uid.takeRetainedValue() as String
    }

    private static func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard err == noErr else { throw MeetingCaptureError.osStatus("Reading the system audio format", err) }
        return asbd
    }
}
