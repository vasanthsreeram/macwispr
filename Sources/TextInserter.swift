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
    /// Clipboard to put back after the last paste (main thread only).
    private var pendingRestore: PasteboardTransfer.Session?

    /// Insert text per mode. Synthetic ⌘V / keystrokes need Accessibility and
    /// are dropped by macOS while Secure Event Input is on (password fields);
    /// then the text is left on the clipboard so it is never lost. A paste
    /// borrows the clipboard and restores the user's contents afterwards.
    @discardableResult
    func insert(text: String, mode: InsertionMode) -> InsertOutcome {
        guard !text.isEmpty else { return .failed(reason: "Empty transcription") }

        let secureInput = IsSecureEventInputEnabled()
        let action = InsertionDecision.decide(
            mode: mode.style,
            canPostEvents: Self.canPostEvents,
            secureInputActive: secureInput
        )
        if let plan = ClipboardPolicy.write(for: action, secureInputActive: secureInput) {
            let pasteboard = NSPasteboard.general
            let session = PasteboardTransfer.begin(text: text, plan: plan, on: pasteboard, pending: pendingRestore)
            pendingRestore = session
            if let session { scheduleRestore(session) }
        }
        switch action {
        case .copy:
            return .ok
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

    private func scheduleRestore(_ session: PasteboardTransfer.Session) {
        DispatchQueue.main.asyncAfter(deadline: .now() + ClipboardPolicy.restoreDelay) { [weak self] in
            guard let self, let pending = self.pendingRestore, pending.changeCount == session.changeCount else { return }
            self.pendingRestore = nil
            PasteboardTransfer.finish(pending, on: .general)
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
        let vKey = Self.pasteKeyCode()
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// The key that types "v" with ⌘ held in the current keyboard layout
    /// (Dvorak: not ANSI V), falling back to ANSI V.
    private static func pasteKeyCode() -> CGKeyCode {
        let inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyUnicodeKeyLayoutData
        ) else { return CGKeyCode(PasteKey.ansiV) }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return CGKeyCode(PasteKey.ansiV)
            }
            return CGKeyCode(PasteKey.keyCode { keyCode, commandHeld in
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length: Int = 0
                let err = UCKeyTranslate(
                    ptr,
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    commandHeld ? UInt32((cmdKey >> 8) & 0xFF) : 0,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )
                guard err == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: chars, count: length)
            })
        }
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

extension InsertionMode {
    var style: InsertionStyle {
        switch self {
        case .clipboard: return .copyOnly
        case .typeOut: return .typeOut
        case .both: return .paste
        }
    }
}
