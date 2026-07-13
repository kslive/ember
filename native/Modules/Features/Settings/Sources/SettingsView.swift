import AppKit
import Core
import DesignSystem
import SummaryService
import SwiftUI
import TranscriptionService
import UpdaterService

public struct SettingsView: View {
    @EnvironmentObject private var locale: LocaleManager
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var updater: UpdaterService
    @ObservedObject private var transcription: TranscriptionService
    @ObservedObject private var summary: SummaryService
    @State private var tab: Tab = .general
    @State private var pendingDelete: PendingModelDelete?
    @State private var deepseekDraft = ""
    @State private var deepseekModels: [String] = []
    @State private var deepseekChecking = false
    @State private var deepseekError: String?
    @State private var deepseekHasKey = false
    @State private var deepseekListFailed = false
    @StateObject private var devices = AudioDevicesModel()
    @Namespace private var tabNS
    @Namespace private var segNS

    /// A downloaded model queued for deletion (confirm dialog payload).
    private struct PendingModelDelete {
        let name: String
        let size: String
        let isWhisper: Bool
        let id: String
        let repoId: String
    }

    enum Tab: String, CaseIterable {
        case general, recording, transcription, summary, updates
        var key: String {
            "settings.tab.\(rawValue)"
        }

        var glyph: EmberIcon.Glyph {
            switch self {
            case .general: .settings
            case .recording: .mic
            case .transcription: .waves
            case .summary: .sparkle
            case .updates: .download
            }
        }
    }

