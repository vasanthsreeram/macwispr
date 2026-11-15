import Foundation

/// The user's insertion setting, as far as the decision is concerned.
public enum InsertionStyle: Sendable {
    /// Paste with ⌘V ("Pasting (fastest)").
    case paste
    /// Type the text as synthetic key events.
    case typeOut
    /// Leave the text on the clipboard; never send keys.
    case copyOnly
}

/// How a finished transcript reaches the frontmost app.
public enum InsertAction: Equatable, Sendable {
    /// Put text on the pasteboard and send ⌘V.
    case copyAndPaste
    /// Type the text as synthetic key events.
    case typeOut
    /// The user chose Copy only: update the pasteboard, send no keys. A success.
    case copy
    /// Paste/type was blocked, so only the pasteboard is updated; `reason` tells the user why.
    case copyOnly(reason: String)
}

/// Pure decision for `TextInserter`.
///
/// Synthetic key events need the Accessibility grant (post-event access).
/// While Secure Event Input is on (a password field is focused), macOS drops
/// synthetic keystrokes, so pasting would silently do nothing.
public enum InsertionDecision {
    public static let needsAccessibility = "Copied — turn on Accessibility for MacWispr to paste automatically"
    public static let secureInput = "Copied — a password field is blocking automatic paste. Press ⌘V."

    public static func decide(mode: InsertionStyle, canPostEvents: Bool, secureInputActive: Bool) -> InsertAction {
        if mode == .copyOnly { return .copy }
        if !canPostEvents { return .copyOnly(reason: needsAccessibility) }
        if secureInputActive { return .copyOnly(reason: secureInput) }
        return mode == .typeOut ? .typeOut : .copyAndPaste
    }
}

/// Picks the virtual key for the ⌘V paste shortcut.
///
/// Key equivalents follow the active keyboard layout, so ANSI V (0x09) is
/// ⌘K on Dvorak. Layouts such as "Dvorak - QWERTY ⌘" switch to QWERTY while
/// ⌘ is held, so the lookup must be made with ⌘ down.
public enum PasteKey {
    public static let ansiV: UInt16 = 0x09

    /// `translate(keyCode, commandHeld)` returns what the key types in the
    /// current layout, or nil.
    public static func keyCode(translate: (_ keyCode: UInt16, _ commandHeld: Bool) -> String?) -> UInt16 {
        func typesV(_ code: UInt16) -> Bool { translate(code, true)?.lowercased() == "v" }
        if typesV(ansiV) { return ansiV }
        return (0..<128).first(where: typesV) ?? ansiV
    }
}

/// What the transcript write does to the clipboard.
public struct ClipboardWrite: Equatable, Sendable {
    /// Mark `org.nspasteboard.TransientType`: clipboard managers skip it.
    public var transient: Bool
    /// Mark `org.nspasteboard.ConcealedType`: may be a password.
    public var concealed: Bool
    /// Put the user's previous clipboard back once the paste has landed.
    public var restoreAfterPaste: Bool

    public init(transient: Bool, concealed: Bool, restoreAfterPaste: Bool) {
        self.transient = transient
        self.concealed = concealed
        self.restoreAfterPaste = restoreAfterPaste
    }
}

/// The transcript borrows the clipboard only for ⌘V; elsewhere it stays
/// because the user (or a blocked paste) needs it there.
public enum ClipboardPolicy {
    /// Time for the target app to read the pasteboard after ⌘V.
    public static let restoreDelay: TimeInterval = 0.8

    /// nil: leave the clipboard untouched.
    public static func write(for action: InsertAction, secureInputActive: Bool) -> ClipboardWrite? {
        switch action {
        case .typeOut:
            return nil
        case .copyAndPaste:
            return ClipboardWrite(transient: true, concealed: secureInputActive, restoreAfterPaste: true)
        case .copy, .copyOnly:
            return ClipboardWrite(transient: false, concealed: secureInputActive, restoreAfterPaste: false)
        }
    }

    /// Restore only if nobody wrote the clipboard since our transcript.
    public static func shouldRestore(changeCountAfterWrite: Int, currentChangeCount: Int) -> Bool {
        changeCountAfterWrite == currentChangeCount
    }
}

/// Repairs a stale Accessibility entry.
///
/// TCC binds the grant to the code signature. After a re-sign (ad-hoc build →
/// Developer ID), System Settings can still show MacWispr switched on while
/// macOS denies it. Resetting the app's own entry and prompting again creates
/// a fresh entry for the current signature.
public enum AccessibilityRepair {
    public static let tccutilPath = "/usr/bin/tccutil"
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    public static func resetArguments(bundleID: String) -> [String] {
        ["reset", "Accessibility", bundleID]
    }
}
