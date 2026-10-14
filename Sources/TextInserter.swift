import Cocoa
import Carbon
import MacWisprCore

/// Result of trying to put transcribed text into the user's workflow.
enum InsertOutcome: Equatable {
    case ok
    /// Text is on the clipboard, but synthetic paste/type needs Accessibility.
    case clipboardOnly(reason: String)
    case failed(reason: String)
}

final class TextInserter: @unchecked Sendable {
    /// Serial queue for character type-out so `usleep` never blocks the main actor.
    private let typeQueue = DispatchQueue(label: "com.macwispr.textinserter.type")

    /// Insert text per mode. The pasteboard always gets the text first, so it
    /// is never lost. Synthetic ⌘V / keystrokes need Accessibility and are
    /// dropped by macOS while Secure Event Input is on (password fields).
    @discardableResult
    func insert(text: String, mode: InsertionMode) -> InsertOutcome {
        guard !text.isEmpty else { return .failed(reason: "Empty transcription") }

        copyToClipboard(text)
        let action = InsertionDecision.decide(
            typeOut: mode == .typeOut,
            canPostEvents: Self.canPostEvents,
            secureInputActive: IsSecureEventInputEnabled()
        )
        switch action {
        case .copyOnly(let reason):
            return .clipboardOnly(reason: reason)
        case .typeOut:
            typeTextAsync(text)
            return .ok
        case .copyAndPaste:
            pasteFromClipboard()
            return .ok
        }
    }

    /// Accessibility grant that covers posting synthetic key events.
    static var canPostEvents: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    /// Update the general pasteboard without synthesizing paste/type.
    /// Used after async polish so the user can re-paste the improved text.
    func copyToClipboardOnly(_ text: String) {
        guard !text.isEmpty else { return }
        copyToClipboard(text)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pasteFromClipboard() {
        // One event source for the key-down + key-up pair.
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Character type-out on a background queue; one CGEventSource for the whole string.
    private func typeTextAsync(_ text: String) {
        typeQueue.async { [text] in
            Self.typeText(text)
        }
    }

    private static func typeText(_ text: String) {
        // Create the event source once per insertion, not per character (#4 item 6).
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for char in text {
            let str = String(char)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                let utf16 = Array(str.utf16)
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }
            // Small gap so the target app's input queue keeps up; off main actor.
            usleep(5000)
        }
    }
}
