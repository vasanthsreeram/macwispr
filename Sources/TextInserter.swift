import Cocoa

/// Result of trying to put transcribed text into the user's workflow.
enum InsertOutcome: Equatable {
    case ok
    /// Text is on the clipboard, but synthetic paste/type needs Accessibility.
    case clipboardOnly(reason: String)
    case failed(reason: String)
}

final class TextInserter: @unchecked Sendable {
    /// Insert text per mode. Always attempts clipboard when mode wants it.
    /// Synthetic ⌘V / keystrokes require Accessibility — without it we leave
    /// text on the pasteboard and report clipboardOnly so the UI can explain.
    @discardableResult
    func insert(text: String, mode: InsertionMode) -> InsertOutcome {
        guard !text.isEmpty else { return .failed(reason: "Empty transcription") }

        let ax = AXIsProcessTrusted()
        switch mode {
        case .clipboard:
            copyToClipboard(text)
            if !ax {
                return .clipboardOnly(reason: "Copied — enable Accessibility to auto-paste")
            }
            pasteFromClipboard()
            return .ok

        case .typeOut:
            if !ax {
                copyToClipboard(text)
                return .clipboardOnly(reason: "Copied — enable Accessibility to type into apps")
            }
            typeText(text)
            return .ok

        case .both:
            copyToClipboard(text)
            if !ax {
                return .clipboardOnly(reason: "Copied — enable Accessibility to auto-paste")
            }
            pasteFromClipboard()
            return .ok
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pasteFromClipboard() {
        // Simulate Cmd+V to paste into the active app (needs Accessibility).
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        for char in text {
            let str = String(char)
            let source = CGEventSource(stateID: .combinedSessionState)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                let utf16 = Array(str.utf16)
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }
            usleep(5000)
        }
    }
}
