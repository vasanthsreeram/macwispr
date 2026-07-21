import AVFoundation
import Accelerate
import AudioToolbox

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    /// Core Audio device UID. `nil` / empty → system default input.
    var inputDeviceUID: String?
    private var samples: [Float] = []
    private let targetSampleRate: Double = 16000
    private let lock = NSLock()
    private var isTapped = false

    /// Latest input RMS level (raw, ~0…1) for UI metering. Written on the audio
    /// thread, read from the main thread via `currentAudioLevel()`.
    private var meterLevel: Float = 0
    /// Debounce guard so a burst of config-change notifications restarts capture once.
    private var restartPending = false

    /// Reused on the audio thread so each 1024-frame tap does not allocate.
    private var monoScratch: [Float] = []
    /// Expected max frames per tap (engine may deliver slightly more than requested).
    private let maxTapFrames = 4096

    /// Converts device format → 16 kHz mono float32. nil when input already matches.
    private var converter: AVAudioConverter?
    private var convertBuffer: AVAudioPCMBuffer?
    /// True when input is already 16 kHz mono — append channel data directly.
    private var usesPassthrough = false

    /// Prompt for mic access if needed. Safe to call at launch.
    static func requestPermissionIfNeeded() {
        if #available(macOS 14.0, *) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    NSLog("MacWispr mic permission: %@", granted ? "granted" : "denied")
                }
            case .denied, .restricted:
                NSLog("MacWispr mic permission: denied — dictation will capture silence")
            case .authorized:
                break
            @unknown default:
                break
            }
        }
    }

    /// Last device successfully bound for capture (for UI / debug). Empty if unknown.
    private(set) var lastBoundInputName: String = ""
    private(set) var lastBoundInputUID: String = ""

    init() {
        // Mid-recording device changes: the AUHAL is bound to a concrete device id,
        // so it does NOT follow the OS default on its own — rebind when it moves.
        installDefaultInputListener()
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleInputConfigChange(reason: "engine configuration change")
        }
    }

    /// Latest mic input level for UI metering (raw RMS, ~0…1). Thread-safe.
    func currentAudioLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return meterLevel
    }

    func startRecording() {
        // Pre-size for ~60s of 16 kHz mono so appends rarely reallocate.
        samples = []
        samples.reserveCapacity(Int(targetSampleRate) * 60)
        startCapture()
    }

    /// Binds the device, detects the hardware format, installs the tap, starts the
    /// engine. Safe to call again mid-session (rebind after a device switch) —
    /// accumulated `samples` are kept; only the capture path is rebuilt.
    private func startCapture() {
        // Clean up a prior session that never stopped cleanly.
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        converter = nil
        convertBuffer = nil
        usesPassthrough = false
        lastBoundInputName = ""
        lastBoundInputUID = ""

        // Materialize the input AUHAL, then bind the chosen (or OS-default) mic
        // *before* reading the hardware format / installing the tap.
        engine.prepare()
        applyInputDeviceUID(inputDeviceUID)

        let inputNode = engine.inputNode
        // Prefer hardware input format after device bind (more accurate post-switch).
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let outFormat = inputNode.outputFormat(forBus: 0)
        let inputFormat = (hwFormat.sampleRate > 0 && hwFormat.channelCount > 0) ? hwFormat : outFormat
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            NSLog("AudioRecorder: invalid input format (mic permission / device?)")
            return
        }
        NSLog(
            "AudioRecorder: capturing name=%@ uid=%@ format=%.0f Hz × %u ch",
            lastBoundInputName.isEmpty ? "?" : lastBoundInputName,
            lastBoundInputUID.isEmpty ? "?" : lastBoundInputUID,
            inputFormat.sampleRate,
            inputFormat.channelCount
        )

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            NSLog("AudioRecorder: failed to create target format")
            return
        }

        let alreadyTarget =
            abs(inputFormat.sampleRate - targetSampleRate) < 1.0
            && inputFormat.channelCount == 1
            && inputFormat.commonFormat == .pcmFormatFloat32

        if alreadyTarget {
            usesPassthrough = true
            if monoScratch.count < maxTapFrames {
                monoScratch = [Float](repeating: 0, count: maxTapFrames)
            }
        } else if let conv = AVAudioConverter(from: inputFormat, to: targetFormat) {
            converter = conv
            // Worst-case output frames for one tap (upsample edge case + padding).
            let ratio = targetSampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(
                ceil(Double(maxTapFrames) * max(ratio, 1.0)) + 64
            )
            convertBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
            // Keep mono scratch for the vDSP fallback path if converter fails mid-stream.
            if monoScratch.count < maxTapFrames {
                monoScratch = [Float](repeating: 0, count: maxTapFrames)
            }
        } else {
            NSLog("AudioRecorder: AVAudioConverter unavailable — using vDSP mono + linear resample")
            if monoScratch.count < maxTapFrames {
                monoScratch = [Float](repeating: 0, count: maxTapFrames)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processTapBuffer(buffer, sourceSR: inputFormat.sampleRate)
        }
        isTapped = true

        do {
            try engine.start()
        } catch {
            NSLog("AudioRecorder: Failed to start engine: \(error)")
            inputNode.removeTap(onBus: 0)
            isTapped = false
        }
    }

    func stopRecording() -> [Float] {
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        converter?.reset()
        lock.lock()
        let result = samples
        meterLevel = 0
        lock.unlock()
        return result
    }

    // MARK: - Mid-recording device changes

    /// Follows Sound settings / Control Center while capturing on the system default.
    private func installDefaultInputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self else { return }
            // Only relevant when following the system default; an explicit pick stays.
            let explicit = self.inputDeviceUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard explicit.isEmpty else { return }
            self.handleInputConfigChange(reason: "default input device changed")
        }
        if status != noErr {
            NSLog("AudioRecorder: could not observe default input changes (OSStatus %d)", status)
        }
    }

    /// Rebuild the capture path (rebind device, re-detect format, reinstall tap)
    /// without dropping audio already captured. Debounced — device switches fire
    /// several notifications while Core Audio settles.
    private func handleInputConfigChange(reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isTapped, !self.restartPending else { return }
            self.restartPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self.restartPending = false
                guard self.isTapped else { return }
                NSLog("AudioRecorder: %@ — rebinding capture mid-recording", reason)
                self.startCapture()
            }
        }
    }

    /// Copy of audio captured so far without stopping the mic (for live partials).
    func snapshotSamples() -> [Float] {
        lock.lock()
        let copy = samples
        lock.unlock()
        return copy
    }

    /// Seconds of 16 kHz mono captured so far.
    var capturedDuration: TimeInterval {
        lock.lock()
        let n = samples.count
        lock.unlock()
        return Double(n) / targetSampleRate
    }

    /// Binds `AVAudioEngine` to a specific input device before capture starts.
    /// Empty / nil UID → **explicitly** bind the current OS default input (so a prior
    /// explicit choice cannot stick on the AUHAL after the user picks System Default).
    private func applyInputDeviceUID(_ uid: String?) {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Force the input node / AUHAL to exist.
        _ = engine.inputNode
        engine.prepare()

        guard let audioUnit = engine.inputNode.audioUnit else {
            NSLog("AudioRecorder: input node has no audio unit — cannot select mic")
            return
        }

        let requestedID: AudioDeviceID?
        let requestedLabel: String
        if trimmed.isEmpty {
            requestedID = AudioInputDevices.defaultInputDeviceID()
            requestedLabel = "system-default"
        } else if let id = AudioInputDevices.deviceID(forUID: trimmed) {
            requestedID = id
            requestedLabel = trimmed
        } else {
            NSLog(
                "AudioRecorder: input device uid=%@ not found — falling back to system default",
                trimmed
            )
            requestedID = AudioInputDevices.defaultInputDeviceID()
            requestedLabel = "system-default(fallback)"
        }

        guard var device = requestedID, device != 0 else {
            NSLog("AudioRecorder: no resolvable input device id (%@)", requestedLabel)
            return
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            NSLog(
                "AudioRecorder: failed to set input device %@ (OSStatus %d)",
                requestedLabel,
                status
            )
            return
        }

        // Verify the AUHAL actually took the device (new Macs often wrap default
        // in CADefaultDeviceAggregate — accept either the requested id or that aggregate).
        var actual = AudioDeviceID(0)
        var actualSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let getStatus = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &actual,
            &actualSize
        )
        if getStatus == noErr, actual != 0 {
            let name = AudioInputDevices.name(forDeviceID: actual)
                ?? AudioInputDevices.name(forDeviceID: device)
                ?? requestedLabel
            let actualUID = AudioInputDevices.uidString(deviceID: actual)
                ?? (trimmed.isEmpty ? "" : trimmed)
            lastBoundInputName = name
            lastBoundInputUID = actualUID
            if actual != device {
                // Common when binding OS default: AUHAL reports CADefaultDeviceAggregate-*.
                if actualUID.hasPrefix("CADefaultDeviceAggregate") || trimmed.isEmpty {
                    lastBoundInputName = AudioInputDevices.defaultInputDeviceName()
                    if let defID = AudioInputDevices.defaultInputDeviceID(),
                       let defUID = AudioInputDevices.uidString(deviceID: defID)
                    {
                        lastBoundInputUID = defUID
                    }
                } else {
                    NSLog(
                        "AudioRecorder: device readback mismatch requested=%u actual=%u name=%@",
                        device,
                        actual,
                        name
                    )
                }
            }
            NSLog(
                "AudioRecorder: bound input → %@ (uid=%@, requested=%@)",
                lastBoundInputName,
                lastBoundInputUID.isEmpty ? "?" : lastBoundInputUID,
                requestedLabel
            )
        } else {
            lastBoundInputName = AudioInputDevices.name(forDeviceID: device) ?? requestedLabel
            lastBoundInputUID = trimmed
            NSLog("AudioRecorder: set input ok but could not read back (OSStatus %d)", getStatus)
        }
    }

    // MARK: - Audio thread

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, sourceSR: Double) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        if let channelData = buffer.floatChannelData {
            var rms: Float = 0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameCount))
            lock.lock()
            meterLevel = rms
            lock.unlock()
        }

        if usesPassthrough {
            appendPassthrough(buffer, frameCount: frameCount)
            return
        }

        if let converter, let convertBuffer {
            convertAndAppend(buffer: buffer, converter: converter, convertBuffer: convertBuffer)
            return
        }

        // Fallback: vDSP mono mix + linear interpolation (no converter available).
        fallbackResample(buffer: buffer, sourceSR: sourceSR, frameCount: frameCount)
    }

    private func appendPassthrough(_ buffer: AVAudioPCMBuffer, frameCount: Int) {
        guard let channelData = buffer.floatChannelData else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameCount))
        lock.unlock()
    }

    private func convertAndAppend(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        convertBuffer: AVAudioPCMBuffer
    ) {
        convertBuffer.frameLength = 0
        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertBuffer, error: &error, withInputFrom: inputBlock)
        if status == .error {
            NSLog("AudioRecorder: convert error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        let outFrames = Int(convertBuffer.frameLength)
        guard outFrames > 0, let channelData = convertBuffer.floatChannelData else { return }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: outFrames))
        lock.unlock()
    }

    /// vDSP mono-mix + linear resample when AVAudioConverter cannot be created.
    private func fallbackResample(buffer: AVAudioPCMBuffer, sourceSR: Double, frameCount: Int) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)

        if frameCount > monoScratch.count {
            monoScratch = [Float](repeating: 0, count: frameCount)
        }

        mixToMono(
            channelData: channelData,
            frameCount: frameCount,
            channelCount: channelCount
        )

        if abs(sourceSR - targetSampleRate) < 1.0 {
            lock.lock()
            samples.append(contentsOf: monoScratch.prefix(frameCount))
            lock.unlock()
            return
        }

        let ratio = targetSampleRate / sourceSR
        let outputCount = Int(Double(frameCount) * ratio)
        guard outputCount > 0 else { return }

        var output = [Float](repeating: 0, count: outputCount)
        let last = frameCount - 1
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let lower = Int(srcIndex)
            let upper = min(lower + 1, last)
            let frac = Float(srcIndex - Double(lower))
            output[i] = monoScratch[lower] * (1 - frac) + monoScratch[upper] * frac
        }

        lock.lock()
        samples.append(contentsOf: output)
        lock.unlock()
    }

    /// Average channels into `monoScratch` using Accelerate.
    private func mixToMono(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channelCount: Int
    ) {
        let n = vDSP_Length(frameCount)
        if channelCount == 1 {
            _ = monoScratch.withUnsafeMutableBufferPointer { dest in
                memcpy(dest.baseAddress!, channelData[0], frameCount * MemoryLayout<Float>.size)
            }
            return
        }

        // Start with channel 0, then accumulate the rest and scale.
        monoScratch.withUnsafeMutableBufferPointer { dest in
            guard let destBase = dest.baseAddress else { return }
            destBase.update(from: channelData[0], count: frameCount)
            for ch in 1..<channelCount {
                vDSP_vadd(destBase, 1, channelData[ch], 1, destBase, 1, n)
            }
            var scale = 1.0 / Float(channelCount)
            vDSP_vsmul(destBase, 1, &scale, destBase, 1, n)
        }
    }
}
