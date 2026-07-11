import Cocoa
import Carbon
import CoreGraphics

/// Hold/press ⌥Space to dictate.
///
/// Three layers (any one can detect; tap also swallows Space):
/// 1. **CGEvent tap** — best: swallows ⌥Space so it never types
/// 2. **Carbon RegisterEventHotKey** — reliable system hotkey path
/// 3. **NSEvent monitors** — backup (global needs Accessibility)
final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

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

    private static let spaceKeyCode: CGKeyCode = 49

    /// True when at least one path that can receive global keys is live.
    /// Monitors alone do **not** count — without Accessibility they install
    /// but never fire for other apps (which looked like “armed but dead”).
    var isArmed: Bool {
        tapInstalled || carbonInstalled
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func register() {
        unregister()
        tapInstalled = installEventTap()
        carbonInstalled = installCarbonHotKey()
        // Always install monitors too — if the tap swallows, they never see
        // the event; if the tap misses, they still catch it.
        installMonitors()
        installLocalMonitors()
        monitorsInstalled = keyMonitor != nil
        NSLog(
            "MacWispr hotkey: tap=%@ carbon=%@ monitors=%@ ax=%@",
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
        // Without Accessibility the tap/carbon fail AND global monitors are
        // installed but never receive events — so a non-nil monitor doesn't
        // mean working. Re-register when AX is granted or nothing is armed.
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

    /// Simulate ⌥Space for automated tests (posts HID events into the system stream).
    func injectOptionSpace(down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        // Post Option flag change first when going down, for realism.
        if down {
            if let optDown = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: true) { // left option
                optDown.flags = .maskAlternate
                optDown.post(tap: .cghidEventTap)
            }
        }
        if let space = CGEvent(keyboardEventSource: source, virtualKey: Self.spaceKeyCode, keyDown: down) {
            space.flags = .maskAlternate
            space.post(tap: .cghidEventTap)
        }
        if !down {
            if let optUp = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: false) {
                optUp.flags = []
                optUp.post(tap: .cghidEventTap)
            }
        }
    }

    /// Directly exercise the handler with a synthetic CGEvent (does not need AX).
    @discardableResult
    func handleSyntheticKey(down: Bool, option: Bool = true) -> Bool {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: Self.spaceKeyCode,
            keyDown: down
        ) else { return false }
        if option { event.flags = .maskAlternate }
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

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let option = (event.flags.rawValue & CGEventFlags.maskAlternate.rawValue) != 0

        if type == .keyDown && keyCode == Self.spaceKeyCode && option {
            fireDown(source: "tap")
            return nil // swallow
        }

        // Space keyUp ends a hold (with or without Option still down).
        if type == .keyUp && keyCode == Self.spaceKeyCode && isHotkeyHeld {
            fireUp(source: "tap")
            return nil
        }

        if type == .flagsChanged && isHotkeyHeld && !option {
            fireUp(source: "tap-option")
        }

        return Unmanaged.passUnretained(event)
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
            UInt32(kVK_Space),
            UInt32(optionKey),
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard regStatus == noErr, let ref else {
            NSLog("MacWispr hotkey: RegisterEventHotKey failed (%d) — grant Accessibility", regStatus)
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
            guard let self else { return }
            let option = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            if self.isHotkeyHeld && !option {
                self.fireUp(source: "monitor-option")
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

    /// Returns true if the event was handled as our hotkey.
    @discardableResult
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        let option = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
        guard event.keyCode == Self.spaceKeyCode else { return false }

        if event.type == .keyDown && option {
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
        guard !isHotkeyHeld else { return }
        isHotkeyHeld = true
        lastDownAt = Date()
        downCount += 1
        NSLog("MacWispr hotkey: DOWN via %@ (#%d)", source, downCount)
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
