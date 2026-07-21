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

        // Cap MLX free-buffer pool before any Qwen/polish load (see MLXMemoryPolicy).
        MLXMemoryPolicy.apply()

        // Sparkle: start background update checks when Info.plist has SUFeedURL
        // (packaged .app). Bare SPM binaries skip this — see SparkleUpdater.
        _ = SparkleUpdater.shared

        // Accessibility is required for the global ⌥Space hotkey (event tap /
        // Carbon) and for pasting into other apps. Mic is required to capture audio.
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        AudioRecorder.requestPermissionIfNeeded()

        // Allow: open -a MacWispr --args --open-dashboard
        if CommandLine.arguments.contains("--open-dashboard") {
            openDashboardWhenReady(attempts: 30)
        }

        // First-run onboarding / telemetry: open the dashboard so sheets can present.
        // Skip during automated self-test / when dashboard already requested.
        if !CommandLine.arguments.contains("--self-test"),
           !CommandLine.arguments.contains("--open-dashboard")
        {
            let needsOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if needsOnboarding || !Telemetry.shared.hasSeenDisclosure {
                openDashboardWhenReady(attempts: 30)
            }
        }

        // Automated smoke test: --self-test
        if CommandLine.arguments.contains("--self-test") {
            runSelfTest()
        }
    }

    /// Verifies status item, model load, hold/toggle API, and ⌥Space hotkey path.
    private func runSelfTest() {
        Task { @MainActor in
            var failures: [String] = []
            print("MacWispr self-test starting…")
            print("AXIsProcessTrusted:", AXIsProcessTrusted())

            // 1. Status item
            try? await Task.sleep(nanoseconds: 500_000_000)
            if StatusBarController.sharedHasStatusItem {
                print("PASS status item present")
            } else {
                failures.append("status item missing")
                print("FAIL status item missing")
            }

            // 2. Wait for model (up to ~60s)
            let state = appState ?? AppState.shared
            guard let state else {
                print("FAIL no AppState")
                exit(1)
            }
            for _ in 0..<120 {
                if state.isModelLoaded || state.modelLoadStatus.hasPrefix("Error") { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if state.isModelLoaded {
                print("PASS model loaded")
            } else {
                failures.append("model not loaded: \(state.modelLoadStatus)")
                print("FAIL model not loaded: \(state.modelLoadStatus)")
            }

            let hotkey = state.hotkeyManager
            print("hotkey tap installed:", hotkey.tapInstalled)
            print("hotkey carbon installed:", hotkey.carbonInstalled)
            print("hotkey monitors installed:", hotkey.monitorsInstalled)
            print("hotkey armed:", hotkey.isArmed)
            state.refreshHotkeyHealth()

            if state.isModelLoaded {
                // 3. Direct API hold start/stop
                state.setDictationMode(.hold)
                state.startRecording()
                if state.isRecording {
                    print("PASS hold startRecording (API)")
                } else {
                    failures.append("startRecording API failed")
                    print("FAIL startRecording API")
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                await state.stopRecordingAndTranscribe()
                print(state.isRecording ? "FAIL hold stop API" : "PASS hold stopRecording (API)")
                if state.isRecording { failures.append("hold stop API") }

                // 4. Toggle API
                state.setDictationMode(.toggle)
                state.toggleRecording()
                print(state.isRecording ? "PASS toggle start (API)" : "FAIL toggle start API")
                if !state.isRecording { failures.append("toggle start API") }
                try? await Task.sleep(nanoseconds: 150_000_000)
                state.toggleRecording()
                try? await Task.sleep(nanoseconds: 300_000_000)
                print(!state.isRecording ? "PASS toggle stop (API)" : "FAIL toggle stop API")
                if state.isRecording { failures.append("toggle stop API") }

                // 5. Hotkey via synthetic handler (no OS event stream needed)
                state.setDictationMode(.hold)
                let downsBefore = hotkey.downCount
                hotkey.handleSyntheticKey(down: true, option: true)
                // Let main-queue callbacks run
                try? await Task.sleep(nanoseconds: 150_000_000)
                if hotkey.downCount > downsBefore && state.isRecording {
                    print("PASS hotkey synthetic DOWN → recording")
                } else {
                    failures.append("synthetic DOWN failed (downCount=\(hotkey.downCount) recording=\(state.isRecording))")
                    print("FAIL hotkey synthetic DOWN (downCount=\(hotkey.downCount) recording=\(state.isRecording))")
                }
                hotkey.handleSyntheticKey(down: false, option: true)
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !state.isRecording {
                    print("PASS hotkey synthetic UP → stopped")
                } else {
                    failures.append("synthetic UP did not stop")
                    print("FAIL hotkey synthetic UP")
                }

                // 6. Hotkey via real CGEvent.post (tests event tap / monitors)
                state.setDictationMode(.hold)
                let downs2 = hotkey.downCount
                hotkey.injectOptionSpace(down: true)
                try? await Task.sleep(nanoseconds: 250_000_000)
                if hotkey.downCount > downs2 || state.isRecording {
                    print("PASS hotkey CGEvent inject DOWN (downCount \(downs2)→\(hotkey.downCount) recording=\(state.isRecording))")
                } else {
                    // Not always a hard fail: some environments block inject into own tap.
                    print("WARN hotkey CGEvent inject DOWN not observed (tap=\(hotkey.tapInstalled) AX=\(AXIsProcessTrusted()))")
                    print("     If real keyboard also fails, enable Accessibility for MacWispr.")
                }
                hotkey.injectOptionSpace(down: false)
                try? await Task.sleep(nanoseconds: 400_000_000)
                if state.isRecording {
                    // Force cleanup so we exit cleanly.
                    await state.stopRecordingAndTranscribe()
                }
                print("hotkey totals: downs=\(hotkey.downCount) ups=\(hotkey.upCount)")
            }

            if failures.isEmpty {
                print("MacWispr self-test: ALL PASSED")
                exit(0)
            } else {
                print("MacWispr self-test: FAILED \(failures)")
                exit(1)
            }
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

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any pending opt-in telemetry before process exit (fail-silent).
        Telemetry.shared.flush(force: true)
        // Brief wait so the fire-and-forget URLSession task can leave the device.
        Thread.sleep(forTimeInterval: 0.35)
    }

    func applicationDidResignActive(_ notification: Notification) {
        Telemetry.shared.flush(force: false)
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
        // Coarse surface open only — no free text / paths.
        Telemetry.shared.reportUIOpen(surface: "dashboard")

        // Become a normal app so the window can take focus and appear on-screen.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        // Drop any leftover titled "MacWispr" windows from older dual-path builds
        // (SwiftUI Window scene + AppKit host) so only one dashboard stays open.
        closeStrayMacWisprWindows(keeping: dashboardWindow)

        if dashboardWindow == nil {
            let root = MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 680, minHeight: 480)

            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.identifier = NSUserInterfaceItemIdentifier("MacWisprDashboard")
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
            ) { _ in
                DispatchQueue.main.async {
                    // Keep the window instance for fast reopen; drop Dock presence.
                    let otherVisible = NSApp.windows.contains {
                        $0 !== window && $0.isVisible && $0.isMacWisprDashboardCandidate
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
        // SwiftUI installs the toolbar asynchronously — lock it after layout.
        lockDashboardToolbar(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.lockDashboardToolbar(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.lockDashboardToolbar(window)
        }
    }

    /// Kill the macOS “Icon and Text / Icon Only” toolbar menu (right-click /
    /// double-click on the titlebar toolbar). Users don’t customize this chrome.
    @MainActor
    private func lockDashboardToolbar(_ window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }
        // Keep a stable look; don’t let a double-click flip display modes.
        toolbar.displayMode = .iconAndLabel
    }

    /// Closes extra titled MacWispr windows so only our retained dashboard remains.
    @MainActor
    private func closeStrayMacWisprWindows(keeping keep: NSWindow?) {
        for window in NSApp.windows {
            guard window !== keep else { continue }
            guard window.isMacWisprDashboardCandidate else { continue }
            // Don't touch popovers, HUD panels, status-item windows, etc.
            window.isReleasedWhenClosed = true
            window.close()
        }
    }
}

private extension NSWindow {
    /// Titled app windows that look like a MacWispr dashboard (not HUD/popover chrome).
    var isMacWisprDashboardCandidate: Bool {
        guard styleMask.contains(.titled) else { return false }
        if identifier?.rawValue == "MacWisprDashboard" || identifier?.rawValue == "main" {
            return true
        }
        return title == "MacWispr"
    }
}

extension Notification.Name {
    static let macWisprOpenMainWindow = Notification.Name("macWisprOpenMainWindow")
}
