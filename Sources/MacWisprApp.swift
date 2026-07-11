import SwiftUI
import AppKit

@main
struct MacWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Wire shared state + install the menu-bar status item once AppState exists.
        let _ = {
            appDelegate.appState = appState
            StatusBarController.shared.install(appState: appState)
        }()

        Window("MacWispr", id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 680, minHeight: 480)
        }
        .defaultSize(width: 720, height: 640)
        .commandsRemoved()
    }
}
