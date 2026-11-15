import AVFoundation
import Accelerate
import AudioToolbox
import CoreAudio
import MacWisprCore

/// Converts any device format to 16 kHz mono Float32 and appends it to a PCM file.
/// Pads with silence when the device stalls, so both meeting tracks stay on the
/// same timeline and transcript timestamps line up. The timeline is the awake
/// clock (`MeetingTimeline`), so time the Mac spends asleep is skipped, not padded.
final class MeetingTrackSink: @unchecked Sendable {
    let writer: PCM16FileWriter
    private let startUptime: TimeInterval
    private let lock = NSLock()
    /// Serializes conversion + writing; a capture restart can briefly overlap two callbacks.
    private let consumeLock = NSLock()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var level: Float = 0
    private var peak: Float = 0
    private var stalls: [(at: Int, length: Int)] = []
    private static let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init(url: URL, startUptime: TimeInterval) throws {
        writer = try PCM16FileWriter(url: url)
        self.startUptime = startUptime
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
        consumeLock.lock()
        defer { consumeLock.unlock() }
        let samples = convert(buffer)
        guard !samples.isEmpty else { return }
        let written = writer.sampleCount
        let gap = MeetingTimeline.silenceToPad(elapsedSamples: elapsedSamples, written: written, incoming: samples.count)
        if gap > 0 {
            writer.appendSilence(gap)
            if gap >= MeetingTimeline.stallWarningSamples {
                lock.lock()
                stalls.append((written, gap))
                lock.unlock()
            }
        }
        writer.append(samples)
    }

    private var elapsedSamples: Int {
        MeetingTimeline.elapsedSamples(since: startUptime, now: MeetingTimeline.awakeNow())
    }

