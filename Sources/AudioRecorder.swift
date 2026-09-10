import AVFoundation
import Accelerate
import AudioToolbox
import MacWisprCore

final class AudioRecorder: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var activeDeviceUID: String?
    /// Core Audio device UID. `nil` / empty → system default input.
    var inputDeviceUID: String?
    /// Long captures spill older PCM to disk; only a short tail stays in RAM.
    let capture = SampleRing()
    private let targetSampleRate: Double = 16000
    private let lock = NSLock()
    private var isTapped = false

    /// Latest input RMS (~0…1) for the listening waveform HUD only.
    /// Written on the audio thread; read via `currentAudioLevel()`.
    /// No mid-recording rebind / engine restart — metering only.
    private var meterLevel: Float = 0

    /// Reused on the audio thread so each 1024-frame tap does not allocate.
    private var monoScratch: [Float] = []
    /// Expected max frames per tap (engine may deliver slightly more than requested).
    private let maxTapFrames = 4096

    /// Converts device format → 16 kHz mono float32. nil when input already matches.
    private var converter: AVAudioConverter?
    private var convertBuffer: AVAudioPCMBuffer?
    /// True when input is already 16 kHz mono — append channel data directly.
    private var usesPassthrough = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopEngine()
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // When idle, rebuild the engine so new routes (AirPods, USB mic) are picked up cleanly.
            if !self.isTapped && !self.engine.isRunning {
                self.rebuildEngine()
            }
        }
    }

    private func rebuildEngine() {
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        engine = AVAudioEngine()
        converter = nil
        convertBuffer = nil
        usesPassthrough = false
    }

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

    /// Thread-safe mic level for the HUD waveform (silence ≈ 0).
    func currentAudioLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return meterLevel
    }

    @discardableResult
    func startRecording() -> Bool {
        capture.reset()
        lock.lock()
        meterLevel = 0
        lock.unlock()

        // Clean up a prior session that never stopped cleanly.
        stopEngine()

        if inputDeviceUID != activeDeviceUID {
            rebuildEngine()
            activeDeviceUID = inputDeviceUID
        }

        applyInputDeviceUID(inputDeviceUID)

        let inputNode = engine.inputNode

        // Hardware format is the ground truth. On macOS, inputNode.outputFormat(forBus: 0)
        // can stay stale (e.g. 48 kHz default) even when hardware switched to 16 kHz (Bluetooth HFP/SCO).
        // Passing the true hardware format prevents AVAudioEngine's fatal Format mismatch exception.
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let busFormat = inputNode.outputFormat(forBus: 0)
        let inputFormat: AVAudioFormat
        if hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 {
            inputFormat = hwFormat
        } else if busFormat.sampleRate > 0 && busFormat.channelCount > 0 {
            inputFormat = busFormat
        } else {
            NSLog("AudioRecorder: invalid input format (hw: \(hwFormat), bus: \(busFormat))")
            return false
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            NSLog("AudioRecorder: failed to create target format")
            return false
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
            return true
        } catch {
            NSLog("AudioRecorder: Failed to start engine: \(error)")
            if isTapped {
                inputNode.removeTap(onBus: 0)
                isTapped = false
            }
            rebuildEngine()
            return false
        }
    }

    /// Stop the mic but keep the capture ring for chunked STT.
    func stopEngine() {
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        converter?.reset()
        converter = nil
        convertBuffer = nil
        usesPassthrough = false
        lock.lock()
        meterLevel = 0
        lock.unlock()
    }

    /// Stop + materialize. Only for short clips (self-test). Long dictation uses `capture`.
    func stopRecording() -> [Float] {
        stopEngine()
        return capture.takeAllAndClear()
    }

    func clearCapture() {
        capture.reset()
    }

    /// Copy of audio captured so far without stopping the mic (for live partials).
    func snapshotSamples() -> [Float] {
        capture.snapshotTail(maxSamples: AudioChunkPlanner.qwenWindowSamples)
    }

    func snapshotTail(maxSamples: Int) -> [Float] {
        capture.snapshotTail(maxSamples: maxSamples)
    }

    func copyNewSamples(from offset: Int) -> [Float] {
        capture.copyNew(from: offset)
    }

    var capturedSampleCount: Int { capture.count }

    /// Seconds of 16 kHz mono captured so far.
    var capturedDuration: TimeInterval {
        capture.duration
    }

    /// Binds `AVAudioEngine` to a specific input device before capture starts.
    private func applyInputDeviceUID(_ uid: String?) {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        guard let deviceID = AudioInputDevices.deviceID(forUID: trimmed) else {
            NSLog("AudioRecorder: input device uid=%@ not found — using system default", trimmed)
            return
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            NSLog("AudioRecorder: input node has no audio unit")
            return
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            NSLog("AudioRecorder: failed to set input device (OSStatus %d)", status)
        }
    }

    // MARK: - Audio thread

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, sourceSR: Double) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Level meter for HUD (first channel RMS). Does not affect capture path.
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
        capture.append(UnsafeBufferPointer(start: channelData[0], count: frameCount))
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

        capture.append(UnsafeBufferPointer(start: channelData[0], count: outFrames))
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
            let prefix = Array(monoScratch.prefix(frameCount))
            capture.append(prefix)
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

        capture.append(output)
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
