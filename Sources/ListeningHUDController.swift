import AppKit
import SwiftUI

/// Compact non-activating floating HUD for eyes-free dictation status.
/// Shows listening / transcribing / success / fail without stealing focus.
@MainActor
final class ListeningHUDController {
    static let shared = ListeningHUDController()

    private var panel: NSPanel?
    private var host: NSHostingView<ListeningHUDView>?

    private init() {}

    func sync(with state: AppState) {
        guard state.listeningHUDEnabled else {
            hide()
            return
        }

        // Only show while actively dictating or briefly after success/fail.
        let visible: Bool
        switch state.dictationPhase {
        case .listening, .transcribing, .success, .failed:
            visible = true
        case .setup, .ready:
            visible = false
        }

        guard visible else {
            hide()
            return
        }

        let model = ListeningHUDModel(
            phase: state.dictationPhase,
            detail: state.phaseDetail.isEmpty ? statusFallback(state) : state.phaseDetail,
            elapsedLabel: state.dictationPhase == .listening ? state.recordingElapsedLabel : nil
        )

        if let host {
            host.rootView = ListeningHUDView(model: model)
        } else {
            ensurePanel()
            let view = NSHostingView(rootView: ListeningHUDView(model: model))
            view.frame = panel?.contentView?.bounds ?? .zero
            view.autoresizingMask = [.width, .height]
            panel?.contentView = view
            host = view
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func statusFallback(_ state: AppState) -> String {
        switch state.dictationPhase {
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .success: return "Done"
        case .failed: return "Failed"
        case .ready: return "Ready"
        case .setup: return "Setup"
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
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

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct ListeningHUDModel: Equatable {
    var phase: DictationPhase
    var detail: String
    var elapsedLabel: String?
}

struct ListeningHUDView: View {
    let model: ListeningHUDModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if model.phase == .listening {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.6)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let elapsed = model.elapsedLabel {
                Spacer(minLength: 8)
                Text(elapsed)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(4)
    }

    private var title: String {
        switch model.phase {
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .success: return "Done"
        case .failed: return "Failed"
        case .ready: return "Ready"
        case .setup: return "Setup"
        }
    }

    private var dotColor: Color {
        switch model.phase {
        case .listening: return .red
        case .transcribing: return .orange
        case .success: return .green
        case .failed: return .red
        case .ready: return .green
        case .setup: return .orange
        }
    }
}
