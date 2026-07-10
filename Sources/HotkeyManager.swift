import Cocoa
import CoreGraphics

/// Hold ⌥Space to dictate. Uses a session event tap so Space is *swallowed*
/// and never reaches the focused app (cursor won't jump / insert spaces).
///
/// Falls back to global monitors if the tap cannot be created (Accessibility).
final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyHeld = false
    private var healthTimer: Timer?

    private static let spaceKeyCode: Int64 = 49 // kVK_Space

    /// Re-create / re-enable the event tap (e.g. after Accessibility grant).
    func ensureRegistered() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("MacWispr: re-enabled disabled event tap")
            }
            return
        }
        register()
    }

    func register() {
        unregister()

        // Only real key events in the mask. The special "tap disabled" events
        // (0xFFFFFFFE / 0xFFFFFFFF) are delivered automatically — do NOT
        // `1 <<` them; that overflows the CGEventMask.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // must NOT be listenOnly — we need to swallow
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: refcon
        )

        if let tap {
            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("MacWispr: event tap registered (⌥Space will be swallowed)")
        } else {
            NSLog("MacWispr: event tap FAILED — need Accessibility. Using observe-only fallback.")
            installFallbackMonitors()
        }

        // Also listen locally (when one of our windows is focused, global
        // monitors alone can miss events depending on focus path).
        installLocalMonitors()

        // Periodically re-enable if macOS disabled the tap after a stall.
        DispatchQueue.main.async { [weak self] in
            self?.healthTimer?.invalidate()
            self?.healthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.ensureRegistered()
            }
            if let healthTimer = self?.healthTimer {
                RunLoop.main.add(healthTimer, forMode: .common)
            }
        }
    }

    func unregister() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        removeFallbackMonitors()
        removeLocalMonitors()
        isHotkeyHeld = false
    }

    deinit {
        unregister()
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // System may disable the tap after timeout — re-enable immediately.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("MacWispr: event tap was disabled (\(type.rawValue)); re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        // Only keyboard-like events have a meaningful keycode.
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasOption = Self.hasOptionModifier(event.flags)

        // ⌥Space keyDown (and key-repeat): swallow so Space never types.
        if type == .keyDown && keyCode == Self.spaceKeyCode && hasOption {
            if !isHotkeyHeld {
                isHotkeyHeld = true
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyDown?()
                }
            }
            return nil // swallow
        }

        // Space keyUp while we were dictating: swallow + stop.
        // (Don't require Option still held — user often releases Option first.)
        if type == .keyUp && keyCode == Self.spaceKeyCode && isHotkeyHeld {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp?()
            }
            return nil // swallow
        }

        // Option released while Space still physically held.
        if type == .flagsChanged && isHotkeyHeld && !hasOption {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp?()
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    /// Device-independent Option/Alt check (ignores left/right & mouse flags).
    private static func hasOptionModifier(_ flags: CGEventFlags) -> Bool {
        (flags.rawValue & CGEventFlags.maskAlternate.rawValue) != 0
    }

    private static func hasOptionModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask).contains(.option)
    }

    // MARK: - Local monitors (our windows focused)

    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?

    private func installLocalMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49 && Self.hasOptionModifier(event.modifierFlags) {
                if event.type == .keyDown && !self.isHotkeyHeld {
                    self.isHotkeyHeld = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                    return nil // swallow locally too
                } else if event.type == .keyUp && self.isHotkeyHeld {
                    self.isHotkeyHeld = false
                    DispatchQueue.main.async { self.onHotkeyUp?() }
                    return nil
                }
            }
            // Space keyUp without option still ends hold.
            if event.type == .keyUp && event.keyCode == 49 && self.isHotkeyHeld {
                self.isHotkeyHeld = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
                return nil
            }
            return event
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            if self.isHotkeyHeld && !Self.hasOptionModifier(event.modifierFlags) {
                self.isHotkeyHeld = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
            }
            return event
        }
    }

    private func removeLocalMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        localKeyMonitor = nil
        localFlagsMonitor = nil
    }

    // MARK: - Fallback (observe only — cannot block Space)

    private var fallbackKeyMonitor: Any?
    private var fallbackFlagsMonitor: Any?

    private func installFallbackMonitors() {
        fallbackKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 49 && Self.hasOptionModifier(event.modifierFlags) {
                if event.type == .keyDown && !self.isHotkeyHeld {
                    self.isHotkeyHeld = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                } else if event.type == .keyUp && self.isHotkeyHeld {
                    self.isHotkeyHeld = false
                    DispatchQueue.main.async { self.onHotkeyUp?() }
                }
            } else if event.type == .keyUp && event.keyCode == 49 && self.isHotkeyHeld {
                self.isHotkeyHeld = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
            }
        }
        fallbackFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            if self.isHotkeyHeld && !Self.hasOptionModifier(event.modifierFlags) {
                self.isHotkeyHeld = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
            }
        }
    }

    private func removeFallbackMonitors() {
        if let fallbackKeyMonitor { NSEvent.removeMonitor(fallbackKeyMonitor) }
        if let fallbackFlagsMonitor { NSEvent.removeMonitor(fallbackFlagsMonitor) }
        fallbackKeyMonitor = nil
        fallbackFlagsMonitor = nil
    }
}
