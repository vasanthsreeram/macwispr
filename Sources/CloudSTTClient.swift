import Foundation

/// Cloud speech-to-text and optional OpenAI polish. Uses the user's BYOK keys only.
enum CloudSTTClient {
    // MARK: - OpenAI STT

    /// OpenAI audio transcriptions API.
    /// Model: gpt-4o-mini-transcribe (fast + high quality for dictation).
    static func transcribeOpenAI(
        samples: [Float],
        apiKey: String,
        language: String? = nil,
        prompt: String? = nil
    ) async throws -> String {
        let wav = AudioWAVEncoder.encode(samples: samples)
        var fields: [MultipartField] = [
            .text(name: "model", value: "gpt-4o-mini-transcribe"),
            .text(name: "response_format", value: "json"),
            .file(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wav),
        ]
        if let language, !language.isEmpty {
            fields.append(.text(name: "language", value: language))
        }
        if let prompt, !prompt.isEmpty {
            // Biases recognition toward custom vocab / domain terms.
            fields.append(.text(name: "prompt", value: prompt))
        }

        let (data, status) = try await multipartPOST(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            fields: fields,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )

        guard (200...299).contains(status) else {
            throw CloudSTTError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String
        {
            return text
        }
        // Some models return plain text when response_format is text.
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, !text.hasPrefix("{")
        {
            return text
        }
        throw CloudSTTError.invalidResponse
    }

    // MARK: - ElevenLabs STT

    /// ElevenLabs Speech-to-Text (Scribe v2).
    static func transcribeElevenLabs(
        samples: [Float],
        apiKey: String,
        language: String? = nil,
        keyterms: [String] = []
    ) async throws -> String {
        let pcm = AudioWAVEncoder.pcm16Data(from: samples)
        var fields: [MultipartField] = [
            .text(name: "model_id", value: "scribe_v2"),
            .text(name: "file_format", value: "pcm_s16le_16"),
            .text(name: "tag_audio_events", value: "false"),
            .file(name: "file", filename: "audio.pcm", mimeType: "application/octet-stream", data: pcm),
        ]
        if let language, !language.isEmpty {
            fields.append(.text(name: "language_code", value: language))
        }
        // Keyterms improve recognition of custom vocab (billed surcharge by ElevenLabs).
        for term in keyterms.prefix(100) {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 50 else { continue }
            fields.append(.text(name: "keyterms", value: cleaned))
        }

        let (data, status) = try await multipartPOST(
            url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
            fields: fields,
            headers: ["xi-api-key": apiKey]
        )

        guard (200...299).contains(status) else {
            throw CloudSTTError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String
        {
            return text
        }
        throw CloudSTTError.invalidResponse
    }

    // MARK: - OpenAI polish

    static func polishOpenAI(text: String, apiKey: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard trimmed.split(whereSeparator: \.isWhitespace).count >= 3 else { return text }

        let system = """
            You are a careful editor for voice dictation transcripts.
            Fix grammar, punctuation, capitalization, and sentence structure.
            Keep the original meaning and wording as close as possible.
            Do not add explanations, quotes, or commentary.
            Output only the corrected transcript.
            """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": trimmed],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            throw CloudSTTError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CloudSTTError.invalidResponse
        }

        let cleaned = sanitizePolish(content)
        return cleaned.isEmpty ? text : cleaned
    }

    private static func sanitizePolish(_ output: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")),
           s.count > 1
        {
            s = String(s.dropFirst().dropLast())
        }
        if s.lowercased().hasPrefix("corrected:"), s.count > 11 {
            s = String(s.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Multipart helper

    private enum MultipartField {
        case text(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    private static func multipartPOST(
        url: URL,
        fields: [MultipartField],
        headers: [String: String]
    ) async throws -> (Data, Int) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        for field in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            switch field {
            case .text(let name, let value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            case .file(let name, let filename, let mimeType, let data):
                body.append(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                        .data(using: .utf8)!
                )
                body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 120
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }
}

enum CloudSTTError: LocalizedError {
    case missingAPIKey(String)
    case http(status: Int, body: String)
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Add your \(provider) API key in Settings → API Keys."
        case .http(let status, let body):
            let snippet = body
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(180)
            if snippet.isEmpty {
                return "Cloud API error (HTTP \(status))."
            }
            return "Cloud API error (HTTP \(status)): \(snippet)"
        case .invalidResponse:
            return "Cloud API returned an unexpected response."
        case .notConfigured:
            return "Cloud transcription is not configured."
        }
    }
}
