import AppKit
import SwiftUI
import Combine
import QuartzCore

/// Floating banner under the menu bar while dictating.
///
/// Live monochrome transcript with fade-in words. Card **grows with text**
/// up to ~4 lines, then stops expanding and auto-scrolls.
@MainActor
final class ListeningHUDController {
    static let shared = ListeningHUDController()

    /// ~30% narrower than the old 520pt strip.
    private static let minWidth: CGFloat = 180
    /// Live transcript card width (shared with SwiftUI so wrap never uses chrome width).
    static let liveWidth: CGFloat = 364
    private static let compactHeight: CGFloat = 40
    /// Vertical padding inside the live card (matches SwiftUI `.padding(.vertical, 12)` × 2).
    static let liveVerticalPadding: CGFloat = 24
    /// Approx one line of 14pt rounded body (+ layout line spacing).
    static let liveLineHeight: CGFloat = 20
    static let liveMaxLines: CGFloat = 4
    /// Minimum live card when only a word or two is on screen.
    static var liveMinHeight: CGFloat { liveLineHeight + liveVerticalPadding }
    /// Cap: ~4 lines of body + padding (no further growth; scroll instead).
    static var liveMaxHeight: CGFloat {
        liveLineHeight * liveMaxLines + 5 * (liveMaxLines - 1) + liveVerticalPadding
    }

    private var panel: NSPanel?
    private var host: NSHostingView<ListeningBannerView>?
    private let box = ListeningBannerBox()
    private var sizeCancellable: AnyCancellable?

    private init() {}

    func sync(with state: AppState) {
        // None = fully off. Also honor legacy listeningHUDEnabled.
        guard state.recordingWindowStyle != .none, state.listeningHUDEnabled else {
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

        // Mini: compact timer / status only — never expand into live text card.
        let allowLiveText = state.recordingWindowStyle == .classic

        let live = state.currentTranscription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLive = allowLiveText
            && !live.isEmpty
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
        let wasLive = box.model.liveTranscript.map { !$0.isEmpty } ?? false

        ensurePanel()

        if host == nil, let panel {
            let view = NSHostingView(rootView: ListeningBannerView(box: box))
            view.frame = panel.contentView?.bounds ?? .zero
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            host = view
        }

        // Leaving live mode resets measured height so the next session starts compact.
        if !hasLive {
            box.liveContentHeight = 0
        }

        // First partial: open at live width + one-line height *before* SwiftUI lays out
        // the transcript. Avoids the 180→364 width reflow that glitches line 1.
        if hasLive && !wasLive {
            box.liveContentHeight = Self.liveLineHeight
            applyPanelSize(hasLive: true, animated: false)
        }

        // Waveform polls this ~24 Hz; not @Published (avoids full banner re-renders).
        box.audioLevelProvider = { [weak state] in
            state?.audioRecorder.currentAudioLevel() ?? 0
        }

        box.model = ListeningBannerModel(
            phase: state.dictationPhase,
            timerLabel: showChrome ? timer : nil,
            liveTranscript: hasLive ? live : nil,
            statusLine: statusLine,
            showChrome: showChrome,
            glassStyle: state.liquidGlassStyle
        )

        // Chrome / leave-live: snap. Ongoing live height growth: animate.
        if !hasLive {
            applyPanelSize(hasLive: false, animated: false)
        } else if wasLive {
            applyPanelSize(hasLive: true, animated: true)
        }
        // else: already sized for first live word above

        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        box.liveContentHeight = 0
    }

    private func ensurePanel() {
        if panel != nil {
            observeContentHeightIfNeeded()
            return
        }
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
        observeContentHeightIfNeeded()
    }

    private func observeContentHeightIfNeeded() {
        guard sizeCancellable == nil else { return }
        sizeCancellable = box.$liveContentHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] height in
                guard let self else { return }
                // Only react to real multi-line growth after first seed (one-line).
                let hasLive = self.box.model.liveTranscript.map { !$0.isEmpty } ?? false
                guard hasLive, height > Self.liveLineHeight + 0.5 else { return }
                self.applyPanelSize(hasLive: true, animated: true)
            }
    }

    /// Grow with measured transcript body up to 4 lines, then hold max height.
    private static func livePanelHeight(contentBody: CGFloat) -> CGFloat {
        let body = contentBody > 1 ? contentBody : liveLineHeight
        let total = body + liveVerticalPadding
        return min(liveMaxHeight, max(liveMinHeight, total))
    }

    private func applyPanelSize(hasLive: Bool, animated: Bool) {
        guard let panel, let screen = NSScreen.main else { return }
        let width = hasLive ? Self.liveWidth : Self.minWidth
        let height = hasLive
            ? Self.livePanelHeight(contentBody: box.liveContentHeight)
            : Self.compactHeight

        let visible = screen.visibleFrame
        let x = visible.midX - width / 2
        let y = visible.maxY - height - 10
        let frame = NSRect(x: x, y: y, width: width, height: height)

        // Never animate a width change (chrome ↔ live) — only smooth height growth.
        let widthJump = abs(panel.frame.width - width) > 1
        let heightDelta = abs(panel.frame.height - height)
        let shouldAnimate = animated && panel.isVisible && !widthJump && heightDelta > 0.5

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
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
    /// Liquid Glass Clear / Tinted (macOS 26+).
    var glassStyle: LiquidGlassStyle

    static let empty = ListeningBannerModel(
        phase: .ready,
        timerLabel: nil,
        liveTranscript: nil,
        statusLine: nil,
        showChrome: true,
        glassStyle: .clear
    )
}

