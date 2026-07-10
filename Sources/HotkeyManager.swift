import Cocoa
import CoreGraphics

/// Hold/press ⌥Space to dictate.
///
/// Uses an event tap (can swallow Space) **and** global monitors as backup.
/// When the tap swallows, monitors never see the event — no double-fire.
final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var isHotkeyHeld = false

    /// Diagnostics (read from self-test / logs).
    private(set) var tapInstalled = false
    private(set) var monitorsInstalled = false
    private(set) var lastDownAt: Date?
    private(set) var lastUpAt: Date?
    private(set) var downCount = 0
    private(set) var upCount = 0

    private static let spaceKeyCode: CGKeyCode = 49

    func register() {
        unregister()
        tapInstalled = installEventTap()
        // Always install monitors too — if the tap swallows, they never see
        // the event; if the tap misses, they still catch it.
        installMonitors()
        installLocalMonitors()
        monitorsInstalled = keyMonitor != nil
        NSLog(
            "MacWispr hotkey: tap=%@ monitors=%@",
            tapInstalled ? "yes" : "NO",
            monitorsInstalled ? "yes" : "NO"
        )
    }

    func ensureRegistered() {
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("MacWispr hotkey: re-enabled disabled tap")
        }
        if eventTap == nil && keyMonitor == nil {
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
        isHotkeyHeld = false
        tapInstalled = false
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
            if !isHotkeyHeld {
                isHotkeyHeld = true
                lastDownAt = Date()
                downCount += 1
                NSLog("MacWispr hotkey: DOWN (#%d)", downCount)
                DispatchQueue.main.async { [weak self] in self?.onHotkeyDown?() }
            }
            return nil // swallow
        }

        if type == .keyUp && keyCode == Self.spaceKeyCode && isHotkeyHeld {
            isHotkeyHeld = false
            lastUpAt = Date()
            upCount += 1
            NSLog("MacWispr hotkey: UP (#%d)", upCount)
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
            return nil
        }

        // Space keyUp without option still ends a hold.
        if type == .keyUp && keyCode == Self.spaceKeyCode && isHotkeyHeld {
            isHotkeyHeld = false
            lastUpAt = Date()
            upCount += 1
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
            return nil
        }

        if type == .flagsChanged && isHotkeyHeld && !option {
            isHotkeyHeld = false
            lastUpAt = Date()
            upCount += 1
            NSLog("MacWispr hotkey: Option released → UP")
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
        }

        return Unmanaged.passUnretained(event)
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
                self.isHotkeyHeld = false
                self.lastUpAt = Date()
                self.upCount += 1
                DispatchQueue.main.async { self.onHotkeyUp?() }
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
            if !isHotkeyHeld {
                isHotkeyHeld = true
                lastDownAt = Date()
                downCount += 1
                NSLog("MacWispr hotkey: DOWN via monitor (#%d)", downCount)
                DispatchQueue.main.async { [weak self] in self?.onHotkeyDown?() }
            }
            return true
        }
        if event.type == .keyUp && isHotkeyHeld {
            isHotkeyHeld = false
            lastUpAt = Date()
            upCount += 1
            NSLog("MacWispr hotkey: UP via monitor (#%d)", upCount)
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
            return true
        }
        return false
    }
}
