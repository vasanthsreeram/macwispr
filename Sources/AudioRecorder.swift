import AVFoundation
import Accelerate

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let targetSampleRate: Double = 16000
    private let lock = NSLock()

    func startRecording() {
        samples = []

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let resampled = self.resample(buffer: buffer, from: inputFormat.sampleRate, to: self.targetSampleRate)
            self.lock.lock()
            self.samples.append(contentsOf: resampled)
            self.lock.unlock()
        }

        do {
            try engine.start()
        } catch {
            print("AudioRecorder: Failed to start engine: \(error)")
        }
    }

    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
