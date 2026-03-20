import Cocoa
import Carbon.HIToolbox

final class HotkeyManager: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    private var monitor: Any?
    private var flagsMonitor: Any?
    private var isHotkeyHeld = false

    /// Registers a global hotkey: hold Fn key (Option+Space as fallback)
    /// The primary hotkey is Option+Space (hold to record, release to transcribe)
    func register() {
        // Monitor for Option+Space (hold to dictate)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            // Option + Space
            if event.keyCode == 49 && event.modifierFlags.contains(.option) {
                if event.type == .keyDown && !self.isHotkeyHeld {
                    self.isHotkeyHeld = true
                    self.onHotkeyDown?()
                } else if event.type == .keyUp {
                    self.isHotkeyHeld = false
                    self.onHotkeyUp?()
                }
            }
        }

        // Also monitor modifier flags for when Option is released while Space was held
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            if self.isHotkeyHeld && !event.modifierFlags.contains(.option) {
                self.isHotkeyHeld = false
                self.onHotkeyUp?()
            }
        }
    }

    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        monitor = nil
        flagsMonitor = nil
    }

    deinit {
        unregister()
    }
}
