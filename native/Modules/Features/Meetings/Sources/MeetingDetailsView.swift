import AppKit
import Core
import DesignSystem
import SummaryService
import SwiftUI

/// Meeting detail (mockup M1/M2): two panes — transcript on the left, summary
/// on the right (empty / generating / ready states).
public struct MeetingDetailsView: View {
    @EnvironmentObject private var locale: LocaleManager
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var summarySvc: SummaryService
    private let meeting: Meeting
    private let segments: [TranscriptSegment]
    private let summary: MeetingSummary?
    private let isProcessing: Bool
    private let progress: ProcessingProgress?
    private let onRegenerate: () -> Void
    private let onRename: (String) -> Void

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var splitFraction: CGFloat = 1.15 / 2.15
    private let minPane: CGFloat = 320

    public init(meeting: Meeting, segments: [TranscriptSegment], summary: MeetingSummary?, isProcessing: Bool,
                progress: ProcessingProgress? = nil,
                summaryService: SummaryService,
                onRegenerate: @escaping () -> Void, onRename: @escaping (String) -> Void = { _ in }) {
        self.meeting = meeting
        self.segments = segments
        self.summary = summary
        self.isProcessing = isProcessing
        self.progress = progress
        summarySvc = summaryService
        self.onRegenerate = onRegenerate
        self.onRename = onRename
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let w = geo.size.width
                let raw = w * splitFraction
                let leftW = min(max(raw, minPane), max(minPane, w - minPane))
                HStack(spacing: 0) {
                    transcriptPane
                        .frame(width: leftW)
                    divider(totalWidth: w)
                    summaryPane
                        .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "split")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmberColor.bg)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                if editingTitle {
                    TextField("", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(EmberType.semibold(23)).tracking(-0.46)
                        .foregroundStyle(EmberColor.text)
                        .focused($titleFocused)
                        .onSubmit(commitTitle)
                        .onChange(of: titleFocused) { _, f in if !f { commitTitle() } }
                } else {
                    Text(meeting.title)
                        .font(EmberType.semibold(23)).tracking(-0.46)
                        .foregroundStyle(EmberColor.text)
                        .onTapGesture(count: 2) { startEditingTitle() }
                        .help(locale.t("meeting.renameHint"))
                }
                Text(metaLine)
                    .font(EmberType.mono(12))
                    .foregroundStyle(EmberColor.text3)
            }
            Spacer()
            HStack(spacing: 8) {
                EmberButton(locale.t("meeting.copy"), kind: .secondary, height: 34) {
                    copyToPasteboard()
                }
                EmberButton(locale.t("meeting.regenerate"), kind: .primary, height: 34, action: onRegenerate)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(EmberColor.border).frame(height: 1) }
    }

    private func startEditingTitle() {
        titleDraft = meeting.title
        editingTitle = true
        titleFocused = true
    }

    private func commitTitle() {
        guard editingTitle else { return }
        editingTitle = false
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != meeting.title { onRename(trimmed) }
    }

    private var metaLine: String {
        var parts: [String] = []
        parts.append(Format.date(meeting.createdAt, format: "d MMMM yyyy", language: locale.language))
        if let d = meeting.durationSeconds, d > 0 { parts.append(Format.duration(d, language: locale.language)) }
        if let p = meeting.participantCount { parts.append("\(p) \(locale.t("meeting.participants"))") }
        return parts.joined(separator: " · ")
    }

    private func divider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(EmberColor.border)
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(
                        DragGesture(coordinateSpace: .named("split"))
                            .onChanged { v in
                                guard totalWidth > 2 * minPane else { return }
                                let f = v.location.x / totalWidth
                                splitFraction = min(max(f, minPane / totalWidth), 1 - minPane / totalWidth)
                            }
                    )
            )
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneLabel(locale.t("meeting.transcript"))
                .padding(.horizontal, 30).padding(.top, 24)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if segments.isEmpty {
                        Text(locale.t("meeting.processing"))
                            .font(EmberType.regular(13.5)).foregroundStyle(EmberColor.text3)
                    } else {
                        ForEach(segments) { seg in
                            HStack(alignment: .top, spacing: 6) {
                                Text(seg.timecode).font(EmberType.mono(12)).foregroundStyle(EmberColor.text3).padding(.top, 2)
                                Group {
                                    if let lbl = SpeakerLabel.tag(source: seg.source, speaker: seg.speaker,
                                                                  meShort: locale.t("speaker.me.short"),
                                                                  themShort: locale.t("speaker.them.short")) {
                                        Text(lbl).font(EmberType.mono(11)).foregroundStyle(EmberColor.accentText).fixedSize()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 27, alignment: .leading)
                                .padding(.top, 2)
                                Text(seg.text).font(EmberType.regular(14.5)).lineSpacing(8).foregroundStyle(EmberColor.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.bottom, 18)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
    }

    /// Staged processing indicator: spinner + "step N of M" + what is happening
    /// right now, cross-fading upward as the pipeline advances (transcribe →
    /// diarize → summarize). Single-step runs (regenerate) show just the title.
    private var processingState: some View {
        VStack(spacing: 18) {
            Spinner()
            if let progress {
                VStack(spacing: 9) {
                    if progress.total > 1 {
                        Text(locale.t("processing.step", ["n": "\(progress.step)", "t": "\(progress.total)"]))
                            .font(EmberType.mono(10.5)).tracking(1.2)
                            .foregroundStyle(EmberColor.text3)
                            .textCase(.uppercase)
                    }
                    Text(locale.t(progress.stage.titleKey))
                        .font(EmberType.medium(13.5)).foregroundStyle(EmberColor.text2)
                }
                .id(progress.step)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                if progress.total > 1 {
                    OnboardingDots(active: progress.step - 1, total: progress.total)
                }
            } else {
                Text(locale.t("meeting.generating")).font(EmberType.regular(13.5)).foregroundStyle(EmberColor.text2)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress?.step ?? 0)
    }

    @ViewBuilder private var summaryPane: some View {
        if isProcessing {
            processingState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let summary, !summary.markdown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                summaryLabel
                    .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 18)
                ScrollView {
                    SummaryMarkdownView(md: summary.markdown)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
                Rectangle().fill(EmberColor.border).frame(height: 1)
                HStack(spacing: 14) {
                    Text(locale.t("meeting.savedMd")).font(EmberType.regular(12)).foregroundStyle(EmberColor.text3)
                        .lineLimit(1)
                    Spacer()
                    if SageIntegration.isInstalled {
                        SageGlowButton(locale.t("meeting.openSage")) { openInSage(summary.markdown) }
                            .layoutPriority(1)
                    } else {
                        Button(action: { openInObsidian(summary.markdown) }, label: {
                            Text(locale.t("meeting.openObsidian")).font(EmberType.medium(12.5)).foregroundStyle(EmberColor.accentText)
                                .contentShape(Rectangle())
                        })
                        .buttonStyle(EmberPressStyle()).hoverCursor()
                    }
                }
                .padding(.horizontal, 30).padding(.vertical, 16)
            }
        } else {
            VStack(spacing: 14) {
                EmberIcon(.sparkle, size: 26, lineWidth: 1.7, color: EmberColor.accentText)
                    .frame(width: 54, height: 54)
                    .background(EmberColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(locale.t("meeting.noSummary")).font(EmberType.semibold(17)).foregroundStyle(EmberColor.text)
                Text(locale.t("meeting.noSummaryDesc"))
                    .font(EmberType.regular(13.5)).lineSpacing(3)
                    .foregroundStyle(EmberColor.text2).multilineTextAlignment(.center).frame(maxWidth: 300)
                EmberButton(locale.t("meeting.generate"), kind: .primary, height: 46, action: onRegenerate)
                    .frame(maxWidth: 320)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }

    private func paneLabel(_ text: String) -> some View {
        Text(text)
            .font(EmberType.mono(10.5)).tracking(1.26).textCase(.uppercase)
            .foregroundStyle(EmberColor.text3)
            .padding(.bottom, 18)
    }

    /// Summary section label with a continuously-pulsing accent sparkle.
    private var summaryLabel: some View {
        HStack(spacing: 7) {
            EmberIcon(.sparkle, size: 13, lineWidth: 1.7, color: EmberColor.accentText)
                .softPulse()
            Text(locale.t("meeting.summary"))
                .font(EmberType.mono(10.5)).tracking(1.26).textCase(.uppercase)
                .foregroundStyle(EmberColor.text3)
        }
    }

    private func copyToPasteboard() {
        let text = segments.map { "[\($0.timecode)] \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes the summary .md into the chosen export folder, then opens THAT file in
    /// Obsidian by path (not a throwaway new note). Falls back to the default app.
    /// Writes the export .md (same file the Obsidian flow uses) and deep-links it
    /// into Sage (`sage://open?path=…`).
    private func openInSage(_ md: String) {
        guard let url = SummaryExport.write(markdown: md, title: meeting.title, createdAt: meeting.createdAt,
                                            typeLabel: locale.t("meeting.exportType"),
                                            folder: settings.exportFolderPath) else { return }
        SageIntegration.open(file: url)
    }

    private func openInObsidian(_ md: String) {
        guard let url = SummaryExport.write(markdown: md, title: meeting.title, createdAt: meeting.createdAt,
                                            typeLabel: locale.t("meeting.exportType"),
                                            folder: settings.exportFolderPath) else { return }
        var comps = URLComponents()
        comps.scheme = "obsidian"
        comps.host = "open"
        comps.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let u = comps.url, NSWorkspace.shared.open(u) { return }
        NSWorkspace.shared.open(url)
    }
}

/// Structured Markdown renderer for the summary (headings / callouts / bullets /
/// checkboxes). `Equatable` on `md` so it isn't re-parsed every frame while the
/// transcript↔summary divider is being dragged (splitFraction churns the parent).
struct SummaryMarkdownView: View, Equatable {
    let md: String
    static func == (a: SummaryMarkdownView, b: SummaryMarkdownView) -> Bool {
        a.md == b.md
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(md.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Color.clear.frame(height: 4)
                } else if line.hasPrefix("# ") {
                    EmptyView()
                } else if line.hasPrefix("### ") {
                    Text(String(line.dropFirst(4))).font(EmberType.semibold(13.5)).foregroundStyle(EmberColor.text).padding(.top, 6)
                } else if line.hasPrefix("## ") {
                    Text(String(line.dropFirst(3))).font(EmberType.semibold(14)).foregroundStyle(EmberColor.text).padding(.top, 8)
                } else if line.hasPrefix("> [!") {
                    let inner = line.dropFirst(3)
                    let type = String(inner.drop(while: { $0 == "!" }).prefix(while: { $0 != "]" })).lowercased()
                    let rest = String(inner.drop(while: { $0 != "]" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                    let m = Self.calloutMeta(type)
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 1.5).fill(m.color).frame(width: 2.5).padding(.vertical, 2)
                        Text("\(m.emoji)  \(rest)")
                            .font(EmberType.semibold(13.5)).foregroundStyle(m.color).lineSpacing(2)
                        Spacer(minLength: 0)
                    }.fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                } else if line.hasPrefix("> ") {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1).fill(EmberColor.accent).frame(width: 2).padding(.vertical, 1)
                        Text(Self.inline(String(line.dropFirst(2)))).font(EmberType.regular(13.5)).italic().lineSpacing(2)
                            .foregroundStyle(EmberColor.text2)
                        Spacer(minLength: 0)
                    }.fixedSize(horizontal: false, vertical: true)
                } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                    let done = !line.hasPrefix("- [ ] ")
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(EmberColor.borderStrong, lineWidth: 1.5)
                            .background(done ? EmberColor.accent.opacity(0.25) : .clear)
                            .frame(width: 16, height: 16).padding(.top, 1)
                        Text(Self.inline(String(line.dropFirst(6)))).font(EmberType.regular(13.5)).foregroundStyle(EmberColor.text2)
                        Spacer(minLength: 0)
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 10) {
                        Text("—").font(EmberType.regular(13.5)).foregroundStyle(EmberColor.accentText)
                        Text(Self.inline(String(line.dropFirst(2)))).font(EmberType.regular(13.5)).lineSpacing(2).foregroundStyle(EmberColor.text2)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text(Self.inline(line)).font(EmberType.regular(13.5)).lineSpacing(3).foregroundStyle(EmberColor.text2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Emoji + accent colour for an Obsidian callout type.
    private static func calloutMeta(_ type: String) -> (emoji: String, color: Color) {
        switch type {
        case "tip": ("💡", EmberColor.accentText)
        case "success": ("✅", EmberColor.good)
        case "todo": ("☑️", EmberColor.accentText)
        case "info": ("ℹ️", EmberColor.text2)
        case "question": ("❓", EmberColor.warn)
        case "warning", "danger", "bug", "caution": ("⚠️", EmberColor.rec)
        default: ("📝", EmberColor.text2)
        }
    }

    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

/// Small rotating spinner.
struct Spinner: View {
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(EmberColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}
