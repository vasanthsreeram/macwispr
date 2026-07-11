import AVFoundation
import Accelerate

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let targetSampleRate: Double = 16000
    private let lock = NSLock()
    private var isTapped = false

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
        samples = []

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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let resampled = self.resample(buffer: buffer, from: inputFormat.sampleRate, to: self.targetSampleRate)
            self.lock.lock()
            self.samples.append(contentsOf: resampled)
            self.lock.unlock()
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

    private func resample(buffer: AVAudioPCMBuffer, from sourceSR: Double, to targetSR: Double) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Mix to mono if stereo
        var mono = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            memcpy(&mono, channelData[0], frameCount * MemoryLayout<Float>.size)
        } else {
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                mono[i] = sum / Float(channelCount)
            }
        }

        // Resample if needed
        if abs(sourceSR - targetSR) < 1.0 {
            return mono
        }

        let ratio = targetSR / sourceSR
        let outputCount = Int(Double(frameCount) * ratio)
        var output = [Float](repeating: 0, count: outputCount)

        // Linear interpolation resampling
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let lower = Int(srcIndex)
            let upper = min(lower + 1, frameCount - 1)
            let frac = Float(srcIndex - Double(lower))
            output[i] = mono[lower] * (1 - frac) + mono[upper] * frac
        }

        return output
    }
}
