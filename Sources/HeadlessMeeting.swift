import Foundation
import MacWisprCore

/// `MacWispr --record-meeting <seconds>` — record a meeting for N seconds, transcribe
/// it, print `meeting.json` and the transcript, and exit. Release check for the
/// capture + transcription path; set MACWISPR_DATA_DIR to keep test runs separate.
enum HeadlessMeeting {
    static let flag = "--record-meeting"

    static var requestedSeconds: Double? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }

    @MainActor
    static func run(seconds: Double, state: AppState) {
        Task { @MainActor in
            let c = state.meetings
            c.start()
            guard c.isRecording else {
                print("FAIL start: \(c.lastError ?? "unknown")")
                exit(1)
            }
            FileHandle.standardError.write(Data("recording \(seconds)s…\n".utf8))
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            c.stop()
            while c.isBusy {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let store = AgentDataStore(paths: c.paths)
            guard let meta = store.meetings(limit: 1).first else {
                print("FAIL no meeting saved")
                exit(1)
            }
            if let data = try? AgentDataStore.makeEncoder().encode(meta) {
                print(String(decoding: data, as: UTF8.self))
            }
            print(store.transcriptMarkdown(id: meta.id) ?? "(no transcript)")
            exit(meta.status == .done ? 0 : 1)
        }
    }
}
