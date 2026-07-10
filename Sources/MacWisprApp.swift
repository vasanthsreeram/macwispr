import SwiftUI
import AppKit

@main
struct MacWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // MenuBarExtra content (and its onAppear) only load after the first
        // click — wire AppState here so Open Dashboard works immediately.
        let _ = { appDelegate.appState = appState }()

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Still declared so Settings / system window management stay consistent;
        // primary open path is AppDelegate.showDashboard() (AppKit-hosted).
        Window("MacWispr", id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 680, minHeight: 480)
        }
        .defaultSize(width: 720, height: 640)
        .commandsRemoved()
    }
}
