import AppKit
import SwiftUI
import Combine

/// Floating banner under the menu bar while dictating.
///
/// Live monochrome transcript with fade-in words, 4-line scroll, and smooth
/// in-place morphs when ASR rewrites the hypothesis.
@MainActor
final class ListeningHUDController {
    static let shared = ListeningHUDController()

    /// ~30% narrower than the old 520pt strip.
    private static let minWidth: CGFloat = 180
    private static let liveWidth: CGFloat = 364
    private static let compactHeight: CGFloat = 40
    /// Header-less live card: 4 lines of body text + padding.
    private static let liveHeight: CGFloat = 118

    private var panel: NSPanel?
    private var host: NSHostingView<ListeningBannerView>?
    private let box = ListeningBannerBox()

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

        let live = state.currentTranscription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLive = !live.isEmpty
            && (state.dictationPhase == .listening || state.dictationPhase == .transcribing)

        let timer: String?
        switch state.dictationPhase {
        case .listening where !hasLive:
            timer = state.recordingElapsedFixedLabel
        default:
            timer = nil
        }

        let statusLine: String?
        switch state.dictationPhase {
        case .success, .failed:
            statusLine = state.phaseDetail.isEmpty ? nil : state.phaseDetail
        case .transcribing where !hasLive:
            statusLine = state.phaseDetail.isEmpty ? "Finalizing…" : state.phaseDetail
        case .listening where !hasLive:
            statusLine = nil
        default:
            statusLine = nil
        }

        // Show chrome (Listening / timer) only before any transcript exists.
        let showChrome = !hasLive

        box.model = ListeningBannerModel(
            phase: state.dictationPhase,
            timerLabel: showChrome ? timer : nil,
            liveTranscript: hasLive ? live : nil,
            statusLine: statusLine,
            showChrome: showChrome
        )

        ensurePanel()

        if host == nil, let panel {
            let view = NSHostingView(rootView: ListeningBannerView(box: box))
            view.frame = panel.contentView?.bounds ?? .zero
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            host = view
        }

        if let panel {
            let width = hasLive ? Self.liveWidth : Self.minWidth
            let height = hasLive ? Self.liveHeight : Self.compactHeight
            var frame = panel.frame
            frame.size = NSSize(width: width, height: height)
            panel.setFrame(frame, display: true)
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
            contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.compactHeight),
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

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Model

struct ListeningBannerModel: Equatable {
    var phase: DictationPhase
    var timerLabel: String?
    var liveTranscript: String?
    var statusLine: String?
    /// When false, hide Listening / red chrome — only the transcript card.
    var showChrome: Bool

    static let empty = ListeningBannerModel(
        phase: .ready,
        timerLabel: nil,
        liveTranscript: nil,
        statusLine: nil,
        showChrome: true
    )
}

@MainActor
final class ListeningBannerBox: ObservableObject {
    @Published var model: ListeningBannerModel = .empty
}

// MARK: - Word token for fade-in

private struct TranscriptWord: Identifiable, Equatable {
    let id: Int
    let text: String
    /// True while the word is still fading/sliding in.
    var isNew: Bool
}

// MARK: - View

struct ListeningBannerView: View {
    @ObservedObject var box: ListeningBannerBox

    /// Stable on-screen word list (never flash empty on rewrite).
    @State private var words: [TranscriptWord] = []
    @State private var nextWordID: Int = 0
    /// Words currently animating in (ids).
    @State private var fadingIDs: Set<Int> = []
    @State private var morphTask: Task<Void, Never>?
    @State private var scrollToken: Int = 0

    private var model: ListeningBannerModel { box.model }

    /// Visible height for ~4 lines of 13.5pt body.
    private static let transcriptLineHeight: CGFloat = 20
    private static let visibleLines: CGFloat = 4
    private static var transcriptViewportHeight: CGFloat {
        transcriptLineHeight * visibleLines
    }

    var body: some View {
        Group {
            if let live = model.liveTranscript, !live.isEmpty {
                liveTranscriptCard
            } else {
                chromeCard
            }
        }
        .onChange(of: model.liveTranscript) { _, newValue in
            morph(to: newValue ?? "")
        }
        .onAppear {
            if let live = model.liveTranscript {
                morph(to: live)
            }
        }
        .onDisappear {
            morphTask?.cancel()
        }
    }

    // MARK: Live transcript (B&W, no Listening chrome)

    private var liveTranscriptCard: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Flow layout: words wrap left→right, top→bottom.
                TranscriptFlowView(words: words, fadingIDs: fadingIDs)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .id("transcript-top")

