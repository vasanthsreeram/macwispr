import Cocoa

final class TextInserter: @unchecked Sendable {
    func insert(text: String, mode: InsertionMode) {
        switch mode {
        case .clipboard:
            copyToClipboard(text)
            pasteFromClipboard()
        case .typeOut:
            typeText(text)
        case .both:
            copyToClipboard(text)
            pasteFromClipboard()
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pasteFromClipboard() {
        // Simulate Cmd+V to paste into the active app
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        // Use CGEvents to type each character
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
            // Small delay to avoid overwhelming the target app
            usleep(5000)
        }
    }
}
