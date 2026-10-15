import SwiftUI
import AppKit
import MacWisprCore

/// `MacWispr --render-ui <dir>` — render the real app views offscreen to PNGs
/// (no window is shown). Used for release screenshots and UI review.
enum UISnapshot {
    static let flag = "--render-ui"

    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    @MainActor
    static func run(to dir: URL, state: AppState) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Reflect real permission / hotkey state, as the running app does.
        state.hotkeyManager.register()
        state.refreshHotkeyHealth()
        let size = CGSize(width: 720, height: 640)
        for pane in MainPane.allCases {
            render(MainWindowView(initialPane: pane), state: state, size: size, to: dir.appendingPathComponent("ui-\(pane.rawValue).png"))
        }
        render(OnboardingView(), state: state, size: CGSize(width: 440, height: 460), to: dir.appendingPathComponent("ui-onboarding.png"))
        render(MenuBarView().fixedSize(), state: state, size: CGSize(width: 300, height: 420), to: dir.appendingPathComponent("ui-menubar.png"))
        let hud = ListeningBannerBox()
        hud.model = ListeningBannerModel(
            phase: .listening, timerLabel: "0:07", liveTranscript: nil,
            statusLine: nil, showChrome: true, glassStyle: .clear
        )
        hud.audioLevelProvider = { Float.random(in: 0.01...0.12) }
        render(ListeningBannerView(box: hud).frame(width: 180, height: 40).padding(20), state: state, size: CGSize(width: 220, height: 80), to: dir.appendingPathComponent("ui-hud.png"))
        print("rendered UI to \(dir.path)")
        exit(0)
    }

    @MainActor
    private static func render<V: View>(_ view: V, state: AppState, size: CGSize, to url: URL) {
        let root = view
            .environment(state)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        // NSHostingView renders AppKit-backed controls (Form, Picker) faithfully.
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let dark = ProcessInfo.processInfo.environment["MACWISPR_RENDER_DARK"] == "1"
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
