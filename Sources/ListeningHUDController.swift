import AppKit
import SwiftUI

/// Simple, fixed-size floating banner under the menu bar while dictating.
///
/// This is ordinary app UI (not a Dynamic Island / notch integration — Apple
/// does not expose that for third-party Mac apps). Centered under the menu bar
/// so it’s always visible without fighting the camera housing.
@MainActor
final class ListeningHUDController {
    static let shared = ListeningHUDController()

    private static let width: CGFloat = 200
    private static let height: CGFloat = 40

    private var panel: NSPanel?
    private var host: NSHostingView<ListeningBannerView>?

    private init() {}

    func sync(with state: AppState) {
        guard state.listeningHUDEnabled else {
            hide()
            return
        }

        switch state.dictationPhase {
        case .listening, .transcribing, .success, .failed:
            break
        case .setup, .ready:
            hide()
            return
        }

        let secondary: String?
        switch state.dictationPhase {
        case .listening:
            secondary = state.recordingElapsedFixedLabel
        case .success, .failed:
            // e.g. "24w · 320 ms" or failure reason (truncated by view).
            secondary = state.phaseDetail.isEmpty ? nil : state.phaseDetail
        case .transcribing, .ready, .setup:
            secondary = nil
        }

        let model = ListeningBannerModel(
            phase: state.dictationPhase,
            secondaryLabel: secondary
        )

        ensurePanel()

        if let host {
            host.rootView = ListeningBannerView(model: model)
        } else if let panel {
            let view = NSHostingView(rootView: ListeningBannerView(model: model))
            view.frame = panel.contentView?.bounds ?? .zero
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            host = view
        }

        // Fixed geometry always — no resize while the clock ticks.
        if let panel {
            var frame = panel.frame
            frame.size = NSSize(width: Self.width, height: Self.height)
            panel.setFrame(frame, display: false)
            position(panel)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        panel = p
    }

    /// Sit just under the menu bar, screen center — never under the notch.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct ListeningBannerModel: Equatable {
    var phase: DictationPhase
    /// Timer while listening, or latency/summary on Done (e.g. "24w · 320 ms").
    var secondaryLabel: String?
}

struct ListeningBannerView: View {
    let model: ListeningBannerModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(lightColor)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if let secondary = model.secondaryLabel {
                Text(secondary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        switch model.phase {
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .success: return "Done"
        case .failed: return "Failed"
        default: return "MacWispr"
        }
    }

    private var accessibilityText: String {
        if let secondary = model.secondaryLabel {
            return "\(title), \(secondary)"
        }
        return title
    }

    private var lightColor: Color {
        switch model.phase {
        case .listening: return .red
        case .transcribing: return .orange
        case .success: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }
}
