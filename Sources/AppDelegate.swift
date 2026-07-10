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

        // Request accessibility permissions for system-wide text insertion
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Allow: open -a MacWispr --args --open-dashboard
        if CommandLine.arguments.contains("--open-dashboard") {
            openDashboardWhenReady(attempts: 20)
        }
    }

    /// Retries until SwiftUI has wired `appState` (MenuBarExtra onAppear).
    private func openDashboardWhenReady(attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if self.appState != nil {
                self.showDashboard()
            } else if attempts > 0 {
                self.openDashboardWhenReady(attempts: attempts - 1)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running in menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showDashboard()
        }
        return true
    }

    /// Opens (or focuses) the Time Saved dashboard. Safe to call from the menu bar.
    @MainActor
    func showDashboard() {
        guard let appState else {
            // AppState not wired yet — ask MenuBarView to open via openWindow.
            NotificationCenter.default.post(name: .macWisprOpenMainWindow, object: nil)
            return
        }

        NSApp.setActivationPolicy(.regular)

        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Keep the window instance for fast reopen; just drop Dock presence.
            DispatchQueue.main.async {
                self?.dashboardWindow = window
                NSApp.setActivationPolicy(.accessory)
            }
        }

        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let macWisprOpenMainWindow = Notification.Name("macWisprOpenMainWindow")
}
