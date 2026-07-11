import Foundation

/// Encodes mono float32 samples (already at `sampleRate`) to 16-bit PCM WAV.
enum AudioWAVEncoder {
    static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let pcm = int16PCM(from: samples)
        var data = Data()
        data.reserveCapacity(44 + pcm.count)

        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        let riffSize = 36 + dataSize

        // RIFF header
        data.append(ascii: "RIFF")
        data.append(u32: riffSize)
        data.append(ascii: "WAVE")

        // fmt chunk
        data.append(ascii: "fmt ")
        data.append(u32: 16) // PCM chunk size
        data.append(u16: 1) // PCM format
        data.append(u16: channels)
        data.append(u32: UInt32(sampleRate))
        data.append(u32: byteRate)
        data.append(u16: blockAlign)
        data.append(u16: bitsPerSample)

        // data chunk
        data.append(ascii: "data")
        data.append(u32: dataSize)
        data.append(pcm)

        return data
    }

    /// Raw little-endian 16-bit PCM (no container) — useful for ElevenLabs pcm_s16le_16.
    static func pcm16Data(from samples: [Float]) -> Data {
        int16PCM(from: samples)
    }

    private static func int16PCM(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var value = Int16((clamped * Float(Int16.max)).rounded())
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}

private extension Data {
    mutating func append(ascii: String) {
        append(contentsOf: ascii.utf8)
    }

    mutating func append(u16: UInt16) {
        var value = u16.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func append(u32: UInt32) {
        var value = u32.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
