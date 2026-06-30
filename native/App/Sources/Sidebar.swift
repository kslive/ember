import Core
import DesignSystem
import SwiftUI

struct Sidebar: View {
    @EnvironmentObject private var locale: LocaleManager
    @Binding var route: AppRoute
    @Binding var selectedMeetingId: String?
    let meetings: [Meeting]
    var width: CGFloat = 266
    var isRecording: Bool = false
    var recordingElapsed: TimeInterval = 0
    var onTapRecording: () -> Void = {}
    var onRename: (Meeting) -> Void = { _ in }
    var onDelete: (Meeting) -> Void = { _ in }
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            logo
            searchField
            nav
            if isRecording, route != .home { recordingIndicator }
            ScrollView {
                meetingsSection.padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.top, 44)
        .padding(.bottom, 16)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(EmberColor.bg)
        .background(focusSearchShortcut)
    }

    /// ⌘F focuses the meeting search field.
    private var focusSearchShortcut: some View {
        Button("") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private var logo: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(EmberColor.accent)
                .frame(width: 9, height: 9)
                .haloPulse(color: EmberColor.accent, maxScale: 2.6)
                .shadow(color: EmberColor.accent.opacity(0.7), radius: 5)
            Text("ember")
                .font(EmberType.medium(17))
                .tracking(-0.17)
                .foregroundStyle(EmberColor.text)
        }
        .padding(.horizontal, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            EmberIcon(.search, size: 15, lineWidth: 2, color: EmberColor.text3)
            TextField(locale.t("sidebar.search"), text: $query)
                .textFieldStyle(.plain)
                .font(EmberType.regular(13.5))
                .foregroundStyle(EmberColor.text)
                .focused($searchFocused)
                .onKeyPress(.escape) { query = ""; searchFocused = false; return .handled }
            if !query.isEmpty {
                Button { query = "" } label: {
                    EmberIcon(.close, size: 13, lineWidth: 2, color: EmberColor.text3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).hoverCursor()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(EmberColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    /// Shown while recording and the user has navigated away from Home — taps back to the live view.
    private var recordingIndicator: some View {
        Button(action: onTapRecording) {
            RecordingBadge(label: locale.t("recording.status"), timecode: Format.timecode(recordingElapsed))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverCursor()
        .padding(.horizontal, 4)
    }

    private var nav: some View {
        VStack(spacing: 3) {
            navItem(.home, .home, locale.t("nav.home"))
            navItem(.settings, .settings, locale.t("nav.settings"))
        }
    }

    private func navItem(_ target: AppRoute, _ glyph: EmberIcon.Glyph, _ title: String) -> some View {
        let active = route == target
        return Button { route = target } label: {
            HStack(spacing: 11) {
                EmberIcon(glyph, size: 17, lineWidth: 1.8, color: active ? EmberColor.accentText : EmberColor.text2)
                Text(title)
                    .font(active ? EmberType.medium(14) : EmberType.regular(14))
                    .foregroundStyle(active ? EmberColor.accentText : EmberColor.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(active ? EmberColor.accentWeak : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .emberHover(cornerRadius: 10)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder private var meetingsSection: some View {
        let groups = groups
        if groups.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(locale.t("sidebar.meetings"))
                    .font(EmberType.mono(10.5)).tracking(1.05).textCase(.uppercase)
                    .foregroundStyle(EmberColor.text3)
                VStack(spacing: 2) {
                    if isSearching {
                        Text(locale.t("sidebar.noResults"))
                    } else {
                        Text(locale.t("sidebar.empty1"))
                        Text(locale.t("sidebar.empty2"))
                    }
                }
                .font(EmberType.regular(13))
                .foregroundStyle(EmberColor.text3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 22)
                .padding(.horizontal, 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(EmberColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
            }
            .padding(.horizontal, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(groups, id: \.label) { g in
                    HStack {
                        Text(g.label)
                            .font(EmberType.mono(10.5)).tracking(1.05).textCase(.uppercase)
                        Spacer()
                        Text("\(g.count)")
                            .font(EmberType.mono(10.5))
                    }
                    .foregroundStyle(EmberColor.text3)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    ForEach(g.items) { meetingRow($0) }
                }
            }
        }
    }

    private func meetingRow(_ m: Meeting) -> some View {
        let sel = selectedMeetingId == m.id && route == .meetings
        return Button {
            selectedMeetingId = m.id
            route = .meetings
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Format.clock(m.createdAt, language: locale.language)) — \(m.title)")
                    .font(sel ? EmberType.medium(13.5) : EmberType.regular(13.5))
                    .foregroundStyle(sel ? EmberColor.accentText : EmberColor.text)
                    .lineLimit(1)
                if let d = m.durationSeconds, d > 0 {
                    Text(Format.duration(d, language: locale.language))
                        .font(EmberType.mono(11))
                        .foregroundStyle(EmberColor.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(sel ? EmberColor.accentWeak : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .emberHover(cornerRadius: 9)
        .contextMenu {
            Button(locale.t("ctx.rename")) { onRename(m) }
            Button(locale.t("ctx.delete"), role: .destructive) { onDelete(m) }
        }
    }

    private struct Group { let label: String; let count: Int; let items: [Meeting] }

    private var groups: [Group] {
        let filtered = MeetingSearch.filter(meetings, query: query, language: locale.language)
        let sorted = filtered.sorted { $0.createdAt > $1.createdAt }
        var order: [DateGroup] = []
        var map: [DateGroup: [Meeting]] = [:]
        for m in sorted {
            let g = DateGroup.of(m.createdAt)
            if map[g] == nil { order.append(g); map[g] = [] }
            map[g, default: []].append(m)
        }
        return order.map { Group(label: label(for: $0), count: map[$0]?.count ?? 0, items: map[$0] ?? []) }
    }

    private func label(for g: DateGroup) -> String {
        switch g {
        case .today: return locale.t("sidebar.today")
        case .yesterday: return locale.t("sidebar.yesterday")
        case let .day(d):
            let sameYear = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
            let fmt = locale.language == .zh ? (sameYear ? "M月d日" : "yyyy年M月d日")
                : (sameYear ? "d MMM" : "d MMM yyyy")
            return Format.date(d, format: fmt, language: locale.language)
        }
    }
}
