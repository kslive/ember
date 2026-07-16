import AppKit
import Core
import DesignSystem
import SwiftUI

/// Borderless, non-activating floating panel for the live-context card. Floats
/// above every app (including other apps' fullscreen Spaces), never steals key
/// focus, and opts out of screen capture via `sharingType = .none` — reliable on
/// legacy capture paths and macOS ≤ 15.3; BEST-EFFORT on newer macOS where Apple
/// regressed the ScreenCaptureKit exclusion (FB21115847). Honest wording lives in
/// the settings description.
private final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        sharingType = .none
        animationBehavior = .utilityWindow
    }

    /// No text input inside — the panel must never take key focus from the call app.
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// The LOGICAL anchor (top-right corner) the panel is pinned to. Content-
    /// driven resizes (collapse/expand animation frames, feed growth) recompute
    /// the origin from it SYNCHRONOUSLY — an async observer lagged a frame and
    /// the window shot past the screen edge while blooming. nil = free.
    var pin: NSPoint?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        // Only intercept SIZE changes; plain moves (user drags) pass through.
        if let pin, abs(r.width - frame.width) > 0.5 || abs(r.height - frame.height) > 0.5 {
            r.origin = NSPoint(x: pin.x - r.width, y: pin.y - r.height)
            r = Self.clamped(r, pin: pin)
        }
        super.setFrame(r, display: flag)
    }

    /// Keeps the whole rect on the pin's screen: the pill can sit in ANY corner —
    /// expanding near the left/bottom edges slides the card back inside instead
    /// of opening off-screen.
    static func clamped(_ rect: NSRect, pin: NSPoint) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pin) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return rect }
        let vis = screen.visibleFrame
        var r = rect
        r.origin.x = min(max(r.origin.x, vis.minX + 8), max(vis.minX + 8, vis.maxX - r.width - 8))
        r.origin.y = min(max(r.origin.y, vis.minY + 8), max(vis.minY + 8, vis.maxY - r.height - 8))
        return r
    }
}

/// Collapsed/expanded state of the overlay, shared by the controller and the
/// SwiftUI card: every session starts as a small LIVE pill at the screen's
/// top-right corner («чтоб не маячило перед глазами») — click expands the feed,
/// the header's «—» collapses it back.
@MainActor
final class OverlayUIState: ObservableObject {
    @Published var collapsed = true
    /// Which corner the bloom/fold animation grows from — follows the screen
    /// quadrant the pill sits in, so a pill dragged to the bottom-left opens
    /// upward-right instead of off-screen.
    @Published var bloomAnchor: UnitPoint = .topTrailing
}

