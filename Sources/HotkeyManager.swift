import Cocoa
import CoreGraphics

/// Hold ⌥Space to dictate. Uses a session event tap so Space is *swallowed*
/// and never reaches the focused app (cursor won't jump / insert spaces).
///
/// `NSEvent.addGlobalMonitorForEvents` can only observe keys — it cannot
/// suppress them. That was why Space kept moving the cursor.
final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyHeld = false

    private static let spaceKeyCode: Int64 = 49 // kVK_Space

    /// Re-create the event tap if Accessibility was granted after launch.
    func ensureRegistered() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        register()
    }

    func register() {
        unregister()

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // must NOT be listenOnly — we need to swallow
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            NSLog("MacWispr: failed to create event tap — grant Accessibility in System Settings")
            // Last-resort observer (cannot suppress Space, but dictation still works)
            installFallbackMonitors()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        removeFallbackMonitors()
        isHotkeyHeld = false
    }

    deinit {
        unregister()
    }

    // MARK: - Event handling

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // System may disable the tap after timeout — re-enable immediately.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let hasOption = flags.contains(.maskAlternate)

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
        if type == .keyUp && keyCode == Self.spaceKeyCode && isHotkeyHeld {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp?()
            }
            return nil // swallow
        }

        // Option released while Space still held.
        if type == .flagsChanged && isHotkeyHeld && !hasOption {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp?()
            }
            // Let the flags change through — only Space was the problem.
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Fallback (observe only — cannot block Space)

    private var fallbackKeyMonitor: Any?
    private var fallbackFlagsMonitor: Any?

    private func installFallbackMonitors() {
        fallbackKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 49 && event.modifierFlags.contains(.option) {
                if event.type == .keyDown && !self.isHotkeyHeld {
                    self.isHotkeyHeld = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                } else if event.type == .keyUp && self.isHotkeyHeld {
                    self.isHotkeyHeld = false
                    DispatchQueue.main.async { self.onHotkeyUp?() }
                }
            }
        }
        fallbackFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            if self.isHotkeyHeld && !event.modifierFlags.contains(.option) {
                self.isHotkeyHeld = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
            }
        }
    }

    private func removeFallbackMonitors() {
        if let fallbackKeyMonitor {
            NSEvent.removeMonitor(fallbackKeyMonitor)
        }
        if let fallbackFlagsMonitor {
            NSEvent.removeMonitor(fallbackFlagsMonitor)
        }
        fallbackKeyMonitor = nil
        fallbackFlagsMonitor = nil
    }
}
