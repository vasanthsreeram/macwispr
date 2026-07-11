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
    private var resampleScratch: [Float] = []
    /// Expected max frames per tap (engine may deliver slightly more than requested).
    private let maxTapFrames = 4096

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

        ensureScratchCapacity(frameCount: maxTapFrames, sourceSR: 48_000)

        // Clean up a prior session that never stopped cleanly.
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            NSLog("AudioRecorder: invalid input format (mic permission / device?)")
            return
        }

        ensureScratchCapacity(frameCount: maxTapFrames, sourceSR: inputFormat.sampleRate)

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
        lock.lock()
        let result = samples
        lock.unlock()
        return result
    }

    // MARK: - Audio thread

    /// Grow scratch once if the device delivers more frames than expected.
    private func ensureScratchCapacity(frameCount: Int, sourceSR: Double) {
        if monoScratch.count < frameCount {
            monoScratch = [Float](repeating: 0, count: frameCount)
        }
        let ratio = targetSampleRate / max(sourceSR, 1)
        let outCount = Int(ceil(Double(frameCount) * max(ratio, 1.0))) + 8
        if resampleScratch.count < outCount {
            resampleScratch = [Float](repeating: 0, count: outCount)
        }
    }

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, sourceSR: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        if frameCount > monoScratch.count || resampleScratch.isEmpty {
            ensureScratchCapacity(frameCount: frameCount, sourceSR: sourceSR)
        }

        let channelCount = Int(buffer.format.channelCount)
        let monoCount = mixToMono(
            channelData: channelData,
            frameCount: frameCount,
            channelCount: channelCount
        )

        let outputCount: Int
        if abs(sourceSR - targetSampleRate) < 1.0 {
            outputCount = monoCount
            // Point resampleScratch at mono for the append path without a second copy.
            // monoScratch already holds the data; copy into samples under the lock.
            lock.lock()
            samples.append(contentsOf: monoScratch.prefix(monoCount))
            lock.unlock()
            return
        }

        outputCount = resampleLinear(
            monoCount: monoCount,
            sourceSR: sourceSR,
            targetSR: targetSampleRate
        )

        lock.lock()
        samples.append(contentsOf: resampleScratch.prefix(outputCount))
        lock.unlock()
    }

    /// Writes mono into `monoScratch`. Returns frame count written.
    private func mixToMono(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channelCount: Int
    ) -> Int {
        if channelCount == 1 {
            _ = monoScratch.withUnsafeMutableBufferPointer { dest in
                memcpy(dest.baseAddress!, channelData[0], frameCount * MemoryLayout<Float>.size)
            }
            return frameCount
        }

        // Scalar mix — replaced by vDSP in a follow-up (#4 item 2).
        for i in 0..<frameCount {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += channelData[ch][i]
            }
            monoScratch[i] = sum / Float(channelCount)
        }
        return frameCount
    }

    /// Linear-interpolation resample from `monoScratch` into `resampleScratch`.
    /// Returns output frame count.
    private func resampleLinear(monoCount: Int, sourceSR: Double, targetSR: Double) -> Int {
        let ratio = targetSR / sourceSR
        let outputCount = Int(Double(monoCount) * ratio)
        guard outputCount > 0, monoCount > 0 else { return 0 }

        if resampleScratch.count < outputCount {
            resampleScratch = [Float](repeating: 0, count: outputCount)
        }

        let last = monoCount - 1
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let lower = Int(srcIndex)
            let upper = min(lower + 1, last)
            let frac = Float(srcIndex - Double(lower))
            resampleScratch[i] = monoScratch[lower] * (1 - frac) + monoScratch[upper] * frac
        }
        return outputCount
    }
}
