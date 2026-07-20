import AppKit
import Carbon
import CoreGraphics

/// A keyboard chord (modifiers + key) used for global hotkeys.
struct KeyChord: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    var command: Bool
    var option: Bool
    var shift: Bool
    var control: Bool

    static let defaultDictation = KeyChord(
        keyCode: UInt16(kVK_Space),
        command: false,
        option: true,
        shift: false,
        control: false
    )

    static let defaultCancel = KeyChord(
        keyCode: UInt16(kVK_Escape),
        command: false,
        option: false,
        shift: false,
        control: false
    )

    var hasModifier: Bool { command || option || shift || control }

    /// Safe enough for a global dictation hotkey (avoids bare letter keys stealing typing).
    var isSafeForGlobalDictation: Bool {
        if keyCode == UInt16(kVK_Escape) { return hasModifier } // bare Esc is for cancel
        if keyCode == UInt16(kVK_Space) { return hasModifier }
        if isFunctionKey { return true }
        return hasModifier
    }

    var isFunctionKey: Bool {
        keyCode >= UInt16(kVK_F1) && keyCode <= UInt16(kVK_F20)
    }

    // MARK: - Matching

    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard keyCode == CGKeyCode(self.keyCode) else { return false }
        let cmd = flags.contains(.maskCommand)
        let opt = flags.contains(.maskAlternate)
        let shf = flags.contains(.maskShift)
        let ctl = flags.contains(.maskControl)
        return cmd == command && opt == option && shf == shift && ctl == control
    }

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == keyCode else { return false }
        return flags.contains(.command) == command
            && flags.contains(.option) == option
            && flags.contains(.shift) == shift
            && flags.contains(.control) == control
    }

    /// Carbon `RegisterEventHotKey` modifier mask.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if command { m |= UInt32(cmdKey) }
        if option { m |= UInt32(optionKey) }
        if shift { m |= UInt32(shiftKey) }
        if control { m |= UInt32(controlKey) }
        return m
    }

    var cgEventFlags: CGEventFlags {
        var f: CGEventFlags = []
        if command { f.insert(.maskCommand) }
        if option { f.insert(.maskAlternate) }
        if shift { f.insert(.maskShift) }
        if control { f.insert(.maskControl) }
        return f
    }

    // MARK: - Display

    /// Individual keycap labels for SuperWhisper-style badges (e.g. `["⌥", "Space"]`).
    var badgeLabels: [String] {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyLabel)
        return parts
    }

    var displayString: String {
        badgeLabels.joined(separator: " ")
    }

    var keyLabel: String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Escape: return "esc"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        default:
            // Prefer characters from the current keyboard layout.
            if let s = Self.string(forKeyCode: keyCode), !s.isEmpty {
                return s.uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    static func from(event: NSEvent) -> KeyChord? {
        // Ignore pure modifier presses.
        let pureModifiers: Set<UInt16> = [
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Function),
            UInt16(kVK_CapsLock),
        ]
        if pureModifiers.contains(event.keyCode) { return nil }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeyChord(
            keyCode: event.keyCode,
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            control: flags.contains(.control)
        )
    }

    private static func string(forKeyCode keyCode: UInt16) -> String? {
        let inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyUnicodeKeyLayoutData
        ) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length: Int = 0
            let err = UCKeyTranslate(
                ptr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard err == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
