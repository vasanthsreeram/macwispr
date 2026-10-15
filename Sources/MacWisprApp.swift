import SwiftUI
import AppKit

@main
struct MacWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    /// Status item must be installed **once**. Side-effect in `body` re-ran on
    /// every scene invalidation and rebuilt the popover host → ghosted UI.
    private static var didInstallMenuBar = false

    var body: some Scene {
        let _ = Self.installMenuBarIfNeeded(appDelegate: appDelegate, appState: appState)

        // Menu-bar agent: the real dashboard is a single AppKit `NSWindow` owned by
        // `AppDelegate` (`showDashboard`). Do **not** declare `Window` / `WindowGroup`
        // here — that creates a second "MacWispr" window next to the AppKit host
        // (GitHub #15: multiple windows + broken Cmd+Q when commands were removed).
        //
        // SwiftUI still requires a Scene. `Settings` is only an anchor; product
        // Settings live in the dashboard. Settings-only scenes omit File > Close
        // for AppKit hosts, so Cmd+Q/W are explicit (not the default suite).
        // macOS can still open this scene directly (app menu, ⌘, before our
        // command group loads), so it redirects to the dashboard's Settings
        // pane and closes itself instead of showing an empty window.
        Settings {
            SettingsSceneRedirect(open: openDashboardSettings)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openDashboardSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // File > Close (⌘W): hide dashboard, stay a menu-bar accessory. Do not quit.
            CommandGroup(replacing: .saveItem) {
                Button("Close Window") {
                    AppDelegate.shared?.closeDashboard()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            // App > Quit (⌘Q): terminate even when no SwiftUI Window scene exists.
            CommandGroup(replacing: .appTermination) {
                Button("Quit MacWispr") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }

    private static func installMenuBarIfNeeded(appDelegate: AppDelegate, appState: AppState) {
        // Always keep the delegate’s pointer current (cheap).
        appDelegate.appState = appState
        guard !didInstallMenuBar else { return }
        didInstallMenuBar = true
        StatusBarController.shared.install(appState: appState)
    }

    private func openDashboardSettings() {
        AppDelegate.shared?.appState = appState
        AppDelegate.shared?.showDashboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .macWisprShowSettings, object: nil)
        }
    }
}

/// Content of the SwiftUI `Settings` scene: closes its own window and opens
/// the real Settings pane in the dashboard.
private struct SettingsSceneRedirect: View {
    let open: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(WindowCloser())
            .onAppear(perform: open)
    }

    private struct WindowCloser: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                view.window?.orderOut(nil)
                view.window?.close()
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}
