import AudioService
import Core
import DesignSystem
import SwiftUI

/// Active recording screen (mockup H3), driven by the live RecordingEngine:
/// real mic levels in the equalizer, real elapsed timer.
public struct RecordingView: View {
    @EnvironmentObject private var locale: LocaleManager
    @ObservedObject private var engine: RecordingEngine
    private let segments: [TranscriptSegment]
    private let onStop: () -> Void

    public init(engine: RecordingEngine, segments: [TranscriptSegment], onStop: @escaping () -> Void) {
        self.engine = engine
        self.segments = segments
        self.onStop = onStop
    }

    private var isPaused: Bool {
        engine.status == .paused
    }

    private var liveText: String {
        segments.last?.text ?? ""
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmberColor.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            RecordingBadge(label: locale.t("recording.status"), timecode: Format.timecode(engine.elapsed))
            Spacer()
            Button { isPaused ? engine.resume() : engine.pause() } label: {
                EmberIcon(isPaused ? .play : .pause, size: 15, lineWidth: 1.8, color: EmberColor.text2)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(EmberColor.border, lineWidth: 1))
            }
            .buttonStyle(EmberPressStyle())
            .hoverCursor()
            LanguageChip()
        }
        .frame(height: 60)
        .padding(.horizontal, 26)
        .overlay(alignment: .bottom) { Rectangle().fill(EmberColor.border).frame(height: 1) }
    }

    /// LazyVStack + a typewriter isolated in its own row: the 33Hz reveal timer used to
    /// live at screen level and re-evaluate EVERY transcript row 33×/s — on a long
    /// recording that meant O(n) text layout per frame (scroll lag + CPU heat). Now the
    /// timer redraws only the last row; confirmed rows (stable ids) render lazily.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(locale.t("transcript.live"))
                        .font(EmberType.mono(10.5)).tracking(1.26).textCase(.uppercase)
                        .foregroundStyle(EmberColor.text3)
                        .padding(.bottom, 22)

                    if segments.isEmpty {
                        Rectangle().fill(EmberColor.accent).frame(width: 2, height: 16).caretBlink()
                    }

                    ForEach(segments.dropLast()) { seg in
                        SegmentRow(seg: seg,
                                   meShort: locale.t("speaker.me.short"),
                                   themShort: locale.t("speaker.them.short"))
                    }
                    if let last = segments.last {
                        LiveTypewriterRow(seg: last, segmentCount: segments.count,
                                          meShort: locale.t("speaker.me.short"),
                                          themShort: locale.t("speaker.them.short"))
                    }
                    Color.clear.frame(height: 1).id("transcript-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
            }
            .scrollIndicators(.never)
            .onChange(of: segments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("transcript-bottom", anchor: .bottom) }
            }
            .onChange(of: liveText) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("transcript-bottom", anchor: .bottom) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 24) {
            Equalizer(levels: engine.levels, paused: isPaused)
                .animation(.linear(duration: 0.12), value: engine.levels)
            Button(action: { engine.stop(); onStop() }, label: {
                ZStack {
                    Circle().fill(EmberColor.rec).frame(width: 64, height: 64)
                        .shadow(color: Color(hex: "EF4444").opacity(0.4), radius: 24, x: 0, y: 10)
                    RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 22, height: 22)
                }
            })
            .buttonStyle(EmberPressStyle())
            .hoverCursor()
            Text(Format.timecode(engine.elapsed))
                .font(EmberType.mono(15))
                .foregroundStyle(EmberColor.rec)
                .frame(width: 54, alignment: .leading)
        }
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(EmberColor.border).frame(height: 1) }
    }
}

/// Timecode + speaker-tag prefix columns shared by both transcript row kinds.
private struct RowPrefix: View {
    let seg: TranscriptSegment
    let meShort: String
    let themShort: String

    var body: some View {
        Text(seg.timecode)
            .font(EmberType.mono(12))
            .foregroundStyle(EmberColor.text3)
            .padding(.top, 2)
        Group {
            if let lbl = SpeakerLabel.tag(source: seg.source, speaker: seg.speaker,
                                          meShort: meShort, themShort: themShort) {
                Text(lbl).font(EmberType.mono(11)).foregroundStyle(EmberColor.accentText).fixedSize()
            } else {
                Color.clear
            }
        }
        .frame(width: 27, alignment: .leading)
        .padding(.top, 2)
    }
}

/// A confirmed (static) transcript row — no timers, re-rendered only when its
/// segment changes.
private struct SegmentRow: View {
    let seg: TranscriptSegment
    let meShort: String
    let themShort: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RowPrefix(seg: seg, meShort: meShort, themShort: themShort)
            Text(seg.text).font(EmberType.regular(15)).lineSpacing(9).foregroundStyle(EmberColor.text)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
    }
}

/// The LIVE (last) row with the character-reveal typewriter. Owns its own 33Hz
/// timer + state so the animation only ever re-renders THIS row. Placed outside
/// the ForEach → structural identity is stable across live-hypothesis updates
/// (state survives the 1.8s re-decodes; resets when a NEW segment starts).
private struct LiveTypewriterRow: View {
    let seg: TranscriptSegment
    let segmentCount: Int
    let meShort: String
    let themShort: String

    @State private var shownChars = 0
    private let revealTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RowPrefix(seg: seg, meShort: meShort, themShort: themShort)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(seg.text.prefix(shownChars)))
                    .font(EmberType.regular(15)).lineSpacing(9).foregroundStyle(EmberColor.text2)
                Rectangle().fill(EmberColor.accent).frame(width: 2, height: 16).caretBlink()
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
        .onReceive(revealTimer) { _ in
            let target = seg.text.count
            if shownChars < target {
                shownChars = min(target, shownChars + max(1, (target - shownChars) / 8))
            }
        }
        .onChange(of: segmentCount) { _, _ in shownChars = 0 }
        .onChange(of: seg.text) { _, new in
            if shownChars > new.count { shownChars = new.count }
        }
    }
}
