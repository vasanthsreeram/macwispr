import Cocoa
import Carbon
import CoreGraphics

/// Global dictation hotkey (configurable; default ⌥Space).
///
/// Three layers (any one can detect; tap also swallows the chord):
/// 1. **CGEvent tap** — best: swallows the chord so it never types
/// 2. **Carbon RegisterEventHotKey** — reliable system hotkey path
/// 3. **NSEvent monitors** — backup (global needs Accessibility)
final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    /// Optional: Esc (or custom) while listening → discard without paste.
    var onCancel: (() -> Void)?

    /// Active dictation chord (default ⌥Space).
    private(set) var dictationChord: KeyChord = .defaultDictation
    /// Cancel chord (default Esc). `nil` = disabled.
    private(set) var cancelChord: KeyChord? = .defaultCancel

    /// When true, ignore dictation fires (UI is capturing a new shortcut).
    var isCapturingShortcut = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var isHotkeyHeld = false

    // Carbon global hotkey
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonHandlerRef: EventHandlerRef?
    private let carbonHotKeyID = EventHotKeyID(signature: OSType(0x4D575350), id: 1) // 'MWSP'

    /// Diagnostics (read from self-test / UI).
    private(set) var tapInstalled = false
    private(set) var carbonInstalled = false
    private(set) var monitorsInstalled = false
    private(set) var lastDownAt: Date?
    private(set) var lastUpAt: Date?
    private(set) var downCount = 0
    private(set) var upCount = 0

    /// True when at least one path that can receive global keys is live.
    var isArmed: Bool {
        tapInstalled || carbonInstalled
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func setDictationChord(_ chord: KeyChord) {
        dictationChord = chord
        if isArmed || eventTap != nil || carbonHotKeyRef != nil {
            register()
        }
    }

    func setCancelChord(_ chord: KeyChord?) {
        cancelChord = chord
        // Cancel is handled via tap/monitors only (no second Carbon ID required).
    }

    func register() {
        unregister()
        tapInstalled = installEventTap()
        carbonInstalled = installCarbonHotKey()
        installMonitors()
        installLocalMonitors()
        monitorsInstalled = keyMonitor != nil
        NSLog(
            "MacWispr hotkey: chord=%@ tap=%@ carbon=%@ monitors=%@ ax=%@",
            dictationChord.displayString as NSString,
            tapInstalled ? "yes" : "NO",
            carbonInstalled ? "yes" : "NO",
            monitorsInstalled ? "yes" : "NO",
            accessibilityTrusted ? "yes" : "NO"
        )
    }

    func ensureRegistered() {
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("MacWispr hotkey: re-enabled disabled tap")
        }

        let ax = AXIsProcessTrusted()
        let missingTap = eventTap == nil
        let missingCarbon = carbonHotKeyRef == nil
        if (missingTap && missingCarbon && keyMonitor == nil) || (ax && (missingTap || missingCarbon)) {
            register()
        }
    }

    func unregister() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
        localKeyMonitor = nil
        uninstallCarbonHotKey()
        isHotkeyHeld = false
        tapInstalled = false
        carbonInstalled = false
        monitorsInstalled = false
    }

    deinit { unregister() }

    // MARK: - Public inject for tests

    /// Simulate the current dictation chord for automated tests.
    func injectOptionSpace(down: Bool) {
        injectChord(dictationChord, down: down)
    }

    func injectChord(_ chord: KeyChord, down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let key = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: down) {
            key.flags = chord.cgEventFlags
            key.post(tap: .cghidEventTap)
        }
    }

    /// Directly exercise the handler with a synthetic CGEvent (does not need AX).
    @discardableResult
    func handleSyntheticKey(down: Bool, option: Bool = true) -> Bool {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: dictationChord.keyCode,
            keyDown: down
        ) else { return false }
        var flags = dictationChord.cgEventFlags
        if option { flags.insert(.maskAlternate) }
        event.flags = flags
        let type: CGEventType = down ? .keyDown : .keyUp
        _ = handle(type: type, event: event)
        return true
    }

    // MARK: - Event tap

    private func installEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            NSLog("MacWispr hotkey: CGEvent.tapCreate failed — grant Accessibility")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("MacWispr hotkey: tap was disabled; re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        if isCapturingShortcut {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Cancel (e.g. Esc) while a session might be live — always observe keyDown.
        if type == .keyDown,
           let cancel = cancelChord,
           cancel.matches(keyCode: keyCode, flags: flags)
        {
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            // Don't swallow Esc globally when not recording — AppState decides.
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown && dictationChord.matches(keyCode: keyCode, flags: flags) {
            fireDown(source: "tap")
            return nil // swallow
        }

        // Key-up of the primary key ends a hold (modifiers may already be up).
        if type == .keyUp && keyCode == CGKeyCode(dictationChord.keyCode) && isHotkeyHeld {
            fireUp(source: "tap")
            return nil
        }

        // If a required modifier is released while held, end the hold.
        if type == .flagsChanged && isHotkeyHeld {
            if !flagsStillIncludeRequiredModifiers(flags) {
                fireUp(source: "tap-mod")
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func flagsStillIncludeRequiredModifiers(_ flags: CGEventFlags) -> Bool {
        if dictationChord.command && !flags.contains(.maskCommand) { return false }
        if dictationChord.option && !flags.contains(.maskAlternate) { return false }
        if dictationChord.shift && !flags.contains(.maskShift) { return false }
        if dictationChord.control && !flags.contains(.maskControl) { return false }
        return true
    }

    // MARK: - Carbon hotkey (reliable detection)

    private func installCarbonHotKey() -> Bool {
        uninstallCarbonHotKey()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                mgr.handleCarbonEvent(event)
                return noErr
            },
            2,
            &eventTypes,
            refcon,
            &carbonHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("MacWispr hotkey: InstallEventHandler failed (%d)", handlerStatus)
            return false
        }

        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            UInt32(dictationChord.keyCode),
            dictationChord.carbonModifiers,
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard regStatus == noErr, let ref else {
            NSLog(
                "MacWispr hotkey: RegisterEventHotKey failed (%d) for %@ — tap/monitors still used",
                regStatus,
                dictationChord.displayString
            )
            uninstallCarbonHotKey()
            return false
        }
        carbonHotKeyRef = ref
        return true
    }

    private func uninstallCarbonHotKey() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        if let handler = carbonHandlerRef {
            RemoveEventHandler(handler)
            carbonHandlerRef = nil
        }
    }

    private func handleCarbonEvent(_ event: EventRef) {
        if isCapturingShortcut { return }

        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard err == noErr,
              hotKeyID.signature == carbonHotKeyID.signature,
              hotKeyID.id == carbonHotKeyID.id
        else { return }

        let kind = GetEventKind(event)
        if kind == UInt32(kEventHotKeyPressed) {
            fireDown(source: "carbon")
        } else if kind == UInt32(kEventHotKeyReleased) {
            fireUp(source: "carbon")
        }
    }

    // MARK: - Monitors

    private func installMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event)
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, !self.isCapturingShortcut else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var cg: CGEventFlags = []
            if flags.contains(.command) { cg.insert(.maskCommand) }
            if flags.contains(.option) { cg.insert(.maskAlternate) }
            if flags.contains(.shift) { cg.insert(.maskShift) }
            if flags.contains(.control) { cg.insert(.maskControl) }
            if self.isHotkeyHeld && !self.flagsStillIncludeRequiredModifiers(cg) {
                self.fireUp(source: "monitor-mod")
            }
        }
    }

    private func installLocalMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if self.handleNSEvent(event) {
                return nil // swallow in our windows
            }
            return event
        }
    }

    /// Returns true if the event was handled as our dictation hotkey.
    @discardableResult
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        if isCapturingShortcut { return false }

        if event.type == .keyDown,
           let cancel = cancelChord,
           cancel.matches(event)
        {
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            return false
        }

        guard event.keyCode == dictationChord.keyCode else { return false }

        if event.type == .keyDown && dictationChord.matches(event) {
            fireDown(source: "monitor")
            return true
        }
        if event.type == .keyUp && isHotkeyHeld {
            fireUp(source: "monitor")
            return true
        }
        return false
    }

    // MARK: - Shared fire (dedupes tap + carbon + monitors)

    private func fireDown(source: String) {
        guard !isCapturingShortcut else { return }
        guard !isHotkeyHeld else { return }
        isHotkeyHeld = true
        lastDownAt = Date()
        downCount += 1
        NSLog("MacWispr hotkey: DOWN via %@ (#%d) %@", source, downCount, dictationChord.displayString)
        DispatchQueue.main.async { [weak self] in self?.onHotkeyDown?() }
    }

    private func fireUp(source: String) {
        guard isHotkeyHeld else { return }
        isHotkeyHeld = false
        lastUpAt = Date()
        upCount += 1
        NSLog("MacWispr hotkey: UP via %@ (#%d)", source, upCount)
        DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
    }
}