    /// Drop-outs worth telling the user about, including one still going on now.
    func stallWarnings(track: String) -> [String] {
        lock.lock()
        let found = stalls
        lock.unlock()
        var warnings = found.compactMap { MeetingTimeline.stallWarning(track: track, gapSamples: $0.length, atSample: $0.at) }
        if let trailing = MeetingTimeline.trailingStallWarning(track: track, elapsedSamples: elapsedSamples, written: writer.sampleCount) {
            warnings.append(trailing)
        }
        return warnings
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

/// Calls `handler` on `queue` whenever one of the given system-wide audio properties
/// changes (default device, device list…).
final class AudioHardwareListener {
    private let addresses: [AudioObjectPropertyAddress]
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private var active = true

    init(_ selectors: [AudioObjectPropertySelector], queue: DispatchQueue, handler: @escaping () -> Void) {
        addresses = selectors.map {
            AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
        self.queue = queue
        block = { _, _ in handler() }
        for var address in addresses {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
    }

    func cancel() {
        guard active else { return }
        active = false
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
    }

    deinit { cancel() }
}

/// Microphone side of a meeting ("the room"). Separate engine from dictation so
/// ⌥Space keeps working during a meeting. Survives device changes (AirPods connecting,
/// a USB mic unplugged, Bluetooth profile switches): it rebuilds the tap and restarts
/// into the same sink, and reports through `onIssue` if it can't.
final class MeetingMicCapture {
    private static let maxRestartAttempts = 5

    private let engine = AVAudioEngine()
    /// All engine work happens here so restarts never race `start`/`stop`.
    private let queue = DispatchQueue(label: "macwispr.meeting.mic", qos: .userInitiated)
    private var tapped = false
    private var sink: MeetingTrackSink?
    private var deviceUID: String?
    private var currentDevice: AudioDeviceID?
    private var restartPending = false
    private var configObserver: NSObjectProtocol?
    private var hardwareListener: AudioHardwareListener?

    /// Called on a background queue with a message for the meeting's warnings.
    var onIssue: ((String) -> Void)?

    func start(deviceUID: String?, sink: MeetingTrackSink) throws {
        try queue.sync {
            self.deviceUID = deviceUID?.trimmingCharacters(in: .whitespaces)
            self.sink = sink
            do {
                try startEngine(sink: sink)
            } catch {
                self.sink = nil
                stopEngine()
                throw error
            }
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.restart(force: false)
        }
        hardwareListener = AudioHardwareListener(
            [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices], queue: queue
        ) { [weak self] in
            self?.restart(force: false)
        }
    }

    /// Restarts after a device change. `force` restarts even if the engine looks healthy (after wake).
    func restart(force: Bool) {
        queue.async { [weak self] in
            guard let self, self.sink != nil, !self.restartPending else { return }
            // Device changes arrive in bursts; let them settle and restart once.
            self.restartPending = true
            self.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartPending = false
                self?.performRestart(force: force, attempt: 1)
            }
        }
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        hardwareListener?.cancel()
        hardwareListener = nil
        queue.sync {
            sink = nil
            stopEngine()
        }
    }

    /// The selected mic if it's still connected, else the system default.
    private func wantedDevice() -> AudioDeviceID? {
        if let uid = deviceUID, !uid.isEmpty, let id = AudioInputDevices.deviceID(forUID: uid) { return id }
        return AudioInputDevices.defaultInputDeviceID()
    }

    private func performRestart(force: Bool, attempt: Int) {
        guard let sink else { return }
        if !force, engine.isRunning, currentDevice == wantedDevice() { return }
        stopEngine()
        do {
            try startEngine(sink: sink)
            if let uid = deviceUID, !uid.isEmpty, AudioInputDevices.deviceID(forUID: uid) == nil {
                onIssue?("The selected microphone disconnected; the meeting continued with the system default microphone.")
            }
        } catch {
            stopEngine()
            if attempt < Self.maxRestartAttempts {
                queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.performRestart(force: true, attempt: attempt + 1)
                }
            } else {
                onIssue?("Microphone stopped after an audio device change and could not restart: \(error.localizedDescription)")
            }
        }
    }

    private func startEngine(sink: MeetingTrackSink) throws {
        if var dev = wantedDevice(), let unit = engine.inputNode.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
            currentDevice = status == noErr ? dev : nil
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

    private func stopEngine() {
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
/// permission, which macOS asks for on first use. The aggregate device is pinned to
/// the output device, so it is rebuilt when the default output changes.
@available(macOS 14.2, *)
final class SystemAudioCapture {
    private static let maxRestartAttempts = 5

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputUID: String?
    private var sink: MeetingTrackSink?
    private var restartPending = false
    private var hardwareListener: AudioHardwareListener?
    private let queue = DispatchQueue(label: "macwispr.meeting.systemaudio", qos: .userInitiated)
    /// Builds and tears down the tap. Separate from the IO queue so stopping never waits on itself.
    private let control = DispatchQueue(label: "macwispr.meeting.systemaudio.control", qos: .userInitiated)

    /// Called on a background queue with a message for the meeting's warnings.
    var onIssue: ((String) -> Void)?

    func start(sink: MeetingTrackSink) throws {
        try control.sync {
            self.sink = sink
            do {
                try startTap(sink: sink)
            } catch {
                self.sink = nil
                throw error
            }
        }
        hardwareListener = AudioHardwareListener(
            [kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices],
            queue: control
        ) { [weak self] in
            self?.restart(force: false)
        }
    }

    /// Rebuilds the tap if the output device changed. `force` rebuilds anyway (after wake).
    func restart(force: Bool) {
        control.async { [weak self] in
            guard let self, self.sink != nil, !self.restartPending else { return }
            self.restartPending = true
            self.control.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartPending = false
                self?.performRestart(force: force, attempt: 1)
            }
        }
    }

    func stop() {
        hardwareListener?.cancel()
        hardwareListener = nil
        control.sync {
            sink = nil
            stopTap()
        }
    }

    private func performRestart(force: Bool, attempt: Int) {
        guard let sink else { return }
        if !force, aggregateID != kAudioObjectUnknown, let uid = try? Self.defaultOutputUID(), uid == outputUID { return }
        stopTap()
        do {
            try startTap(sink: sink)
        } catch {
            if attempt < Self.maxRestartAttempts {
                control.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.performRestart(force: true, attempt: attempt + 1)
                }
            } else {
                onIssue?("Other apps' audio stopped after an audio device change and could not restart: \(error.localizedDescription)")
            }
        }
    }

    private func startTap(sink: MeetingTrackSink) throws {
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

        let outputUID: String
        do {
            outputUID = try Self.defaultOutputUID()
        } catch {
            stopTap()
            throw error
        }
        self.outputUID = outputUID
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
            stopTap()
            throw MeetingCaptureError.osStatus("Creating the system audio device", err)
        }

        var asbd: AudioStreamBasicDescription
        do {
            asbd = try Self.tapFormat(tapID)
        } catch {
            stopTap()
            throw error
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            stopTap()
            throw MeetingCaptureError.message("System audio has an unsupported format.")
        }
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInput, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInput, deallocator: nil) else { return }
            sink.consume(buffer)
        }
        guard err == noErr else {
            stopTap()
            throw MeetingCaptureError.osStatus("Starting system audio", err)
        }
        err = AudioDeviceStart(aggregateID, procID)
        guard err == noErr else {
            stopTap()
            throw MeetingCaptureError.osStatus("Starting system audio", err)
        }
    }

    private func stopTap() {
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
        outputUID = nil
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
