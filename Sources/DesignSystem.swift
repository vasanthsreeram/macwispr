import SwiftUI

/// Shared spacing, radii, and surfaces so every pane uses the same rhythm.
enum DS {
    /// 4 pt grid.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
        static let xl: CGFloat = 18
    }

    /// Readable column for content panes; wide windows get margins instead of stretched rows.
    static let contentMaxWidth: CGFloat = 760

    /// Red from the app icon's glow. Used for recording and the brand surface only.
    static let ember = Color(red: 1.0, green: 0.27, blue: 0.23)
    /// Graphite gradient from the app icon tile.
    static let graphiteTop = Color(red: 0.25, green: 0.25, blue: 0.28)
    static let graphiteBottom = Color(red: 0.07, green: 0.07, blue: 0.09)

    static let hairline = Color.primary.opacity(0.08)
}

// MARK: - Surfaces

/// Quiet content card: control background, hairline border, no drop shadow.
struct CardSurface: ViewModifier {
    var padding: CGFloat = DS.Space.l
    var radius: CGFloat = DS.Radius.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
    }
}

/// Dark graphite surface with the icon's ember glow. One per screen at most.
struct BrandSurface: ViewModifier {
    var radius: CGFloat = DS.Radius.xl

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .environment(\.colorScheme, .dark)
            .background {
                shape
                    .fill(LinearGradient(
                        colors: [DS.graphiteTop, DS.graphiteBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .overlay {
                        RadialGradient(
                            colors: [DS.ember.opacity(0.28), .clear],
                            center: UnitPoint(x: 0.85, y: 1.1),
                            startRadius: 0,
                            endRadius: 320
                        )
                        .clipShape(shape)
                    }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = DS.Space.l, radius: CGFloat = DS.Radius.l) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }

    func brandSurface(radius: CGFloat = DS.Radius.xl) -> some View {
        modifier(BrandSurface(radius: radius))
    }

    /// Hit target through AppKit (SwiftUI `Button` can crash on macOS 26, GitHub #21).
    func appKitTap(_ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        self
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .overlay {
                AppKitClickTarget(isEnabled: enabled, accessibilityLabel: label, action: action)
            }
    }
}

// MARK: - Small components

/// Shortcut keys as keycaps, e.g. ⌥ Space.
struct Keycaps: View {
    let keys: [String]
    var size: CGFloat = 11
    var onDark = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .padding(.horizontal, key.count > 1 ? 6 : 5)
                    .padding(.vertical, 2)
                    .frame(minWidth: size + 9)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(onDark ? Color.white.opacity(0.12) : Color.primary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(onDark ? Color.white.opacity(0.14) : Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

enum ReadinessTone {
    case ready, busy, attention

    var color: Color {
        switch self {
        case .ready: return .green
        case .busy: return .orange
        case .attention: return .orange
        }
    }
}

/// 7 pt status dot plus a word.
struct StatusDot: View {
    let tone: ReadinessTone
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
                .shadow(color: tone.color.opacity(0.6), radius: 3)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Small rounded-square glyph tile, echoing the app icon.
struct GlyphTile: View {
    let systemImage: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [DS.graphiteTop, DS.graphiteBottom], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

/// Uppercase-free section label used above cards.
struct SectionLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension AppState {
    /// One status shared by the sidebar, Home, and the menu bar popover.
    var readiness: (tone: ReadinessTone, text: String) {
        if isModelLoading { return (.busy, "Setting up…") }
        if !isReadyToDictate { return (.attention, "Speech model not ready") }
        if !accessibilityTrusted { return (.attention, "Needs Accessibility") }
        if !hotkeyArmed { return (.attention, "Shortcut not active") }
        return (.ready, "Ready")
    }
}
