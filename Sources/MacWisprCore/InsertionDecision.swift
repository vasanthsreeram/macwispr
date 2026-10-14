import Foundation

/// How a finished transcript reaches the frontmost app.
public enum InsertAction: Equatable, Sendable {
    /// Put text on the pasteboard and send ⌘V.
    case copyAndPaste
    /// Type the text as synthetic key events.
    case typeOut
    /// Only the pasteboard is updated; `reason` tells the user why.
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

    public static func decide(typeOut: Bool, canPostEvents: Bool, secureInputActive: Bool) -> InsertAction {
        if !canPostEvents { return .copyOnly(reason: needsAccessibility) }
        if secureInputActive { return .copyOnly(reason: secureInput) }
        return typeOut ? .typeOut : .copyAndPaste
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
