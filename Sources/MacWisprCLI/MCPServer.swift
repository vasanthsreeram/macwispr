import Foundation
import MacWisprCore

/// Minimal MCP server (JSON-RPC 2.0, newline-delimited over stdio). Tools only, read-only.
struct MCPServer {
    let store: AgentDataStore

    static let protocolVersion = "2025-06-18"

    static let tools: [[String: Any]] = [
        tool(
            "list_dictations",
            "List MacWispr voice dictations (newest first). Each has id, text, timestamp (ISO 8601), duration in seconds, wordCount.",
            [
                "limit": ["type": "integer", "description": "Max results (default 50)."],
                "since": ["type": "string", "description": "Only dictations after this: ISO date, yyyy-MM-dd, or relative like 30m, 24h, 7d, 2w."],
                "query": ["type": "string", "description": "Case-insensitive text filter."],
            ]
        ),
        tool(
            "list_meetings",
            "List recorded meetings (newest first) with id, title, startedAt, durationSeconds, status, wordCount.",
            ["limit": ["type": "integer", "description": "Max results (default 20)."]]
        ),
        tool(
            "get_meeting",
            "Get one meeting: metadata, transcript, and absolute paths to its audio files. 'Me' = the user's microphone, 'Others' = audio from other apps.",
            [
                "id": ["type": "string", "description": "Meeting id from list_meetings, or 'latest'."],
                "format": ["type": "string", "enum": ["markdown", "json"], "description": "markdown (default): readable transcript with timestamps. json: segments with start/end seconds and source."],
            ],
            required: ["id"]
        ),
        tool(
            "search_transcripts",
            "Search dictations and meeting transcripts for text. Returns matching dictations and meeting segments with timestamps.",
            [
                "query": ["type": "string", "description": "Text to find (case-insensitive)."],
                "limit": ["type": "integer", "description": "Max results (default 50)."],
            ],
            required: ["query"]
        ),
    ]

    static func tool(_ name: String, _ description: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": props, "required": required],
            "annotations": ["readOnlyHint": true],
        ]
    }

    func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            if let reply = handle(msg) { send(reply) }
        }
    }

    func handle(_ msg: [String: Any]) -> [String: Any]? {
        let method = msg["method"] as? String ?? ""
        // Notifications have no id and get no reply.
        guard let id = msg["id"] else { return nil }
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return result(id, [
                "protocolVersion": requested ?? Self.protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "macwispr", "version": "1.0.0"],
                "instructions": "Read-only access to the user's MacWispr voice dictation history and meeting recordings (audio + transcripts) stored on this Mac.",
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try callTool(name, arguments)
                return result(id, ["content": [["type": "text", "text": text]], "isError": false])
            } catch let e as ToolError {
                return result(id, ["content": [["type": "text", "text": e.message]], "isError": true])
            } catch {
                return result(id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
            }
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    struct ToolError: Error { let message: String }

    func callTool(_ name: String, _ a: [String: Any]) throws -> String {
        func int(_ key: String) -> Int? {
            if let i = a[key] as? Int { return i }
            if let s = a[key] as? String { return Int(s) }
            return nil
        }
        switch name {
        case "list_dictations":
            var since: Date?
            if let raw = a["since"] as? String, !raw.isEmpty {
                guard let d = SinceParser.parse(raw) else { throw ToolError(message: "Bad 'since': \(raw)") }
                since = d
            }
            return try encode(store.dictations(since: since, query: a["query"] as? String, limit: int("limit") ?? 50))
        case "list_meetings":
            return try encode(store.meetings(limit: int("limit") ?? 20))
        case "get_meeting":
            let raw = a["id"] as? String ?? "latest"
            guard let id = store.resolveMeetingID(raw), let meta = store.meeting(id: id) else {
                throw ToolError(message: "Meeting not found: \(raw). Call list_meetings for ids.")
            }
            let files = store.meetingFiles(id: id)
            if (a["format"] as? String) == "json" {
                struct Full: Encodable {
                    let meeting: MeetingMetadata
                    let transcript: MeetingTranscript?
                    let files: [String: String]
                }
                return try encode(Full(meeting: meta, transcript: store.transcript(id: id), files: files))
            }
            var md = store.transcriptMarkdown(id: id) ?? "# \(meta.title)\n\nStatus: \(meta.status.rawValue) — no transcript yet."
            md += "\n\n## Files\n"
            for key in files.keys.sorted() { md += "- \(key): \(files[key]!)\n" }
            return md
        case "search_transcripts":
            guard let q = a["query"] as? String, !q.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ToolError(message: "'query' is required")
            }
            return try encode(store.search(q, limit: int("limit") ?? 50))
        default:
            throw ToolError(message: "Unknown tool: \(name)")
        }
    }

    func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try AgentDataStore.makeEncoder().encode(value), as: UTF8.self)
    }

    func result(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