/// Owns the overlay panel lifecycle: shown while a recording runs (and the
/// toggle is on), hidden on stop. ✕ hides it for the rest of the session.
@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private(set) var dismissedForSession = false
    private let ui = OverlayUIState()
    /// The panel's TOP-RIGHT corner in screen coords — the panel is PINNED to it:
    /// collapse/expand and feed growth extend leftward/downward (the card hugs
    /// the screen edge instead of drifting), and a user drag just moves the pin.
    private var anchor: NSPoint?
    private var observers: [NSObjectProtocol] = []

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(engine: LiveContextEngine) {
        guard !dismissedForSession else { return }
        if panel == nil {
            let p = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40))
            let root = LiveContextOverlayView(engine: engine, ui: ui, onClose: { [weak self] in
                self?.dismissedForSession = true
                self?.hide()
                // Dismissed for the session → free the live model RIGHT AWAY (the
                // 1.7B must not sit in RAM behind a hidden card).
                engine.stop()
            })
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = [.preferredContentSize]
            p.contentView = hosting
            panel = p
            installObservers(p)
        }
        // Every session starts COLLAPSED at the top-right corner of the screen.
        // NSScreen.main can be nil while the app sits in the background (auto-
        // started calls) — falling through left the STALE anchor from wherever
        // the last session was dragged ("капсула в рандомном месте").
        ui.collapsed = true
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            anchor = NSPoint(x: f.maxX - 16, y: f.maxY - 16)
        }
        applyAppearance()
        repin()
        guard let panel else { return }
        if panel.isVisible {
            panel.orderFrontRegardless()
        } else {
            // Fade in; re-pin once more after the first SwiftUI layout pass has
            // sized the pill (the panel may still carry last session's card size).
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [weak self] in self?.repin() }
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.panel?.orderOut(nil)
                self?.panel?.alphaValue = 1
            }
        }
    }

    /// Recording ended — hide and re-arm the ✕ for the next session.
    func end() {
        hide()
        dismissedForSession = false
    }

    /// A user drag (didMove) re-learns the pin; content resizes are handled
    /// SYNCHRONOUSLY inside OverlayPanel.setFrame. A programmatic repin also
    /// fires didMove, but re-reading the SAME corner is a harmless no-op.
    private func installObservers(_ p: NSPanel) {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                let corner = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
                self.anchor = corner
                panel.pin = corner
                self.updateBloomAnchor(for: corner)
            }
        })
    }

    private func repin() {
        guard let panel, let anchor else { return }
        panel.pin = anchor
        updateBloomAnchor(for: anchor)
        let rect = OverlayPanel.clamped(
            NSRect(x: anchor.x - panel.frame.width, y: anchor.y - panel.frame.height,
                   width: panel.frame.width, height: panel.frame.height),
            pin: anchor
        )
        panel.setFrameOrigin(rect.origin)
    }

    /// The bloom direction follows the screen quadrant of the pin.
    private func updateBloomAnchor(for corner: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(corner) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vis = screen.visibleFrame
        let horizontal: UnitPoint = corner.x < vis.midX ? .leading : .trailing
        let vertical: UnitPoint = corner.y < vis.midY ? .bottom : .top
        ui.bloomAnchor = UnitPoint(x: horizontal.x, y: vertical.y)
    }

    /// The overlay follows the APP theme (dark/light/auto), not the system: the
    /// Ember tokens resolve through the panel's effective appearance.
    private func applyAppearance() {
        let theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "ember.theme") ?? "auto") ?? .auto
        switch theme {
        case .dark: panel?.appearance = NSAppearance(named: .darkAqua)
        case .light: panel?.appearance = NSAppearance(named: .aqua)
        case .auto: panel?.appearance = nil
        }
    }
}

/// The live-context FEED: the meeting's storyline as topic entries with
/// timecodes — same-topic snapshots refresh in place, topic changes append.
/// Scrollable (the whole call's context is browsable), auto-follows the newest.
/// AI-only content — never raw transcript lines.
struct LiveContextOverlayView: View {
    @ObservedObject var engine: LiveContextEngine
    @ObservedObject var ui: OverlayUIState
    let onClose: () -> Void
    /// User-adjustable cap: the card WRAPS its content up to this height, then
    /// scrolls. Dragged via the grip at the bottom edge; persisted.
    @AppStorage("ember.overlay.maxHeight") private var maxFeedHeight = 260.0
    @State private var feedContentHeight: CGFloat = 0
    /// Height during a grip drag — @State only; committed to @AppStorage on
    /// mouse-up (a synchronous UserDefaults write per dragged pixel caused lag).
    @State private var liveMaxHeight = 260.0
    /// Copy-all button feedback: swaps the icon to a checkmark for a beat.
    @State private var copied = false
    /// Hover lift for the collapsed LIVE pill.
    @State private var pillHovering = false

    private static let minFeedHeight = 120.0
    private static let maxFeedHeightCap = 560.0