@MainActor
final class ListeningBannerBox: ObservableObject {
    @Published var model: ListeningBannerModel = .empty
    /// Measured height of the live transcript body (incl. inner vertical padding).
    /// Drives panel growth; clamped to 1…4 lines in the controller.
    @Published var liveContentHeight: CGFloat = 0
    /// Polled by the listening waveform only — deliberately not @Published.
    var audioLevelProvider: (() -> Float)?
}

/// Reports laid-out transcript size so the panel can grow with content.
private struct LiveTranscriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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

    /// Visible body cap for ~4 lines of 14pt body (+ inter-line spacing).
    private static let transcriptLineHeight: CGFloat = ListeningHUDController.liveLineHeight
    private static let visibleLines: CGFloat = ListeningHUDController.liveMaxLines
    private static let verticalPadding: CGFloat = ListeningHUDController.liveVerticalPadding
    private static var maxBodyHeight: CGFloat {
        // 4 lines of text + 3 gaps of ~5pt (WordWrapLayout lineSpacing).
        transcriptLineHeight * visibleLines + 5 * (visibleLines - 1)
    }
    private static var maxCardHeight: CGFloat { ListeningHUDController.liveMaxHeight }
    private static var minCardHeight: CGFloat { ListeningHUDController.liveMinHeight }

    /// Intrinsic content height from layout (includes vertical padding).
    @State private var measuredContentHeight: CGFloat = 0

    /// Card height: grows with content, stops at 4 lines.
    private var liveCardHeight: CGFloat {
        let measured = measuredContentHeight > 1
            ? measuredContentHeight
            : Self.transcriptLineHeight + Self.verticalPadding
        return min(Self.maxCardHeight, max(Self.minCardHeight, measured))
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
            // Seed one-line size so the first frame isn't empty/zero-height.
            if measuredContentHeight < 1 {
                measuredContentHeight = Self.transcriptLineHeight + Self.verticalPadding
            }
            if let live = model.liveTranscript {
                morph(to: live)
            }
        }
        .onDisappear {
            morphTask?.cancel()
            measuredContentHeight = 0
            box.liveContentHeight = 0
        }
    }

    // MARK: Live transcript (B&W, no Listening chrome)

    private var liveTranscriptCard: some View {
        // Fixed live width so wrap/measure never use the compact chrome width (180).
        let cardWidth = ListeningHUDController.liveWidth

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Flow layout: words wrap left→right, top→bottom.
                TranscriptFlowView(words: words, fadingIDs: fadingIDs)
                    .frame(width: cardWidth - 28, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: LiveTranscriptHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .id("transcript-top")

                Color.clear
                    .frame(height: 1)
                    .id("transcript-bottom")
            }
            // Viewport matches content until the 4-line cap, then scrolls.
            .frame(width: cardWidth, height: liveCardHeight, alignment: .top)
            .onPreferenceChange(LiveTranscriptHeightKey.self) { height in
                guard height > 1 else { return }
                // Avoid layout thrash on sub-point differences.
                if abs(height - measuredContentHeight) > 1 {
                    measuredContentHeight = height
                }
                // Body height without vertical padding — controller adds padding clamp.
                let body = max(Self.transcriptLineHeight, height - Self.verticalPadding)
                // Ignore noisy first layout if it's below one line (partial measure).
                guard body >= Self.transcriptLineHeight - 1 else { return }
                if abs(body - box.liveContentHeight) > 1 {
                    box.liveContentHeight = body
                }
            }
            .onChange(of: scrollToken) { _, _ in
                // Only auto-scroll once content has hit the 4-line cap.
                guard measuredContentHeight >= Self.maxCardHeight - 1 else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: words.count) { _, _ in
                scrollToken &+= 1
            }
        }
        .frame(width: cardWidth, height: liveCardHeight, alignment: .topLeading)
        .modifier(LiquidGlassSurface(
            style: model.glassStyle,
            shape: RoundedRectangle(cornerRadius: 16, style: .continuous)
        ))
        // Height growth only after first line is stable (no springy first-frame).
        .animation(
            measuredContentHeight > Self.minCardHeight + 2
                ? .easeInOut(duration: 0.16)
                : nil,
            value: liveCardHeight
        )
        .accessibilityLabel(words.map(\.text).joined())
    }

    // MARK: Pre-text chrome (timer only, monochrome)

    private var chromeCard: some View {
        HStack(spacing: 8) {
            if model.phase == .listening {
                // Live waveform — moves when the mic hears sound ("am I being heard?").
                // Metering only; no capture rebind (that path broke dictation in 1.2.8).
                ListeningWaveformView(levelProvider: { [weak box] in
                    box?.audioLevelProvider?() ?? 0
                })
                .frame(width: 92, height: 18)
                .accessibilityLabel("Listening")
            } else {
                Text(chromeTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

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
        .modifier(LiquidGlassSurface(
            style: model.glassStyle,
            shape: Capsule(style: .continuous)
        ))
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

// MARK: - Listening waveform

/// Scrolling bar waveform driven by live mic RMS. Low floor in silence, rises
/// with speech — doubles as an “am I being heard?” meter. Read-only metering.
private struct ListeningWaveformView: View {
    let levelProvider: () -> Float

    private static let barCount = 26
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 1.5

    @State private var history: [CGFloat] = Array(repeating: 0, count: barCount)
    private let timer = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let maxHeight = geo.size.height
            HStack(alignment: .center, spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(
                            width: Self.barWidth,
                            height: max(2, history[i] * maxHeight)
                        )
                }
            }
            .frame(width: geo.size.width, height: maxHeight, alignment: .center)
        }
        .onReceive(timer) { _ in
            // Typical speech RMS ~0.01–0.3; curve lifts quiet speech without pegging loud.
            let raw = max(0, levelProvider())
            let normalized = CGFloat(min(1.0, pow(Double(raw) * 9.0, 0.65)))
            var next = history
            next.removeFirst()
            next.append(normalized)
            withAnimation(.linear(duration: 1.0 / 24.0)) {
                history = next
            }
        }
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

// MARK: - Liquid Glass (macOS 26+)

/// System Liquid Glass for the floating HUD. Falls back to materials on older OS.
/// Public API: `glassEffect(.clear)` / `glassEffect(.regular.tint(...))` — not the private
/// System Settings Assets.car tiles (AppearanceAuto / GlassClear / …).
struct LiquidGlassSurface<S: InsettableShape>: ViewModifier {
    let style: LiquidGlassStyle
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(glassVariant, in: shape)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
    }

    @available(macOS 26.0, *)
    private var glassVariant: Glass {
        switch style {
        case .clear:
            return .clear
        case .tinted:
            // Soft accent tint — same idea as System Settings “Tinted”.
            return .regular.tint(Color.accentColor.opacity(0.45))
        }
    }
}
