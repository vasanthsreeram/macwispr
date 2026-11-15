import AVFoundation
import Accelerate
import AudioToolbox
import MacWisprCore

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    /// Core Audio device UID. `nil` / empty → system default input.
    var inputDeviceUID: String?
    /// One ring per dictation; long captures spill older PCM to disk.
    private let sessions = CaptureSessionRings()
    /// Ring of the newest dictation. A previous dictation keeps its own ring.
    var capture: SampleRing { sessions.current }
    /// Ring the open engine is writing into (nil when the mic is closed).
    private var activeRing: SampleRing?
    /// Config-change restarts in the current dictation.
    private var configRestarts = 0
    /// Engine config changed mid-dictation and capture could not be reopened.
    /// Called on the main queue.
    var onCaptureFailed: (() -> Void)?
    private var configObserver: NSObjectProtocol?
    private let targetSampleRate: Double = 16000
    private let lock = NSLock()
    private var isTapped = false

    /// Latest input RMS (~0…1) for the listening waveform HUD only.
    /// Written on the audio thread; read via `currentAudioLevel()`.
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
        // Device unplugged / default input switched / sample rate changed: the
        // engine stops itself. Main queue serializes with start/stop from AppState.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
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

    /// Swap in a fresh ring for a new dictation. Call before `startRecording()`;
    /// the previous dictation's ring stays with its transcriber.
    @discardableResult
    func beginSession() -> SampleRing {
        sessions.beginSession()
    }

    /// Open the mic into the current session ring (see `beginSession()`).
    func startRecording() {
        lock.lock()
        meterLevel = 0
        lock.unlock()
        configRestarts = 0
        openCapture(into: capture)
    }

    /// Engine reported a configuration change (device unplugged, default input
    /// switched). Mid-dictation: rebuild tap + converter for the new format and
    /// keep appending to the same session ring.
    private func handleConfigurationChange() {
        switch CaptureConfigurationChange.action(
            isCapturing: activeRing != nil,
            restartsThisSession: configRestarts
        ) {
        case .ignore:
            // Next startRecording() resets the engine and re-reads the format.
            return
        case .restartIntoSessionRing:
            guard let ring = activeRing else { return }
            configRestarts += 1
            NSLog("AudioRecorder: engine configuration changed mid-dictation — restarting capture")
            if !openCapture(into: ring) {
                stopEngine()
                onCaptureFailed?()
            }
        case .stop:
            NSLog("AudioRecorder: too many configuration changes — stopping capture")
            stopEngine()
            onCaptureFailed?()
        }
    }

    /// (Re)builds the input tap for the current device and starts the engine.
    /// Returns false when capture could not be opened.
    @discardableResult
    private func openCapture(into ring: SampleRing) -> Bool {
        activeRing = nil
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

        applyInputDeviceUID(inputDeviceUID)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard CaptureConfigurationChange.canCapture(
            sampleRate: inputFormat.sampleRate,
            channelCount: Int(inputFormat.channelCount)
        ) else {
            NSLog("AudioRecorder: invalid input format (mic permission / device?)")
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
            // The tap owns its session ring, so a late buffer never lands in the next dictation.
            self.processTapBuffer(buffer, sourceSR: inputFormat.sampleRate, into: ring)
        }
        isTapped = true

        do {
            try engine.start()
        } catch {
            NSLog("AudioRecorder: Failed to start engine: \(error)")
            inputNode.removeTap(onBus: 0)
            isTapped = false
            return false
        }
        activeRing = ring
        return true
    }

    /// Stop the mic but keep the capture ring for chunked STT.
    func stopEngine() {
        activeRing = nil
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        converter?.reset()
        lock.lock()
        meterLevel = 0
        lock.unlock()
    }

    /// Stop + materialize. Only for short clips (self-test). Long dictation uses `capture`.
    func stopRecording() -> [Float] {
        stopEngine()
        return capture.takeAllAndClear()
    }

    /// Clear the newest session (cancel paths while it is still recording).
    func clearCapture() {
        sessions.clear(capture)
    }

    /// Clear one finished session. Never touches a dictation started since.
    func clearCapture(_ ring: SampleRing) {
        sessions.clear(ring)
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

    /// Binds `AVAudioEngine` to the chosen input device before capture starts.
    /// nil / empty / unplugged UIDs bind the current system default explicitly:
    /// the engine lives for the whole app, so skipping the bind would leave it
    /// on whatever device was chosen before.
    private func applyInputDeviceUID(_ uid: String?) {
        guard let deviceID = InputDeviceResolver.deviceToBind(
            requestedUID: uid,
            available: AudioInputDevices.inputDeviceIDsByUID(),
            defaultDeviceID: AudioInputDevices.defaultInputDeviceID()
        ) else {
            NSLog("AudioRecorder: no input device to bind")
            return
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            NSLog("AudioRecorder: input node has no audio unit")
            return
        }
        var current = AudioDeviceID(0)
        var currentSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &current,
            &currentSize
        ) == noErr, current == deviceID {
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

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, sourceSR: Double, into ring: SampleRing) {
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
            appendPassthrough(buffer, frameCount: frameCount, into: ring)
            return
        }

        if let converter, let convertBuffer {
            convertAndAppend(buffer: buffer, converter: converter, convertBuffer: convertBuffer, into: ring)
            return
        }

        // Fallback: vDSP mono mix + linear interpolation (no converter available).
        fallbackResample(buffer: buffer, sourceSR: sourceSR, frameCount: frameCount, into: ring)
    }

    private func appendPassthrough(_ buffer: AVAudioPCMBuffer, frameCount: Int, into ring: SampleRing) {
        guard let channelData = buffer.floatChannelData else { return }
        ring.append(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    private func convertAndAppend(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        convertBuffer: AVAudioPCMBuffer,
        into ring: SampleRing
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

        ring.append(UnsafeBufferPointer(start: channelData[0], count: outFrames))
    }

    /// vDSP mono-mix + linear resample when AVAudioConverter cannot be created.
    private func fallbackResample(buffer: AVAudioPCMBuffer, sourceSR: Double, frameCount: Int, into ring: SampleRing) {
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
            ring.append(prefix)
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

        ring.append(output)
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
