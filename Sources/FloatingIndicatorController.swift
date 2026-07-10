import AppKit
import SwiftUI
import Combine
import QuartzCore

/// Owns a borderless, always-on-top pill at the top of the screen.
/// Superwhisper-style floating indicator for listening state + dashboard access.
///
/// Position is hard-clamped to each screen’s **visibleFrame** (below the menu
/// bar / notch) so the pill can never get stuck in the camera housing.
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
    private let edgePadding: CGFloat = 10

    private init() {}

    func attach(appState: AppState) {
        self.appState = appState
        cancellables.removeAll()

        appState.$isRecording
            .combineLatest(
                appState.$isTranscribing,
                appState.$isModelLoading,
                appState.$floatingIndicatorEnabled
            )
            .combineLatest(appState.$currentTranscription)
            .combineLatest(appState.$statusBanner)
            .receive(on: RunLoop.main)
            .sink { [weak self] combined, _ in
                let ((_, _, _, enabled), _) = combined
                self?.refreshVisibility(enabled: enabled)
                self?.relayout()
            }
            .store(in: &cancellables)

        // Displays can change (laptop lid, external monitor) — reclamp.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.clampToSafeArea(animated: true)
            }
            .store(in: &cancellables)

        refreshVisibility(enabled: appState.floatingIndicatorEnabled)
    }

    func setVisible(_ visible: Bool) {
        if visible {
            ensurePanel()
            clampToSafeArea(animated: false)
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    /// Snap back under the menu bar, centered on the main screen.
    func resetPosition() {
        guard let panel else { return }
        centerAtTop(panel)
        clampToSafeArea(animated: true)
    }

    // MARK: - Panel

    private func refreshVisibility(enabled: Bool) {
        if enabled {
            ensurePanel()
            clampToSafeArea(animated: false)
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil else {
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
        // Below menu bar chrome, above normal windows — but we still clamp
        // into visibleFrame so the notch never owns the pill.
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        // Custom drag with clamping — free `isMovableByWindowBackground`
        // lets users drag into the notch dead-zone.
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.delegate = panelDelegate
        panel.sharingType = .none

        let root = AnyView(
            FloatingIndicatorView()
                .environmentObject(appState)
        )
        let hosting = DraggableHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: defaultSize)
        hosting.onDrag = { [weak self] delta in
            self?.moveBy(delta)
        }
        hosting.onDragEnded = { [weak self] in
            self?.clampToSafeArea(animated: true)
            self?.savePositionIfNeeded()
        }
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting

        restoreOrCenterPosition(panel)
        clampToSafeArea(animated: false)
        panel.orderFrontRegardless()
    }

    private func relayout() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        var frame = panel.frame
        let newSize = NSSize(
            width: max(fitting.width + 4, 44),
            height: max(fitting.height + 4, 40)
        )
        let midX = frame.midX
        frame.size = newSize
        frame.origin.x = midX - newSize.width / 2
        panel.setFrame(frame, display: true, animate: false)
        // Expanding text near a screen edge must not push us into the notch.
        clampToSafeArea(animated: false)
    }

    private func moveBy(_ delta: NSPoint) {
        guard let panel else { return }
        var origin = panel.frame.origin
        origin.x += delta.x
        origin.y += delta.y
        panel.setFrameOrigin(origin)
        // Clamp while dragging so the pill can never enter the notch.
        clampToSafeArea(animated: false)
    }

    // MARK: - Safe area / notch

    /// Visible desktop rect for the screen that currently owns the pill,
    /// inset so we stay clear of the menu bar, Dock, and notch.
    private func safeRect(for screen: NSScreen) -> NSRect {
        // `visibleFrame` is already below the menu bar and above the Dock.
        // That is the correct zone — never use full `screen.frame` (notch lives there).
        var vis = screen.visibleFrame
        vis = vis.insetBy(dx: edgePadding, dy: edgePadding)
        // Extra top breathing room under the menu bar / notch shadow.
        vis.size.height -= 4
        return vis
    }

    private func screenContaining(_ panel: NSPanel) -> NSScreen {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let match = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    @discardableResult
    func clampToSafeArea(animated: Bool) -> Bool {
        guard let panel else { return false }
        let screen = screenContaining(panel)
        let safe = safeRect(for: screen)
        var frame = panel.frame

        // If the pill is wider/taller than the safe rect, pin to origin.
        let maxX = max(safe.minX, safe.maxX - frame.width)
        let maxY = max(safe.minY, safe.maxY - frame.height)
        let clampedX = min(max(frame.origin.x, safe.minX), maxX)
        let clampedY = min(max(frame.origin.y, safe.minY), maxY)

        let changed = abs(clampedX - frame.origin.x) > 0.5 || abs(clampedY - frame.origin.y) > 0.5
        if changed {
            frame.origin = NSPoint(x: clampedX, y: clampedY)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
            persistPosition(panel)
        }
        return changed
    }

    // MARK: - Position persistence

    private func restoreOrCenterPosition(_ panel: NSPanel) {
        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                panel.setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
                clampToSafeArea(animated: false)
                return
            }
        }
        centerAtTop(panel)
    }

    private func centerAtTop(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let safe = safeRect(for: screen)
        let size = panel.frame.size
        let x = safe.midX - size.width / 2
        let y = safe.maxY - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        persistPosition(panel)
    }

    private func persistPosition(_ panel: NSPanel) {
        let o = panel.frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: positionKey)
    }

    func savePositionIfNeeded() {
        guard let panel else { return }
        persistPosition(panel)
    }
}

// MARK: - Drag hosting view

/// NSHostingView that reports drag deltas so we can clamp against the notch.
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var lastDragPoint: NSPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        guard let last = lastDragPoint else {
            lastDragPoint = point
            return
        }
        let delta = NSPoint(x: point.x - last.x, y: point.y - last.y)
        // Ignore tiny jitter so clicks still open the dashboard.
        if abs(delta.x) + abs(delta.y) > 1 {
            dragging = true
            // Convert delta to screen coords (window may not be flipped the same).
            if let win = window {
                let curScreen = win.convertPoint(toScreen: point)
                let prevScreen = win.convertPoint(toScreen: last)
                onDrag?(NSPoint(x: curScreen.x - prevScreen.x, y: curScreen.y - prevScreen.y))
            } else {
                onDrag?(delta)
            }
        }
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        lastDragPoint = nil
        dragging = false
        if wasDragging {
            onDragEnded?()
        } else {
            // Treat as click — forward to SwiftUI via super after a clean mouseUp.
            super.mouseDown(with: event)
            super.mouseUp(with: event)
        }
    }
}

/// Observes window moves as a safety net (e.g. Spaces / display changes).
final class FloatingPanelDelegate: NSObject, NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            FloatingIndicatorController.shared.clampToSafeArea(animated: false)
            FloatingIndicatorController.shared.savePositionIfNeeded()
        }
    }
}