    public init(transcription: TranscriptionService, summary: SummaryService) {
        self.transcription = transcription
        self.summary = summary
    }

    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(locale.t("settings.title"))
                        .font(EmberType.semibold(26)).tracking(-0.52)
                        .foregroundStyle(EmberColor.text)
                    tabBar
                }
                .padding(.horizontal, 36)
                .padding(.top, 40)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 20)
                }
                .scrollIndicators(.never)
            }
            if let pd = pendingDelete {
                EmberDialog(tone: .danger, title: locale.t("dialog.deleteModel.title"),
                            message: locale.t("dialog.deleteModel.msg", ["name": pd.name, "size": pd.size]),
                            confirmLabel: locale.t("common.delete"), cancelLabel: locale.t("common.cancel"),
                            onConfirm: { confirmModelDelete(pd) }, onCancel: { pendingDelete = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EmberColor.bg)
    }

    /// Deletes the model from disk; a deleted SELECTED model falls back to the
    /// catalog default so the pipeline never silently re-downloads the deleted one.
    private func confirmModelDelete(_ pd: PendingModelDelete) {
        pendingDelete = nil
        if pd.isWhisper {
            transcription.delete(pd.id)
            if settings.whisperModelId == pd.id { settings.whisperModelId = TranscriptionCatalog.defaultId }
        } else {
            summary.delete(id: pd.id, repoId: pd.repoId)
            if settings.summaryModelId == pd.id { settings.summaryModelId = SummaryCatalog.defaultId }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = t }
                } label: {
                    HStack(spacing: 7) {
                        EmberIcon(t.glyph, size: 14, lineWidth: 1.8,
                                  color: tab == t ? EmberColor.text : EmberColor.text2)
                        Text(locale.t(t.key)).font(EmberType.medium(13.5))
                            .foregroundStyle(tab == t ? EmberColor.text : EmberColor.text2)
                    }
                    .padding(.horizontal, 15).frame(height: 34)
                    .background {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 8).fill(EmberColor.surface2)
                                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                                .matchedGeometryEffect(id: "tabIndicator", in: tabNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverCursor()
            }
        }
        .padding(4)
        .background(EmberColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general: generalTab
        case .recording: recordingTab
        case .transcription: modelsTab(transcription: true)
        case .summary: modelsTab(transcription: false)
        case .updates: updatesTab
        }
    }

    @ViewBuilder private var generalTab: some View {
        segmentCard(locale.t("settings.theme"), locale.t("settings.theme.desc")) { themeSegmented }
        segmentCard(locale.t("settings.accent"), locale.t("settings.accent.desc")) { accentSwatches }
        segmentCard(locale.t("settings.language"), locale.t("settings.language.desc")) { languageSegmented }
        settingRow(locale.t("settings.notifications"), locale.t("settings.notifications.desc")) {
            EmberToggle(isOn: $settings.notificationsEnabled)
        }
        pathCard(locale.t("settings.exportFolder"), locale.t("settings.exportFolder.desc"),
                 path: settings.exportFolderPath, actionTitle: locale.t("common.choose"),
                 glyph: .file) { chooseExportFolder() }
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(locale.t("settings.dataLocation")).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                pathField(locale.t("settings.dataFolder"), dataPath,
                          actionTitle: locale.t("common.open"), glyph: .file) { openDataFolder() }
            }
        }
    }

    /// Accent swatch row (Sage-style): tap a circle to recolor the whole app.
    private var accentSwatches: some View {
        HStack(spacing: 11) {
            ForEach(AccentPreset.all) { preset in
                Circle()
                    .fill(Color(hex: preset.base))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .strokeBorder(EmberColor.text, lineWidth: theme.accentId == preset.id ? 2 : 0)
                            .padding(-4)
                    )
                    .padding(4)
                    .contentShape(Circle())
                    .onTapGesture { theme.setAccent(preset) }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: theme.accentId)
    }

    /// Card with a title, description and a segmented control underneath (mockup S1).
    private func segmentCard(_ title: String, _ desc: String, @ViewBuilder _ control: () -> some View) -> some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                Text(desc).font(EmberType.regular(13)).foregroundStyle(EmberColor.text2)
                    .padding(.top, 4).padding(.bottom, 16)
                control()
            }
        }
    }

    @ViewBuilder private var recordingTab: some View {
        settingRow(locale.t("settings.recording.notifyOnStart"), locale.t("settings.recording.notifyOnStart.desc")) {
            EmberToggle(isOn: $settings.notifyOnStart)
        }
        settingRow(locale.t("settings.recording.diarization"), locale.t("settings.recording.diarization.desc")) {
            EmberToggle(isOn: $settings.diarizationEnabled)
        }
        card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(locale.t("settings.recording.devices")).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                    Text(locale.t("settings.recording.devices.desc")).font(EmberType.regular(13)).foregroundStyle(EmberColor.text2)
                }
                HStack(alignment: .top, spacing: 16) {
                    DeviceSelectField(caption: locale.t("settings.recording.microphone"), defaultLabel: locale.t("settings.recording.micDefault"),
                                      devices: devices.inputs, selectedUID: settings.preferredMicUID) { settings.preferredMicUID = $0 }
                    DeviceSelectField(caption: locale.t("settings.recording.systemAudio"), defaultLabel: locale.t("settings.recording.systemDefault"),
                                      devices: devices.outputs, selectedUID: settings.preferredSystemUID) { settings.preferredSystemUID = $0 }
                }
                VStack(alignment: .leading, spacing: 5) {
                    note(locale.t("settings.recording.micNote"))
                    note(locale.t("settings.recording.sysNote"))
                }.padding(.top, 2)
            }
        }
    }

    @ViewBuilder private func modelsTab(transcription isWhisper: Bool) -> some View {
        if !isWhisper {
            settingRow(locale.t("settings.autoSummary"), locale.t("settings.autoSummary.desc")) {
                EmberToggle(isOn: $settings.autoSummary)
            }
        }
        sectionTitle(locale.t(isWhisper ? "settings.transcription.title" : "settings.summary.title"))
        if isWhisper {
            ForEach(TranscriptionCatalog.all) { m in
                VStack(alignment: .trailing, spacing: 4) {
                    EmberModelCard(name: m.displayName,
                                   desc: m.engine == .gigaAM ? locale.t("model.gigaam.desc") : locale.t("model.ramHint", ["g": "2"]),
                                   meta: "\(m.sizeMB) \(sizeUnit)",
                                   badge: badgeText(m.badge),
                                   state: whisperState(m.id), totalMB: m.sizeMB, errorText: whisperError(m.id),
                                   onAction: { whisperAction(m.id) })
                    if isDeletable(whisperState(m.id)) {
                        deleteLink(PendingModelDelete(name: m.displayName, size: "\(m.sizeMB) \(sizeUnit)",
                                                      isWhisper: true, id: m.id, repoId: ""))
                    }
                }
            }
        } else {
            ForEach(SummaryCatalog.all) { m in
                VStack(alignment: .trailing, spacing: 4) {
                    EmberModelCard(name: m.displayName, desc: locale.t("model.ramHint", ["g": "\(m.ramHintGB)"]),
                                   meta: "\(m.sizeMB) \(sizeUnit) · \(m.contextTokens) \(locale.t("model.tokens"))",
                                   badge: badgeText(m.badge),
                                   state: summaryState(m.id), totalMB: m.sizeMB, errorText: summaryError(m.id),
                                   onAction: { summaryAction(m.id) })
                    if isDeletable(summaryState(m.id)) {
                        deleteLink(PendingModelDelete(name: m.displayName, size: "\(m.sizeMB) \(sizeUnit)",
                                                      isWhisper: false, id: m.id, repoId: m.repoId))
                    }
                }
            }
            deepseekSection
        }
    }

    /// Optional DeepSeek cloud path: key lives in the Keychain; the model is picked
    /// from GET /models for THIS key (ids are never hardcoded — DeepSeek renames them).
    /// Local models remain the always-available fallback.
    @ViewBuilder private var deepseekSection: some View {
        sectionTitle(locale.t("settings.deepseek.title"))
        card {
            VStack(alignment: .leading, spacing: 12) {
                if deepseekHasKey {
                    HStack(spacing: 10) {
                        Text("••••••••")
                            .font(EmberType.mono(13)).foregroundStyle(EmberColor.text2)
                        Text(locale.t("settings.deepseek.valid"))
                            .font(EmberType.regular(12.5)).foregroundStyle(EmberColor.good)
                        Spacer()
                        EmberButton(locale.t("settings.deepseek.delete"), kind: .secondary, height: 30) {
                            SettingsStore.deleteDeepseekKey()
                            settings.deepseekModel = ""
                            deepseekHasKey = false
                            deepseekModels = []
                            deepseekError = nil
                            deepseekListFailed = false
                        }
                    }
                    if !deepseekModels.isEmpty {
                        HStack(spacing: 10) {
                            Text(locale.t("settings.deepseek.model"))
                                .font(EmberType.regular(13)).foregroundStyle(EmberColor.text2)
                            Menu {
                                ForEach(deepseekModels, id: \.self) { m in
                                    Button(m) { settings.deepseekModel = m }
                                }
                            } label: {
                                Text(settings.deepseekModel.isEmpty ? (deepseekModels.first ?? "—") : settings.deepseekModel)
                                    .font(EmberType.mono(12.5)).foregroundStyle(EmberColor.text)
                            }
                            .menuStyle(.borderlessButton).fixedSize()
                            .hoverCursor()
                        }
                    } else if deepseekListFailed {
                        Text(locale.t("settings.deepseek.unavailable"))
                            .font(EmberType.regular(12.5)).foregroundStyle(EmberColor.warn)
                    }
                } else {
                    HStack(spacing: 10) {
                        SecureField(locale.t("settings.deepseek.placeholder"), text: $deepseekDraft)
                            .textFieldStyle(.plain)
                            .font(EmberType.mono(13)).foregroundStyle(EmberColor.text)
                            .padding(.horizontal, 12).frame(height: 36).frame(maxWidth: .infinity)
                            .background(EmberColor.surface)
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(EmberColor.borderStrong, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        EmberButton(deepseekChecking ? locale.t("settings.deepseek.checking") : locale.t("settings.deepseek.save"),
                                    kind: .primary, height: 36) {
                            saveDeepseekKey()
                        }
                        .disabled(deepseekChecking || deepseekDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let err = deepseekError {
                        Text(err).font(EmberType.regular(12.5)).foregroundStyle(EmberColor.rec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                note(locale.t("settings.deepseek.desc"))
            }
        }
        .onAppear { refreshDeepseek() }
    }

    /// Validates the key by fetching ITS model list; only a working key is stored.
    private func saveDeepseekKey() {
        let key = deepseekDraft.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !deepseekChecking else { return }
        deepseekChecking = true
        deepseekError = nil
        Task { @MainActor in
            defer { deepseekChecking = false }
            do {
                let models = try await DeepSeekClient.listModels(key: key)
                SettingsStore.setDeepseekKey(key)
                settings.deepseekModel = models.first ?? ""
                deepseekModels = models
                deepseekHasKey = true
                deepseekDraft = ""
                deepseekListFailed = false
            } catch {
                deepseekError = locale.t("settings.deepseek.invalid")
            }
        }
    }

    private func refreshDeepseek() {
        deepseekHasKey = SettingsStore.deepseekKey() != nil
        guard deepseekHasKey, let key = SettingsStore.deepseekKey() else { return }
        Task { @MainActor in
            do {
                deepseekModels = try await DeepSeekClient.listModels(key: key)
                deepseekListFailed = false
            } catch {
                deepseekModels = []
                deepseekListFailed = true
            }
        }
    }

    private func isDeletable(_ s: ModelCardState) -> Bool {
        switch s {
        case .ready, .selected: true
        default: false
        }
    }

    /// Small trailing "Delete" link under a downloaded model card.
    private func deleteLink(_ pd: PendingModelDelete) -> some View {
        Button {
            pendingDelete = pd
        } label: {
            Text(locale.t("settings.model.delete"))
                .font(EmberType.regular(12))
                .foregroundStyle(EmberColor.text3)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmberPressStyle())
        .hoverCursor()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private var updatesTab: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(updateTitle).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                    Text("\(locale.t("settings.version")) \(appVersion)").font(EmberType.mono(12)).foregroundStyle(EmberColor.text3)
                }
                Spacer()
                updateAction
            }
        }
        card {
            HStack {
                Text(locale.t("settings.autoUpdate")).font(EmberType.regular(14)).foregroundStyle(EmberColor.text)
                Spacer()
                EmberToggle(isOn: $updater.autoUpdate)
            }
        }
    }

    private var updateTitle: String {
        switch updater.phase {
        case .checking: locale.t("update.checking")
        case let .available(r): locale.t("update.available", ["v": r.version])
        case let .downloading(p): locale.t("update.downloading", ["p": String(Int(p * 100))])
        case .installing: locale.t("update.downloading", ["p": "100"])
        case let .readyToInstall(r): locale.t("update.readyToInstall", ["v": r.version])
        case let .failed(m): m
        case .idle, .upToDate: locale.t("settings.upToDate")
        }
    }

    @ViewBuilder private var updateAction: some View {
        switch updater.phase {
        case .available:
            EmberButton(locale.t("update.download"), kind: .primary, height: 34) { updater.update() }
        case .readyToInstall:
            EmberButton(locale.t("update.restart"), kind: .primary, height: 34) { updater.restart() }
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .idle, .upToDate, .failed:
            EmberButton(locale.t("settings.checkUpdates"), kind: .secondary, height: 34) { updater.checkNow() }
        }
    }

    private var themeSegmented: some View {
        segmented([
            SegItem(label: locale.t("settings.theme.light"), symbol: "sun.max", active: theme.theme == .light) { theme.setTheme(.light) },
            SegItem(label: locale.t("settings.theme.dark"), symbol: "moon", active: theme.theme == .dark) { theme.setTheme(.dark) },
            SegItem(label: locale.t("settings.theme.auto"), symbol: "laptopcomputer", active: theme.theme == .auto) { theme.setTheme(.auto) }
        ], group: "seg-theme")
    }

    private var languageSegmented: some View {
        segmented(AppLanguage.allCases.map { lang in
            SegItem(label: lang.nativeName, flag: lang.flag, active: locale.language == lang) { locale.setLanguage(lang) }
        }, group: "seg-lang")
    }

    private struct SegItem: Identifiable {
        let id = UUID()
        let label: String
        var symbol: String?
        var flag: String?
        let active: Bool
        let action: () -> Void
    }

    /// Inset segmented control: dark track, elevated neutral pill for the active item
    /// (matches the mockup's theme/language selectors).
    private func segmented(_ items: [SegItem], group: String) -> some View {
        HStack(spacing: 3) {
            ForEach(items) { it in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { it.action() }
                } label: {
                    HStack(spacing: 7) {
                        if let f = it.flag { Text(f).font(.system(size: 14)) }
                        if let s = it.symbol { Image(systemName: s).font(.system(size: 12.5, weight: .medium)) }
                        Text(it.label).font(EmberType.medium(13.5))
                    }
                    .foregroundStyle(it.active ? EmberColor.text : EmberColor.text2)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background {
                        if it.active {
                            RoundedRectangle(cornerRadius: 8).fill(EmberColor.surface2)
                                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                                .matchedGeometryEffect(id: group, in: segNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverCursor()
            }
        }
        .padding(4)
        .background(EmberColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    /// A custom device selector. NOT a `Menu` — `.menuStyle(.borderlessButton)` strips
    /// a styled label down to plain text on macOS. A plain `Button` renders its custom
    /// label reliably (like every other button in the app) and a `.popover` shows the
    /// device list, so we control rendering AND the click fully.
    struct DeviceSelectField: View {
        let caption: String
        let defaultLabel: String
        let devices: [AudioDeviceInfo]
        let selectedUID: String
        let onSelect: (String) -> Void
        @State private var open = false

        private var current: String {
            devices.first { $0.uid == selectedUID }?.name ?? defaultLabel
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(caption).font(EmberType.mono(10.5)).tracking(0.63).textCase(.uppercase).foregroundStyle(EmberColor.text3)
                Button { open.toggle() } label: {
                    HStack(spacing: 12) {
                        Text(current).font(EmberType.regular(13.5)).foregroundStyle(EmberColor.text).lineLimit(1)
                        Spacer(minLength: 8)
                        EmberIcon(.chevronRight, size: 14, lineWidth: 2, color: EmberColor.text3)
                            .rotationEffect(.degrees(90))
                    }
                    .padding(.horizontal, 14).frame(height: 40).frame(maxWidth: .infinity)
                    .background(EmberColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(EmberColor.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverCursor()
                .popover(isPresented: $open, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            optionRow(defaultLabel, uid: "")
                            if !devices.isEmpty { Divider().overlay(EmberColor.border) }
                            ForEach(devices) { d in optionRow(d.name, uid: d.uid) }
                        }
                        .padding(6)
                    }
                    .frame(width: 280)
                    .frame(maxHeight: 320)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func optionRow(_ name: String, uid: String) -> some View {
            Button { onSelect(uid); open = false } label: {
                HStack(spacing: 8) {
                    Text(name).font(EmberType.regular(13)).foregroundStyle(EmberColor.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if uid == selectedUID {
                        EmberIcon(.check, size: 13, lineWidth: 2, color: EmberColor.accent)
                    }
                }
                .padding(.horizontal, 10).frame(height: 32).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverCursor()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(EmberType.regular(12.5)).foregroundStyle(EmberColor.text2).fixedSize(horizontal: false, vertical: true)
    }

    private func whisperError(_ id: String) -> String? {
        if case let .failed(m) = (transcription.states[id] ?? .absent) { return m.isEmpty ? nil : m }
        return nil
    }

    private func summaryError(_ id: String) -> String? {
        if case let .failed(m) = (summary.states[id] ?? .absent) { return m.isEmpty ? nil : m }
        return nil
    }

    private func whisperState(_ id: String) -> ModelCardState {
        ModelCardState.from(transcription.states[id] ?? .absent, selected: id == settings.whisperModelId)
    }

    private func whisperAction(_ id: String) {
        switch transcription.states[id] ?? .absent {
        case .ready: settings.whisperModelId = id
        case .absent, .failed:
            settings.whisperModelId = id
            transcription.startDownload(id)
        case .downloading: transcription.cancelDownload(id)
        }
    }

    private func summaryState(_ id: String) -> ModelCardState {
        ModelCardState.from(summary.states[id] ?? .absent, selected: id == settings.summaryModelId)
    }

    private func summaryAction(_ id: String) {
        switch summary.states[id] ?? .absent {
        case .ready: settings.summaryModelId = id
        case .absent, .failed:
            settings.summaryModelId = id
            if let repo = SummaryCatalog.spec(for: id)?.repoId { summary.startDownload(id: id, repoId: repo) }
        case .downloading:
            if let repo = SummaryCatalog.spec(for: id)?.repoId { summary.cancelDownload(id: id, repoId: repo) }
        }
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = locale.t("common.choose")
        if panel.runModal() == .OK, let url = panel.url { settings.exportFolderPath = url.path }
    }

    /// The data folder holding `ember.sqlite` (saved transcriptions + summaries) — NOT audio.
    private var dataPath: String {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Ember").path
    }

    private func openDataFolder() {
        let url = URL(fileURLWithPath: dataPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let db = url.appendingPathComponent("ember.sqlite")
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: db.path) ? db : url])
    }

    private func settingRow(_ title: String, _ desc: String? = nil, glyph: EmberIcon.Glyph? = nil,
                            @ViewBuilder trailing: () -> some View) -> some View {
        card {
            HStack(alignment: .center, spacing: 16) {
                if let glyph { EmberIcon(glyph, size: 16, lineWidth: 1.8, color: EmberColor.text2) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                    if let desc { Text(desc).font(EmberType.regular(13)).foregroundStyle(EmberColor.text2) }
                }
                Spacer(minLength: 12)
                trailing()
            }
        }
    }

    private func pathCard(_ title: String, _ desc: String, path: String, actionTitle: String,
                          glyph: EmberIcon.Glyph, action: @escaping () -> Void) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(EmberType.semibold(15)).foregroundStyle(EmberColor.text)
                    Text(desc).font(EmberType.regular(13)).foregroundStyle(EmberColor.text2)
                }
                pathField("", path, actionTitle: actionTitle, glyph: glyph, action: action)
            }
        }
    }

    private func pathField(_ label: String, _ path: String, actionTitle: String,
                           glyph _: EmberIcon.Glyph, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !label.isEmpty {
                Text(label).font(EmberType.mono(10.5)).tracking(0.63).textCase(.uppercase).foregroundStyle(EmberColor.text3)
            }
            HStack(spacing: 10) {
                Text(path).font(EmberType.mono(12)).foregroundStyle(EmberColor.text2).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(EmberColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(EmberColor.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                EmberButton(actionTitle, kind: .secondary, height: 44, action: action)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(EmberType.mono(10.5)).tracking(0.63).textCase(.uppercase)
            .foregroundStyle(EmberColor.text3)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmberColor.surface2)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(EmberColor.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sizeUnit: String {
        locale.language == .ru ? "МБ" : "MB"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }

    private func badgeText(_ b: ModelBadge?) -> String? {
        guard let b else { return nil }
        return locale.t(b == .recommended ? "model.badge.recommended" : "model.badge.balanced")
    }
}