    var body: some View {
        // The collapse/expand morph around the pinned top-trailing corner.
        // Direction-specific timing lives at the toggle call sites: expanding
        // BLOOMS on a spring; collapsing FOLDS fast (0.16s) — the window can only
        // snap to the pill size when the card is fully gone (the container holds
        // the union size during a transition), so the fold must be quick or the
        // end snap reads as jank.
        Group {
            if ui.collapsed {
                pill
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.6, anchor: ui.bloomAnchor).combined(with: .opacity)
                    ))
            } else {
                card
                    .transition(.scale(scale: 0.55, anchor: ui.bloomAnchor).combined(with: .opacity))
            }
        }
    }

    /// Collapsed state: a small LIVE pill that stays out of the way. Click to
    /// expand; the panel itself is draggable (movable by window background).
    private var pill: some View {
        HStack(spacing: 7) {
            Circle().fill(EmberColor.rec).frame(width: 7, height: 7).recPulse()
            Text("LIVE").font(EmberType.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(EmberColor.text3)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(EmberColor.surface2.opacity(pillHovering ? 1 : 0.94))
        .overlay(Capsule().strokeBorder(pillHovering ? EmberColor.borderStrong : EmberColor.border, lineWidth: 1))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .scaleEffect(pillHovering ? 1.07 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pillHovering)
        // Transparent margin INSIDE the window: the panel hugs the pill exactly,
        // so the hover scale-up was clipped by the window bounds.
        .padding(6)
        .onHover { pillHovering = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { ui.collapsed = false }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch engine.phase {
            case .active:
                feed
            case .waiting, .idle:
                shimmer
            case .degraded:
                unavailable
            }
            if engine.phase == .active { resizeGrip }
        }
        .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 6)
        .frame(width: 340, alignment: .leading)
        .background(EmberColor.surface2.opacity(0.94))
        .overlay(RoundedRectangle(cornerRadius: EmberRadius.lg).strokeBorder(EmberColor.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: EmberRadius.lg))
        // Animate only NEW entries — animating every streamed text update (each
        // ~100ms partial flush) kept the whole card in permanent re-animation.
        .animation(.easeInOut(duration: 0.3), value: engine.entries.count)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(EmberColor.rec).frame(width: 7, height: 7).recPulse()
            Text("LIVE").font(EmberType.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(EmberColor.text3)
            Spacer()
            if !engine.entries.isEmpty {
                Button(action: copyAll) {
                    EmberIcon(copied ? .check : .copy, size: 12, lineWidth: 2,
                              color: copied ? EmberColor.good : EmberColor.text3)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(LocalizedStrings.current("overlay.copyAll"))
            }
            Button {
                withAnimation(.easeIn(duration: 0.16)) { ui.collapsed = true }
            } label: {
                EmberIcon(.minus, size: 12, lineWidth: 2, color: EmberColor.text3)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                EmberIcon(.close, size: 12, lineWidth: 2, color: EmberColor.text3)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Copies the WHOLE feed (timecodes included) as plain text — the card can't
    /// be text-selected, and photographing it to share was the alternative.
    private func copyAll() {
        let text = LiveContextLogic.exportText(engine.entries.map { (at: $0.at, context: $0.context) },
                                               lang: .current)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    /// Scrollable storyline, pinned to the newest entry as it grows/updates.
    /// WRAPS its content: the card is only as tall as the feed, up to the
    /// user-set cap — then it scrolls (a plain VStack so the measured height is
    /// exact; entries are lightweight).
    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // .equatable(): frozen blocks never change (append-only feed),
                    // so their bodies are SKIPPED on every update — only the live
                    // block re-renders. Without this, long feeds re-built every
                    // row (and re-parsed every point's markdown) per frame and
                    // scrolling lagged.
                    ForEach(Array(engine.entries.enumerated()), id: \.element.id) { idx, entry in
                        EntryRow(entry: entry, showsDivider: idx > 0)
                            .equatable()
                            .id(entry.id)
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: FeedHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .onPreferenceChange(FeedHeightKey.self) { feedContentHeight = $0 }
            .frame(height: min(max(feedContentHeight, 30), liveMaxHeight))
            .scrollIndicators(.never)
            .onChange(of: engine.entries.last?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onChange(of: engine.entries.last?.context) { _, _ in
                if let id = engine.entries.last?.id {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onAppear {
                if let id = engine.entries.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private struct FeedHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Bottom grip: drag to set how tall the card may grow before scrolling.
    /// A NATIVE AppKit view (proper ↕ cursor, `mouseDownCanMoveWindow=false`):
    /// the SwiftUI gesture fought the panel's background window-drag and felt
    /// dead/laggy. During the drag the height lives in @State only — the old
    /// @AppStorage write per pixel hit UserDefaults synchronously every frame
    /// (the lag); it's committed once on mouse-up.
    private var resizeGrip: some View {
        ResizeGrip(
            onDrag: { delta in
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    liveMaxHeight = min(Self.maxFeedHeightCap, max(Self.minFeedHeight, liveMaxHeight + delta))
                }
            },
            onEnd: { maxFeedHeight = liveMaxHeight }
        )
        .frame(height: 14)
        .overlay {
            Capsule().fill(EmberColor.borderStrong).frame(width: 36, height: 4)
                .allowsHitTesting(false)
        }
        .onAppear { liveMaxHeight = maxFeedHeight }
    }

    /// One feed entry: timecode + topic, then the SUBSTANCE as short accent
    /// bubbles ("→ one thought each") — the format the user reads at a glance.
    /// A question's reply suggestion is just another bubble, marked "?".
    /// Equatable: frozen entries skip re-rendering entirely (see the ForEach).
    private struct EntryRow: View, Equatable {
        let entry: LiveContextEntry
        let showsDivider: Bool

        static func == (a: Self, b: Self) -> Bool {
            a.entry == b.entry && a.showsDivider == b.showsDivider
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.timecode(entry.at))
                        .font(EmberType.mono(10)).foregroundStyle(EmberColor.text3)
                    Text(Self.mdInline(entry.context.topic))
                        .font(EmberType.semibold(13)).foregroundStyle(EmberColor.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(entry.context.points, id: \.self) { point in
                    bubble(point, marker: "→")
                }
                if let a = entry.context.answer {
                    bubble(a, marker: "?")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .overlay(alignment: .top) {
                if showsDivider { Rectangle().fill(EmberColor.border).frame(height: 1) }
            }
        }

        private func bubble(_ text: String, marker: String) -> some View {
            HStack(alignment: .top, spacing: 6) {
                Text(marker).font(EmberType.semibold(12)).foregroundStyle(EmberColor.accentText)
                Text(Self.mdInline(text)).font(EmberType.medium(12)).lineSpacing(2)
                    .foregroundStyle(EmberColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmberColor.accentWeak)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        /// The prompt forbids markdown, but models slip **bold**/`code` in anyway
        /// — render it as inline styling. CACHED: parsing every point of every
        /// block on each streamed update was the scroll-lag hot path. UI-thread
        /// only (all callers are view bodies).
        private nonisolated(unsafe) static var mdCache: [String: AttributedString] = [:]
        private static func mdInline(_ s: String) -> AttributedString {
            if let hit = mdCache[s] { return hit }
            let parsed = (try? AttributedString(
                markdown: s,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(s)
            if mdCache.count > 512 { mdCache.removeAll(keepingCapacity: true) }
            mdCache[s] = parsed
            return parsed
        }
    }

    /// Placeholder bars while the first snapshot is being generated — a proper
    /// sweeping shimmer (no scale pulse). Capped by the engine at ~8s.
    private var shimmer: some View {
        VStack(alignment: .leading, spacing: 7) {
            bar(width: 180, height: 11)
            bar(width: 280, height: 9)
            bar(width: 230, height: 9)
        }
        .shimmerSweep()
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(EmberColor.text.opacity(0.08))
            .frame(width: width, height: height)
    }

    /// AI unavailable — an honest status note (never raw transcript lines);
    /// generation keeps retrying behind it.
    private var unavailable: some View {
        Text(LocalizedStrings.current("overlay.unavailable"))
            .font(EmberType.regular(12)).lineSpacing(2)
            .foregroundStyle(EmberColor.text3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Native resize grip: a real AppKit view handling the drag itself — SwiftUI
/// DragGesture lost the fight against `isMovableByWindowBackground` (the WINDOW
/// moved instead). Shows the proper ↕ cursor and never moves the panel.
private struct ResizeGrip: NSViewRepresentable {
    let onDrag: (Double) -> Void
    let onEnd: () -> Void

    final class GripView: NSView {
        var onDrag: ((Double) -> Void)?
        var onEnd: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(Double(event.deltaY))
        }

        override func mouseUp(with _: NSEvent) {
            onEnd?()
        }
    }

    func makeNSView(context _: Context) -> NSView {
        let v = GripView()
        v.onDrag = onDrag
        v.onEnd = onEnd
        return v
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let grip = view as? GripView else { return }
        grip.onDrag = onDrag
        grip.onEnd = onEnd
    }
}
