import AppKit
import SwiftUI
import Combine

/// Owns a borderless, always-on-top pill at the top of the screen.
/// Superwhisper-style floating indicator for listening state + dashboard access.
@MainActor
final class FloatingIndicatorController {
    static let shared = FloatingIndicatorController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private let panelDelegate = FloatingPanelDelegate()

    private let defaultSize = NSSize(width: 168, height: 48)
    private let positionKey = "floatingIndicatorOrigin"

    private init() {}

    func attach(appState: AppState) {
        self.appState = appState
        cancellables.removeAll()

        appState.$isRecording
            .combineLatest(appState.$isTranscribing, appState.$isModelLoading, appState.$floatingIndicatorEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, enabled in
                self?.refreshVisibility(enabled: enabled)
                self?.relayout()
            }
            .store(in: &cancellables)

        refreshVisibility(enabled: appState.floatingIndicatorEnabled)
    }

    func setVisible(_ visible: Bool) {
        if visible {
            ensurePanel()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    // MARK: - Panel

    private func refreshVisibility(enabled: Bool) {
        if enabled {
            ensurePanel()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil else {
            // Refresh root view if AppState was rebound.
            if let appState, let hostingView {
                hostingView.rootView = AnyView(
                    FloatingIndicatorView()
                        .environmentObject(appState)
                )
            }
            return
        }
        guard let appState else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI capsule draws its own shadow
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.delegate = panelDelegate
        // Stay above normal windows but not above screen savers.
        panel.sharingType = .none

        let root = AnyView(
            FloatingIndicatorView()
                .environmentObject(appState)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: defaultSize)
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting

        restoreOrCenterPosition(panel)
        panel.orderFrontRegardless()
    }

    private func relayout() {
        guard let panel, let content = panel.contentView else { return }
        // Let Auto Layout / hosting view settle after label expand.
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        var frame = panel.frame
        let newSize = NSSize(
            width: max(fitting.width + 4, 44),
            height: max(fitting.height + 4, 40)
        )
        // Keep center X stable when expanding for "Listening".
        let midX = frame.midX
        frame.size = newSize
        frame.origin.x = midX - newSize.width / 2
        panel.setFrame(frame, display: true, animate: true)
        persistPosition(panel)
    }

    // MARK: - Position

    private func restoreOrCenterPosition(_ panel: NSPanel) {
        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2, let screen = NSScreen.main {
                var origin = NSPoint(x: parts[0], y: parts[1])
                // Clamp into visible frame in case of display change.
                let vis = screen.visibleFrame
                origin.x = min(max(origin.x, vis.minX), vis.maxX - defaultSize.width)
                origin.y = min(max(origin.y, vis.minY), vis.maxY - defaultSize.height)
                panel.setFrameOrigin(origin)
                return
            }
        }
        centerAtTop(panel)
    }

    private func centerAtTop(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let size = panel.frame.size
        let x = vis.midX - size.width / 2
        // Just under the menu bar / notch area.
        let y = vis.maxY - size.height - 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        persistPosition(panel)
    }

    private func persistPosition(_ panel: NSPanel) {
        let o = panel.frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: positionKey)
    }

    /// Call when the user finishes dragging the pill (mouse up).
    func savePositionIfNeeded() {
        guard let panel else { return }
        persistPosition(panel)
    }
}

/// Observes window moves so the pill position is remembered.
final class FloatingPanelDelegate: NSObject, NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        FloatingIndicatorController.shared.savePositionIfNeeded()
    }
}
