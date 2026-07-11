import AppKit
import SwiftUI
import Combine

/// System menu-bar presence via AppKit `NSStatusItem` + a single `NSPopover`.
///
/// Important (avoids ghosted / double-drawn Liquid Glass content):
/// - Install once — never rebuild the popover host on every click or SwiftUI body pass.
/// - Keep **one** `NSHostingController` for the life of the process.
/// - `animates = false` (standard menu-bar popover guidance).
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// Single host — must not be replaced while the popover is open.
    private var hostingController: NSHostingController<AnyView>?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var didInstall = false
    /// Event monitor so transient popover dismiss stays reliable.
    private var localEventMonitor: Any?

    private override init() {
        super.init()
    }

    static var sharedHasStatusItem: Bool {
        shared.statusItem != nil
    }

    /// Idempotent. Safe if SwiftUI re-evaluates the App scene body.
    func install(appState: AppState) {
        self.appState = appState

        if !didInstall {
            didInstall = true
            installStatusItem()
            installPopover()
            ensureHostingController()
            NSLog("MacWispr: menu bar status item installed")
        } else {
            // Same AppState instance is shared for life; only re-bind if needed.
            ensureHostingController()
        }

        applyPhase(appState.dictationPhase, detail: appState.phaseDetail, state: appState)
        bindPhaseUpdates(appState)
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.symbolImage(phase: .ready, tinted: false)
            button.imagePosition = .imageOnly
            button.toolTip = "MacWispr — Hold ⌥Space to dictate"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Left-click only — dual mouse-up can double-toggle the popover.
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
    }

    private func installPopover() {
        guard popover == nil else { return }
        let pop = NSPopover()
        pop.behavior = .transient
        // Animation + host swap is a common source of double-draw / glass glitches.
        pop.animates = false
        pop.delegate = self
        popover = pop
    }

    /// Create the hosting controller once. SwiftUI observes `AppState` via
    /// `environmentObject`, so live UI updates without replacing the host.
    private func ensureHostingController() {
        guard let appState, let popover else { return }

        if hostingController != nil {
            return
        }

        let root = AnyView(
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 300)
                // Solid enough background so Liquid Glass doesn't stack two materials.
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let host = NSHostingController(rootView: root)
        if #available(macOS 13.0, *) {
            host.sizingOptions = [.intrinsicContentSize]
        }
        hostingController = host
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 300, height: 420)
    }

    private func bindPhaseUpdates(_ appState: AppState) {
        cancellables.removeAll()

        appState.$dictationPhase
            .combineLatest(appState.$phaseDetail, appState.$recordingElapsed, appState.$isModelLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, detail, _, _ in
                guard let self, let state = self.appState else { return }
                // Icon / title only — never touch the popover host here.
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
        guard let item = statusItem, let button = item.button else { return }

        button.appearsDisabled = false

        switch phase {
        case .listening:
            item.length = 72
            button.image = Self.symbolImage(phase: .listening, tinted: true)
            button.imagePosition = .imageLeading
            button.attributedTitle = Self.timerTitle(state.recordingElapsedFixedLabel, color: .systemRed)
            button.contentTintColor = .systemRed
            button.toolTip = "MacWispr — Listening \(state.recordingElapsedFixedLabel)"

        case .transcribing:
            item.length = 56
            button.image = Self.symbolImage(phase: .transcribing, tinted: true)
            button.imagePosition = .imageLeading
            button.attributedTitle = Self.plainTitle("…", color: .systemOrange)
            button.contentTintColor = .systemOrange
            button.toolTip = detail.isEmpty ? "MacWispr — Transcribing…" : "MacWispr — \(detail)"

        case .success:
            let latencyBit = Self.compactLatency(from: detail)
            if let latencyBit {
                item.length = 64
                button.image = Self.symbolImage(phase: .success, tinted: true)
                button.imagePosition = .imageLeading
                button.attributedTitle = Self.plainTitle(latencyBit, color: .systemGreen)
            } else {
                item.length = NSStatusItem.squareLength
                button.image = Self.symbolImage(phase: .success, tinted: true)
                button.imagePosition = .imageOnly
                button.title = ""
            }
            button.contentTintColor = .systemGreen
            button.toolTip = detail.isEmpty ? "MacWispr — Done" : "MacWispr — Done · \(detail)"

        case .failed:
            item.length = NSStatusItem.squareLength
            button.image = Self.symbolImage(phase: .failed, tinted: true)
            button.imagePosition = .imageOnly
            button.title = ""
            button.contentTintColor = .systemOrange
            button.toolTip = detail.isEmpty ? "MacWispr — Something went wrong" : "MacWispr — \(detail)"

        case .setup:
            item.length = NSStatusItem.squareLength
            button.image = Self.symbolImage(phase: .setup, tinted: false)
            button.imagePosition = .imageOnly
            button.title = ""
            button.contentTintColor = nil
            button.appearsDisabled = !state.isModelLoading
            if state.isModelLoading {
                button.toolTip = "MacWispr — \(state.modelLoadStatus.isEmpty ? "Loading model…" : state.modelLoadStatus)"
            } else {
                button.toolTip = "MacWispr — Setup needed: \(state.readinessLabel)"
            }

        case .ready:
            item.length = NSStatusItem.squareLength
            button.image = Self.symbolImage(phase: .ready, tinted: false)
            button.imagePosition = .imageOnly
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = "MacWispr — Hold ⌥Space to dictate"
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            closePopover()
            return
        }

        ensureHostingController()
        updatePopoverContentSize()

        // Show first, then activate — avoids a frame where glass composites twice.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.isHighlighted = true
        NSApp.activate(ignoringOtherApps: true)
        startDismissMonitor()
    }

    private func updatePopoverContentSize() {
        guard let popover, let host = hostingController else { return }
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.view.fittingSize
        let width: CGFloat = 300
        let height: CGFloat
        if fitting.height > 1 {
            height = min(max(fitting.height, 180), 720)
        } else {
            height = 420
        }
        popover.contentSize = NSSize(width: width, height: height)
    }

    func closePopover() {
        popover?.performClose(nil)
        statusItem?.button?.isHighlighted = false
        stopDismissMonitor()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.isHighlighted = false
        stopDismissMonitor()
    }

    func popoverDidShow(_ notification: Notification) {
        // Re-measure after first layout (model loading UI can change height).
        DispatchQueue.main.async { [weak self] in
            self?.updatePopoverContentSize()
        }
    }

    // MARK: - Outside click dismiss helper

    private func startDismissMonitor() {
        stopDismissMonitor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let popover = self.popover, popover.isShown else { return event }
            // Clicks inside the popover window should not close it.
            if let popoverWindow = popover.contentViewController?.view.window,
               event.window === popoverWindow
            {
                return event
            }
            // Clicks on the status item are handled by toggle.
            if let buttonWindow = self.statusItem?.button?.window,
               event.window === buttonWindow
            {
                return event
            }
            self.closePopover()
            return event
        }
    }

    private func stopDismissMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    // MARK: - Icons

    private static func symbolImage(phase: DictationPhase, tinted: Bool) -> NSImage? {
        let name: String
        switch phase {
        case .listening: name = "mic.fill"
        case .transcribing: name = "ellipsis.circle.fill"
        case .success: name = "checkmark.circle.fill"
        case .failed: name = "exclamationmark.circle.fill"
        case .setup, .ready: name = "waveform.circle"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard var image = NSImage(systemSymbolName: name, accessibilityDescription: "MacWispr")?
            .withSymbolConfiguration(config)
        else { return nil }

        image.isTemplate = !tinted
        if tinted {
            let color: NSColor
            switch phase {
            case .listening: color = .systemRed
            case .transcribing, .failed: color = .systemOrange
            case .success: color = .systemGreen
            default: color = .labelColor
            }
            image = image.tintedSafely(with: color)
        }
        return image
    }

    private static func timerTitle(_ text: String, color: NSColor) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        return NSAttributedString(string: " \(text)", attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private static func plainTitle(_ text: String, color: NSColor) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        return NSAttributedString(string: " \(text)", attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private static func compactLatency(from detail: String) -> String? {
        let parts = detail.components(separatedBy: "·").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let last = parts.last, !last.isEmpty else { return nil }
        if last.hasSuffix("ms") || last.hasSuffix("s") {
            return last.replacingOccurrences(of: " ", with: "")
        }
        return nil
    }
}

private extension NSImage {
    /// Colorize without deprecated `lockFocus` (can glitch / crash on modern macOS).
    func tintedSafely(with color: NSColor) -> NSImage {
        let targetSize = size
        guard targetSize.width > 0, targetSize.height > 0 else { return self }

        let output = NSImage(size: targetSize, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        output.isTemplate = false
        return output
    }
}
