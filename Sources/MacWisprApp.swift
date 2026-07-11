import SwiftUI
import AppKit

@main
struct MacWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    /// Status item must be installed **once**. Side-effect in `body` re-ran on
    /// every scene invalidation and rebuilt the popover host → ghosted UI.
    private static var didInstallMenuBar = false

    var body: some Scene {
        let _ = Self.installMenuBarIfNeeded(appDelegate: appDelegate, appState: appState)

        Window("MacWispr", id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 680, minHeight: 480)
        }
        .defaultSize(width: 720, height: 640)
        .commandsRemoved()
    }

    private static func installMenuBarIfNeeded(appDelegate: AppDelegate, appState: AppState) {
        // Always keep the delegate’s pointer current (cheap).
        appDelegate.appState = appState
        guard !didInstallMenuBar else { return }
        didInstallMenuBar = true
        StatusBarController.shared.install(appState: appState)
    }
}