                Color.clear
                    .frame(height: 1)
                    .id("transcript-bottom")
            }
            .frame(height: Self.transcriptViewportHeight + 24)
            .onChange(of: scrollToken) { _, _ in
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: words.count) { _, _ in
                scrollToken &+= 1
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.20), radius: 10, y: 3)
        .accessibilityLabel(words.map(\.text).joined())
    }

    // MARK: Pre-text chrome (timer only, monochrome)

    private var chromeCard: some View {
        HStack(spacing: 8) {
            Text(chromeTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if let timer = model.timerLabel {
                Text(timer)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let status = model.statusLine, !status.isEmpty {
                Text(status)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private var chromeTitle: String {
        switch model.phase {
        case .listening: return "Listening"
        case .transcribing: return "Finalizing"
        case .success: return "Done"
        case .failed: return "Failed"
        default: return "MacWispr"
        }
    }

    // MARK: Smooth morph (no full clear)

    /// Update on-screen tokens from a new ASR hypothesis without blanking.
    ///
    /// Strategy:
    /// - Tokenize Latin by words **and CJK by character** so Chinese can wrap.
    /// - Keep the common **prefix** with the same identity (no flash).
    /// - Fade new tail tokens in, staggered.
    private func morph(to newText: String) {
        let cleaned = newText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        // Critical for Chinese: no spaces between hanzi → must split CJK to wrap.
        let incoming = Self.tokenizeForWrap(cleaned)

        let current = words.map(\.text)
        if incoming == current { return }

        let shared = Self.commonWordPrefixCount(current, incoming)

        morphTask?.cancel()
        morphTask = Task { @MainActor in
            var rebuilt: [TranscriptWord] = Array(words.prefix(shared))
            var brandNewIDs: [Int] = []

            for token in incoming.dropFirst(shared) {
                let idx = rebuilt.count
                if idx < words.count,
                   words[idx].text.lowercased() == token.lowercased()
                {
                    rebuilt.append(TranscriptWord(id: words[idx].id, text: token, isNew: false))
                } else {
                    let id = nextWordID
                    nextWordID &+= 1
                    rebuilt.append(TranscriptWord(id: id, text: token, isNew: true))
                    brandNewIDs.append(id)
                }
            }

            fadingIDs.formUnion(brandNewIDs)
            withAnimation(.easeInOut(duration: 0.16)) {
                words = rebuilt
            }
            scrollToken &+= 1

            // CJK produces many more tokens — speed up so long Chinese tails stay snappy.
            let cjkHeavy = brandNewIDs.count > 12
                && brandNewIDs.count > 0
                && rebuilt.suffix(brandNewIDs.count).allSatisfy { Self.isCJKToken($0.text) }
            let stepNs: UInt64 = cjkHeavy ? 14_000_000 : 42_000_000
            let batch = cjkHeavy ? 3 : 1

            var i = 0
            while i < brandNewIDs.count {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 12_000_000)
                let end = min(i + batch, brandNewIDs.count)
                withAnimation(.easeOut(duration: 0.30)) {
                    for j in i..<end {
                        fadingIDs.remove(brandNewIDs[j])
                    }
                }
                i = end
                try? await Task.sleep(nanoseconds: stepNs)
            }
        }
    }

    /// Latin: space-separated words. CJK / Hangul / kana: one character per token
    /// so the flow layout can wrap across multiple lines.
    static func tokenizeForWrap(_ text: String) -> [String] {
        var tokens: [String] = []
        var latin = ""

        func flushLatin() {
            let t = latin.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { tokens.append(t) }
            latin = ""
        }

        for ch in text {
            if ch.isWhitespace || ch.isNewline {
                flushLatin()
                continue
            }
            if isCJKScalar(ch) {
                flushLatin()
                tokens.append(String(ch))
            } else {
                latin.append(ch)
            }
        }
        flushLatin()
        return tokens
    }

    private static func isCJKToken(_ s: String) -> Bool {
        s.count == 1 && s.first.map(isCJKScalar) == true
    }

    /// Han, kana, hangul, CJK punctuation, fullwidth forms — anything that
    /// typically wraps without spaces.
    private static func isCJKScalar(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            switch v {
            case 0x3000...0x303F, // CJK symbols & punctuation
                 0x3040...0x309F, // Hiragana
                 0x30A0...0x30FF, // Katakana
                 0x31F0...0x31FF, // Katakana phonetic extensions
                 0x3400...0x4DBF, // CJK Ext A
                 0x4E00...0x9FFF, // CJK Unified
                 0xAC00...0xD7AF, // Hangul syllables
                 0xF900...0xFAFF, // CJK compatibility ideographs
                 0xFF00...0xFFEF, // Halfwidth/fullwidth forms
                 0x20000...0x2A6DF: // CJK Ext B (if present)
                return true
            default:
                break
            }
        }
        return false
    }

    private static func commonWordPrefixCount(_ a: [String], _ b: [String]) -> Int {
        let n = min(a.count, b.count)
        var i = 0
        while i < n {
            if a[i].lowercased() != b[i].lowercased() { break }
            i += 1
        }
        return i
    }
}

// MARK: - Wrapping flow of tokens

/// Flow layout: tokens wrap left→right, top→bottom (works for CJK chars + Latin words).
private struct TranscriptFlowView: View {
    let words: [TranscriptWord]
    let fadingIDs: Set<Int>

    /// Tight gap between hanzi; wider between Latin words.
    private var horizontalSpacing: CGFloat {
        let cjk = words.filter { $0.text.count == 1 }.count
        return cjk * 2 >= words.count ? 1.5 : 5
    }

    var body: some View {
        WordWrapLayout(spacing: horizontalSpacing, lineSpacing: 5) {
            ForEach(words) { word in
                let isFading = fadingIDs.contains(word.id)
                Text(word.text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .opacity(isFading ? 0.18 : 1.0)
                    .offset(y: isFading ? 4 : 0)
                    .blur(radius: isFading ? 0.5 : 0)
                    .animation(.easeOut(duration: 0.30), value: isFading)
            }
        }
        // Ensure layout gets a real width for wrap decisions.
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Left-to-right, top-to-bottom wrap. Subviews wider than the line start a new row.
private struct WordWrapLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        guard maxWidth.isFinite, maxWidth > 0 else {
            // Unbounded: single row estimate.
            let w = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
                + CGFloat(max(0, subviews.count - 1)) * spacing
            let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return CGSize(width: w, height: h)
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
