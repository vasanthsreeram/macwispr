import Cocoa
import CoreGraphics

/// Hold ⌥Space to dictate. Prefers an event tap so Space is swallowed
/// (doesn’t type into the focused app); falls back to a global monitor.
final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var isHotkeyHeld = false

    private static let spaceKeyCode: CGKeyCode = 49

    func register() {
        unregister()
        if !installEventTap() {
            installMonitors()
        }
    }

    func ensureRegistered() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
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
        keyMonitor = nil
        flagsMonitor = nil
        isHotkeyHeld = false
    }

    deinit { unregister() }

    // MARK: - Event tap (can swallow Space)

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
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let option = (event.flags.rawValue & CGEventFlags.maskAlternate.rawValue) != 0

        if type == .keyDown && keyCode == Self.spaceKeyCode && option {
            if !isHotkeyHeld {
                isHotkeyHeld = true
                DispatchQueue.main.async { [weak self] in self?.onHotkeyDown?() }
            }
            return nil // swallow
        }

        if type == .keyUp && keyCode == Self.spaceKeyCode && isHotkeyHeld {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
            return nil
        }

        if type == .flagsChanged && isHotkeyHeld && !option {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp?() }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Fallback monitors (cannot swallow Space)

    private func installMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            let option = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            if event.keyCode == Self.spaceKeyCode && option {
                if event.type == .keyDown && !self.isHotkeyHeld {
                    self.isHotkeyHeld = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                } else if event.type == .keyUp && self.isHotkeyHeld {
                    self.isHotkeyHeld = false
                    DispatchQueue.main.async { self.onHotkeyUp?() }
                }
            }
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let option = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            if self.isHotkeyHeld && !option {
                self.isHotkeyHeld = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
            }
        }
    }
}
