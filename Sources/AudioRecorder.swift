import AVFoundation
import Accelerate

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let targetSampleRate: Double = 16000
    private let lock = NSLock()
    private var isTapped = false

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

    func startRecording() {
        // Pre-size for ~60s of 16 kHz mono so appends rarely reallocate.
        samples = []
        samples.reserveCapacity(Int(targetSampleRate) * 60)

        // Clean up a prior session that never stopped cleanly.
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        converter = nil
        convertBuffer = nil
        usesPassthrough = false

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            NSLog("AudioRecorder: invalid input format (mic permission / device?)")
            return
        }

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
        lock.unlock()
        return result
    }

    // MARK: - Audio thread

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, sourceSR: Double) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

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
