import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared so menu bar actions can open the dashboard without depending on
    /// SwiftUI `openWindow` (often a no-op from MenuBarExtra).
    static private(set) var shared: AppDelegate?

    /// Same AppState instance as the SwiftUI hierarchy.
    var appState: AppState?

    /// Retained AppKit host for the main dashboard (not released on close).
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Menu-bar agent (LSUIElement) — stay out of the Dock until a window opens.
        NSApp.setActivationPolicy(.accessory)

        // Accessibility is required to *suppress* ⌥Space (event tap) and insert text.
        // Without it, Space still types into the focused app.
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Allow: open -a MacWispr --args --open-dashboard
        if CommandLine.arguments.contains("--open-dashboard") {
            openDashboardWhenReady(attempts: 30)
        }
    }

    /// Retries until AppState is available.
    private func openDashboardWhenReady(attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            if (self.appState ?? AppState.shared) != nil {
                self.showDashboard()
            } else if attempts > 0 {
                self.openDashboardWhenReady(attempts: attempts - 1)
            } else {
                NSLog("MacWispr: timed out waiting for AppState to open dashboard")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running in menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock icon click / reopen → show dashboard.
        showDashboard()
        return true
    }

    /// Opens (or focuses) the Time Saved dashboard. Safe to call from the menu bar.
    /// Always hops to the main queue after a short delay so MenuBarExtra can dismiss first.
    func showDashboard() {
        // Defer: if we open while the menu-bar panel is still animating closed,
        // the new window often fails to key / appears blank / vanishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.presentDashboard()
        }
    }

    @MainActor
    private func presentDashboard() {
        guard let appState = appState ?? AppState.shared else {
            NSLog("MacWispr: showDashboard called before AppState is ready")
            return
        }
        self.appState = appState

        // Become a normal app so the window can take focus and appear on-screen.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        if dashboardWindow == nil {
            let root = MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 680, minHeight: 480)

            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.identifier = NSUserInterfaceItemIdentifier("main")
            window.title = "MacWispr"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 720, height: 640))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MacWisprMain")
            window.collectionBehavior.insert(.moveToActiveSpace)

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    // Keep the window instance for fast reopen; drop Dock presence.
                    guard let self else { return }
                    let otherVisible = NSApp.windows.contains {
                        $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
                    }
                    if !otherVisible {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }

            dashboardWindow = window
        }

        guard let window = dashboardWindow else { return }

        // If the user closed it, it's hidden but retained — show again.
        if !window.isVisible {
            window.setIsVisible(true)
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // One more kick after layout — fixes rare blank first frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension Notification.Name {
    static let macWisprOpenMainWindow = Notification.Name("macWisprOpenMainWindow")
}
