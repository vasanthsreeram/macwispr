import AppKit
import SwiftUI
import Combine

/// System menu-bar presence via AppKit `NSStatusItem`.
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

    static var sharedHasStatusItem: Bool {
        shared.statusItem != nil
    }

    func install(appState: AppState) {
        self.appState = appState

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = Self.symbolImage(phase: .ready, tinted: false)
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
        guard let item = statusItem, let button = item.button else { return }

        button.appearsDisabled = false

        switch phase {
        case .listening:
            // Visible “REC 0:12” so it’s obvious even in a crowded menu bar.
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
            // Show latency in the menu bar when short enough (e.g. "320ms").
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
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

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
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacWispr")?
            .withSymbolConfiguration(config)
        // Non-template when tinted so contentTintColor / attributed colors read clearly.
        image?.isTemplate = !tinted
        if tinted, let image {
            // Bake a solid color for maximum visibility in the menu bar.
            let color: NSColor
            switch phase {
            case .listening: color = .systemRed
            case .transcribing, .failed: color = .systemOrange
            case .success: color = .systemGreen
            default: color = .labelColor
            }
            return image.tinted(with: color)
        }
        return image
    }

    private static func timerTitle(_ text: String, color: NSColor) -> NSAttributedString {
        // Fixed-width monospaced digits reduce menu-bar jumpiness.
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

    /// Pull "320 ms" / "1.2 s" out of detail like "24w · 320 ms".
    private static func compactLatency(from detail: String) -> String? {
        // Prefer the segment after the last middle-dot.
        let parts = detail.components(separatedBy: "·").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let last = parts.last, !last.isEmpty else { return nil }
        if last.hasSuffix("ms") || last.hasSuffix("s") {
            // Compact spaces: "320 ms" → "320ms", "1.2 s" → "1.2s"
            return last.replacingOccurrences(of: " ", with: "")
        }
        return nil
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        let rect = NSRect(origin: .zero, size: size)
        color.set()
        rect.fill()
        draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        return image
    }
}
