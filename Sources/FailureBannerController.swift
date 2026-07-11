import AppKit
import SwiftUI

/// Non-activating failure toast with optional Accessibility / setup actions.
@MainActor
final class FailureBannerController {
    static let shared = FailureBannerController()

    private var panel: NSPanel?
    private var host: NSHostingView<FailureBannerView>?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(
        message: String,
        showAccessibilityFix: Bool,
        openSetup: Bool
    ) {
        hideTask?.cancel()

        let model = FailureBannerModel(
            message: message,
            showAccessibilityFix: showAccessibilityFix,
            openSetup: openSetup
        )

        ensurePanel()
        let view = FailureBannerView(
            model: model,
            onFixAX: { [weak self] in
                AppState.shared?.repairHotkey()
                self?.hide()
            },
            onOpenSetup: { [weak self] in
                AppState.shared?.reopenOnboarding()
                AppDelegate.shared?.showDashboard()
                self?.hide()
            },
            onDismiss: {
                AppState.shared?.dismissFailureBanner()
            }
        )

        if let host {
            host.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = panel?.contentView?.bounds ?? .zero
            hosting.autoresizingMask = [.width, .height]
            panel?.contentView = hosting
            host = hosting
        }

        // Size from intrinsic content
        if let host {
            let fitting = host.fittingSize
            let width = min(max(fitting.width, 280), 420)
            let height = max(fitting.height, 64)
            panel?.setContentSize(NSSize(width: width, height: height))
        }

        positionPanel()
        panel?.orderFrontRegardless()

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            // Don't auto-hide if still on failed phase with same message
            hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = false
        panel = p
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.maxX - size.width - 20
        let y = visible.maxY - size.height - 48
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct FailureBannerModel: Equatable {
    var message: String
    var showAccessibilityFix: Bool
    var openSetup: Bool
}

struct FailureBannerView: View {
    let model: FailureBannerModel
    var onFixAX: () -> Void
    var onOpenSetup: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(model.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                if model.showAccessibilityFix {
                    Button("Fix Accessibility", action: onFixAX)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if model.openSetup {
                    Button("Open Setup", action: onOpenSetup)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 400, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        .padding(4)
    }
}
