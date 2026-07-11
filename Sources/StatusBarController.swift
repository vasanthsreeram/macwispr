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
                button.image = Self.symbolImage(phase: .setup)
                button.imagePosition = .imageOnly
                button.toolTip = "MacWispr — Hold ⌥Space to dictate"
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
        applyPhase(appState.dictationPhase, detail: appState.phaseDetail, state: appState)

        cancellables.removeAll()

        appState.$dictationPhase
            .combineLatest(appState.$phaseDetail, appState.$recordingElapsed, appState.$isModelLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, detail, _, _ in
                guard let self, let state = self.appState else { return }
                self.applyPhase(phase, detail: detail, state: state)
            }
            .store(in: &cancellables)

        appState.$isModelLoaded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let state = self.appState else { return }
                self.applyPhase(state.dictationPhase, detail: state.phaseDetail, state: state)
            }
            .store(in: &cancellables)
    }

    private func applyPhase(_ phase: DictationPhase, detail: String, state: AppState) {
        guard let button = statusItem?.button else { return }
        button.image = Self.symbolImage(phase: phase)
        button.appearsDisabled = false

        switch phase {
        case .listening:
            button.imagePosition = .imageLeading
            button.title = " \(state.recordingElapsedLabel)"
            button.toolTip = detail.isEmpty ? "MacWispr — listening…" : detail
        case .transcribing:
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = detail.isEmpty ? "MacWispr — transcribing…" : detail
        case .success:
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = detail.isEmpty ? "MacWispr — inserted" : detail
        case .failed:
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = detail.isEmpty ? "MacWispr — something went wrong" : detail
        case .setup:
            button.imagePosition = .imageOnly
            button.title = ""
            if state.isModelLoading {
                button.toolTip = "MacWispr — \(state.modelLoadStatus.isEmpty ? "loading model…" : state.modelLoadStatus)"
            } else {
                button.toolTip = "MacWispr — setup needed: \(state.readinessLabel)"
            }
        case .ready:
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "MacWispr — Hold ⌥Space to dictate"
        }
    }

    private func refreshPopoverContent() {
        guard let appState, let popover else { return }
        let root = MenuBarView()
            .environmentObject(appState)
            .frame(width: 300)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 300, height: 440)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        refreshPopoverContent()
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so buttons inside the popover receive clicks (popover only).
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    private static func symbolImage(phase: DictationPhase) -> NSImage? {
        let name: String
        switch phase {
        case .listening:
            name = "waveform.circle.fill"
        case .transcribing:
            name = "ellipsis.circle.fill"
        case .success:
            name = "checkmark.circle.fill"
        case .failed, .setup:
            name = "waveform.circle"
        case .ready:
            name = "waveform.circle"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacWispr")
        image?.isTemplate = true
        return image
    }
}
