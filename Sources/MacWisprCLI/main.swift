import Foundation
import MacWisprCore

// `macwispr` — read MacWispr dictation history and meeting recordings from the
// shell, or serve them to AI agents over MCP (`macwispr mcp`). Read-only.

let usage = """
usage: macwispr <command> [options]

  history   [--limit N] [--since 7d|24h|2026-10-01] [--search TEXT] [--json]
  meetings  [--limit N] [--json]
  meeting   <id|latest> [--json] [--files]
  search    <TEXT> [--limit N] [--json]
  paths     data folder and file locations
  mcp       MCP server over stdio (for Claude Code, Cursor, Grok, Codex…)

Data folder: \(MacWisprPaths.default.root.path)  (override with MACWISPR_DATA_DIR)
"""

struct Args {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ raw: ArraySlice<String>) {
        let valued: Set<String> = ["--limit", "--since", "--search"]
        var it = raw.makeIterator()
        while let a = it.next() {
            if valued.contains(a) {
                options[a] = it.next() ?? ""
            } else if a.hasPrefix("--") {
                flags.insert(a)
            } else {
                positional.append(a)
            }
        }
    }

    var limit: Int? { options["--limit"].flatMap(Int.init) }
    var json: Bool { flags.contains("--json") }
}

func fail(_ msg: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(code)
}

func printJSON<T: Encodable>(_ value: T) {
    guard let data = try? AgentDataStore.makeEncoder().encode(value) else { fail("encode failed", code: 1) }
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

let localTime: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
}()

let store = AgentDataStore()
let argv = CommandLine.arguments
guard argv.count >= 2 else { print(usage); exit(0) }
let command = argv[1]
let args = Args(argv.dropFirst(2))

switch command {
case "history":
    var since: Date?
    if let raw = args.options["--since"] {
        guard let d = SinceParser.parse(raw) else { fail("bad --since: \(raw)") }
        since = d
    }
    let entries = store.dictations(since: since, query: args.options["--search"], limit: args.limit ?? (args.json ? nil : 50))
    if args.json { printJSON(entries); break }
    if entries.isEmpty { print("No dictations.") }
    for e in entries {
        print("[\(localTime.string(from: e.timestamp))] \(e.text)")
    }

case "meetings":
    let list = store.meetings(limit: args.limit)
    if args.json { printJSON(list); break }
    if list.isEmpty { print("No meetings recorded yet.") }
    for m in list {
        print("\(m.id)  \(m.title)  \(UsageClock.format(seconds: m.durationSeconds))  \(m.status.rawValue)  \(m.wordCount) words")
    }

case "meeting":
    guard let id = store.resolveMeetingID(args.positional.first ?? "latest") else {
        fail("meeting not found: \(args.positional.first ?? "latest")", code: 1)
    }
    if args.flags.contains("--files") {
        let files = store.meetingFiles(id: id)
        if args.json { printJSON(files); break }
        for key in files.keys.sorted() { print("\(key): \(files[key]!)") }
        break
    }
    if args.json {
        struct Full: Encodable {
            let meeting: MeetingMetadata
            let transcript: MeetingTranscript?
            let files: [String: String]
        }
        printJSON(Full(meeting: store.meeting(id: id)!, transcript: store.transcript(id: id), files: store.meetingFiles(id: id)))
        break
    }
    if let md = store.transcriptMarkdown(id: id) {
        print(md)
    } else if let meta = store.meeting(id: id) {
        print("# \(meta.title)\n\nStatus: \(meta.status.rawValue) — no transcript yet.")
    }

case "search":
    let q = args.positional.joined(separator: " ")
    guard !q.isEmpty else { fail("usage: macwispr search <TEXT>") }
    let hits = store.search(q, limit: args.limit ?? 50)
    if args.json { printJSON(hits); break }
    if hits.isEmpty { print("No matches.") }
    for h in hits {
        let at = h.offsetSeconds.map { " @\(MeetingTranscriptFormatter.timestamp($0))" } ?? ""
        print("[\(localTime.string(from: h.timestamp))] \(h.kind) \(h.id)\(at): \(h.text)")
    }

case "paths":
    let p = store.paths
    printJSON([
        "root": p.root.path,
        "history": p.historyFile.path,
        "meetings": p.meetingsDir.path,
        "agents_readme": p.agentsReadme.path,
    ])

case "mcp":
    MCPServer(store: store).run()

case "-h", "--help", "help":
    print(usage)

default:
    fail("unknown command: \(command)\n\n\(usage)")
}
