import AppKit
import SwiftUI
import Combine

/// Reliable menu-bar presence via `NSStatusItem` (more dependable than
/// SwiftUI `MenuBarExtra` for LSUIElement apps).
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    /// Exposed for `--self-test`.
    static var sharedHasStatusItem: Bool {
        shared.statusItem != nil
    }

    func install(appState: AppState) {
        self.appState = appState

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = Self.symbolImage(recording: false)
                button.imagePosition = .imageOnly
                button.toolTip = "MacWispr — click for controls"
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
            NSLog("MacWispr: menu bar status item installed")
        }

        if popover == nil {
            let pop = NSPopover()
            pop.behavior = .transient
            pop.animates = true
            popover = pop
        }
        refreshPopoverContent()

        cancellables.removeAll()
        appState.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                self?.statusItem?.button?.image = Self.symbolImage(recording: recording)
                self?.statusItem?.button?.toolTip = recording
                    ? "MacWispr — listening…"
                    : "MacWispr — click for controls"
            }
            .store(in: &cancellables)

        appState.$isModelLoaded
            .receive(on: RunLoop.main)
            .sink { [weak self] loaded in
                self?.statusItem?.button?.appearsDisabled = false
                if !loaded {
                    self?.statusItem?.button?.toolTip = "MacWispr — loading model…"
                }
            }
            .store(in: &cancellables)
    }

    private func refreshPopoverContent() {
        guard let appState, let popover else { return }
        let root = MenuBarView()
            .environmentObject(appState)
            .frame(width: 300)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 300, height: 420)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        refreshPopoverContent()
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so buttons inside the popover receive clicks.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    private static func symbolImage(recording: Bool) -> NSImage? {
        let name = recording ? "waveform.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacWispr")
        image?.isTemplate = true
        return image
    }
}
