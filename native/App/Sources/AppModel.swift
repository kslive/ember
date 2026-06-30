import AudioService
import CallDetectService
import Combine
import Core
import PersistenceService
import SummaryService
import SwiftUI
import TranscriptionService
import UserNotifications

enum AppRoute: Hashable {
    case home
    case meetings
    case settings
}

/// Composition root: owns the services and drives the record → transcribe →
/// summarize → save pipeline.
@MainActor
final class AppModel: ObservableObject {
    let store = MeetingStore()
    let engine = RecordingEngine()
    let transcription = TranscriptionService()
    let summary = SummaryService()
    let callDetect = CallDetectService()
    private var autoStarted = false

    @Published var route: AppRoute = .home
    @Published var selectedMeetingId: String?
    @Published var renaming: Meeting?
    @Published var deleting: Meeting?
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var toast: ToastInfo?
    private var toastTask: Task<Void, Never>?
    @Published private(set) var processingIds: Set<String> = []
    @Published private(set) var revision = 0

    private var recordingId: String?
    private var isStarting = false
    private var isSummarizing = false
    private var liveTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        for obj in [store.objectWillChange, engine.objectWillChange,
                    transcription.objectWillChange, summary.objectWillChange] {
            obj.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        callDetect.onCallStart = { [weak self] in self?.autoStartFromCall() }
        callDetect.onCallEnd = { [weak self] in self?.autoStopFromCall() }
        callDetect.start()
        RecordingEngine.purgeRecordings()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if !UserDefaults.standard.bool(forKey: "ember.purgedDemo") {
            UserDefaults.standard.set(true, forKey: "ember.purgedDemo")
            store.purgeDemo()
        }
        if store.persistenceDegraded { showToast(tr("toast.persistenceDegraded"), tone: .error) }
    }

    private func notify(_ en: String, _ ru: String, _ zh: String) {
        guard SettingsStore.notificationsOn() else { return }
        let body: String = switch AppLanguage.current {
        case .ru: ru
        case .zh: zh
        case .en: en
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            func post() {
                let content = UNMutableNotificationContent()
                content.title = "Ember"
                content.body = body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
            switch s.authorizationStatus {
            case .authorized, .provisional: post()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { ok, _ in if ok { post() } }
            default: break
            }
        }
    }

    /// Localized lookup for in-app toast strings (canonical impl lives in LocalizedStrings).
    private func tr(_ key: String) -> String {
        LocalizedStrings.current(key)
    }

    /// Shows a transient in-app toast (auto-dismisses).
    func showToast(_ text: String, tone: ToastInfo.Tone = .info) {
        toast = ToastInfo(text, tone: tone)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    private func autoStartFromCall() {
        guard !isRecordingActive else { return }
        autoStarted = true
        startRecording()
    }

    private func autoStopFromCall() {
        guard isRecordingActive, autoStarted else { return }
        stopRecording(language: .current)
    }

    var isRecordingActive: Bool {
        engine.status == .recording || engine.status == .paused || engine.status == .starting
    }

    func startRecording() {
        guard !isStarting, !isRecordingActive else { return }
        route = .home
        isStarting = true
        Task {
            defer { isStarting = false }
            guard await RecordingEngine.requestMicPermission() else {
                showToast(tr("toast.micDenied"), tone: .error)
                return
            }
            let id = UUID().uuidString
            recordingId = id
            do {
                try engine.start(meetingId: id)
            } catch {
                recordingId = nil
                showToast(tr("toast.recFailed"), tone: .error)
                return
            }
            startLiveLoop(id)
            notify("Recording started", "Запись началась", "开始录音")
            if SettingsStore.notifyOnStartOn() { showToast(tr("toast.recReminder"), tone: .warn) } else { showToast(tr("toast.recStarted"), tone: .info) }
        }
    }

    /// Incrementally transcribes new mic audio (~2s chunks) for a live transcript.
    /// Reads only the delta since the last chunk (no re-transcription → no dupes,
    /// bounded cost), offsets timecodes onto the full timeline, and appends.
    /// Growing-window live transcription (WhisperAX pattern): re-transcribe the
    /// tail since the last *confirmed* segment so Whisper always has context
    /// (a 2s isolated clip gets padded to 30s of silence → predicts nothing).
    /// Older segments are confirmed (locked); the last is a live hypothesis.
    private struct LiveState { var confirmed: [TranscriptSegment] = []; var confirmedSamples = 0; var live: [TranscriptSegment] = [] }

    /// Skip transcription only when a window/recording is TRULY silent. Gate on PEAK
    /// (max |sample|), NOT mean RMS: real speech mixed with pauses has a low average
    /// RMS but clear peaks, so an RMS gate wrongly dropped the quiet-but-real mic
    /// channel (the user spoke yet only [mac] appeared). Speech peaks ≫ 0.02; a silent
    /// tap's noise floor peaks ≪ 0.02.
    private static let silencePeak: Float = 0.02

    private func startLiveLoop(_ meetingId: String) {
        liveSegments = []
        liveTask?.cancel()
        liveTask = Task { [weak self] in
            guard let self else { return }
            await transcription.ensureLoaded(model: SettingsStore.currentWhisperModelId())
            var mic = LiveState(), sys = LiveState()
            while !Task.isCancelled, isRecordingActive {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard !Task.isCancelled, engine.status == .recording, transcription.isReady else { continue }
                mic = await advanceLive(mic, meetingId: meetingId, source: .mic,
                                        total: engine.liveMicCount(),
                                        tailFrom: { self.engine.liveMicSlice(from: $0) })
                sys = await advanceLive(sys, meetingId: meetingId, source: .system,
                                        total: engine.liveSystemCount(),
                                        tailFrom: { self.engine.liveSystemSlice(from: $0) })
                if Task.isCancelled { break }
                liveSegments = TranscriptMerge.interleave(mic: mic.live, system: sys.live)
            }
        }
    }

    /// Folds a freshly-transcribed tail of ONE source into its growing-window state.
    /// `tailFrom` is evaluated lazily — only after the cheap sample-count gate passes —
    /// so a silent/short 1.8s tick doesn't copy the accumulator off the realtime thread.
    private func advanceLive(_ state: LiveState, meetingId: String, source: TranscriptSource,
                             total: Int, tailFrom: (Int) -> [Float]) async -> LiveState {
        var s = state
        guard total - s.confirmedSamples > 16000 else { return s }
        let tail = tailFrom(s.confirmedSamples)
        guard AudioLevel.peak(tail) > Self.silencePeak else { return s }
        let base = Double(s.confirmedSamples) / 16000.0
        let segs = await transcription.transcribeSamples(tail, meetingId: meetingId, language: whisperLang())
        guard !segs.isEmpty else { return s }
        let adjusted = segs.map {
            TranscriptSegment(meetingId: meetingId, text: $0.text,
                              startSeconds: $0.startSeconds + base, endSeconds: $0.endSeconds + base, source: source)
        }
        let merged = LiveMerge.apply(confirmed: s.confirmed, fresh: adjusted,
                                     confirmedSamples: s.confirmedSamples, totalSamples: total)
        if total - s.confirmedSamples > 480_000 {
            s.confirmed = merged.live; s.confirmedSamples = total; s.live = merged.live
        } else {
            s.confirmed = merged.confirmed; s.confirmedSamples = merged.confirmedSamples; s.live = merged.live
        }
        return s
    }

    /// The user-selected language (sidebar/header chip) drives transcription —
    /// otherwise Whisper auto-detects and often translates Russian → English.
    private func whisperLang() -> String {
        AppLanguage.current.rawValue
    }

    func stopRecording(language: AppLanguage) {
        let live = liveTask
        liveTask?.cancel()
        liveTask = nil
        liveSegments = []
        let (mic, system) = engine.stop()
        let micSamples = engine.liveSamples()
        let systemSamples = engine.systemSamples()
        let id = recordingId ?? UUID().uuidString
        let meeting = Meeting(id: id, title: defaultTitle(language), createdAt: Date(), durationSeconds: engine.elapsed)
        store.upsert(meeting)
        engine.reset()
        recordingId = nil
        autoStarted = false
        route = .home
        guard mic != nil || system != nil else { return }
        processingIds.insert(id)
        notify("Recording stopped — processing…", "Запись остановлена — обработка…", "录音已停止——处理中…")
        showToast(tr("toast.recStopped"), tone: .info)
        Task { await live?.value; await process(meetingId: id, micSamples: micSamples, systemSamples: systemSamples, mic: mic, system: system) }
    }

    private func process(meetingId id: String, micSamples: [Float], systemSamples: [Float], mic: URL?, system: URL?) async {
        defer { processingIds.remove(id); revision += 1 }
        await transcription.ensureLoaded(model: SettingsStore.currentWhisperModelId())
        let lang = whisperLang()
        let micGated = !micSamples.isEmpty && AudioLevel.peak(micSamples) >= Self.silencePeak
        let sysGated = !systemSamples.isEmpty && AudioLevel.peak(systemSamples) >= Self.silencePeak
        async let micRaw: [TranscriptSegment] = micGated
            ? transcription.transcribeSamples(micSamples, meetingId: id, language: lang, strict: true) : []
        async let sysRaw: [TranscriptSegment] = sysGated
            ? transcription.transcribeSamples(systemSamples, meetingId: id, language: lang, strict: true) : []
        let micSegs = await (micRaw).map { tag($0, .mic) }
        let sysSegs = await (sysRaw).map { tag($0, .system) }
        var segs = TranscriptMerge.merge(mic: micSegs, system: sysSegs)
        if segs.isEmpty {
            let mixedURL = RecordingEngine.recordingsDir().appendingPathComponent("\(id).m4a")
            if let audioURL = await AudioMixer.mix(mic: mic, system: system, output: mixedURL) ?? mic ?? system {
                segs = await transcription.transcribe(url: audioURL, meetingId: id, language: lang, strict: false)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        store.saveTranscript(meetingId: id, segments: segs)
        revision += 1
        if let mic { try? FileManager.default.removeItem(at: mic) }
        if let system { try? FileManager.default.removeItem(at: system) }
        let text = speakerTranscript(segs)
        if !text.isEmpty, SettingsStore.autoSummaryOn(),
           let repo = SummaryCatalog.spec(for: SettingsStore.currentSummaryModelId())?.repoId {
            if await makeSummary(meetingId: id, text: text, repo: repo) {
                notify("Summary ready", "Саммари готово", "摘要已就绪")
                showToast(tr("toast.summaryReady"), tone: .good)
            }
        }
    }

    /// Generates + persists a summary using ONLY the user-selected model — no silent
    /// fallback to a smaller (weaker) model. If the chosen model can't load (e.g. 8B on
    /// 16GB) or returns nothing, the user gets the REAL reason via a toast. Serialized:
    /// the MLX container is single-instance.
    @discardableResult
    private func makeSummary(meetingId id: String, text: String, repo: String) async -> Bool {
        guard !isSummarizing else { return false }
        isSummarizing = true
        defer { isSummarizing = false }
        let lang = whisperLang()
        transcription.unload()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 200_000_000)

        await summary.ensureLoaded(repoId: repo)
        guard summary.isReady else {
            showToast(summaryErrorMessage(), tone: .error)
            return false
        }
        let md = await summary.summarize(transcript: text, languageCode: lang)
        guard !md.isEmpty else {
            showToast(summaryErrorMessage(), tone: .error)
            return false
        }
        store.saveSummary(meetingId: id, summary: MeetingSummary(markdown: md))
        let topic = SummaryMarkdown.title(from: md)
        if let topic { store.rename(id, title: topic) }
        exportSummary(meetingId: id, markdown: md, title: topic)
        return true
    }

    /// Surfaces the REAL summary failure reason instead of a generic toast: a
    /// low-memory rejection (pick a smaller model) or the underlying MLX error.
    private func summaryErrorMessage() -> String {
        if case let .error(reason) = summary.status {
            if reason == "low-memory" { return tr("toast.summaryLowMemory") }
            if !reason.isEmpty, reason != "empty" { return reason }
        }
        return tr("toast.summaryFailed")
    }

    /// Tags a transcribed segment with its capture source.
    private func tag(_ seg: TranscriptSegment, _ source: TranscriptSource) -> TranscriptSegment {
        var s = seg; s.source = source; return s
    }

    /// Builds speaker-attributed transcript text for the summary AI: each line is
    /// prefixed with who said it ("Me"/"Speaker") so the model can tell participants
    /// apart. Unknown-source lines (legacy) are passed through unprefixed.
    private func speakerTranscript(_ segs: [TranscriptSegment]) -> String {
        let me = tr("speaker.me"), them = tr("speaker.them")
        return segs.map { seg in
            switch seg.source {
            case .mic: "\(me): \(seg.text)"
            case .system: "\(them): \(seg.text)"
            case .unknown: seg.text
            }
        }.joined(separator: "\n")
    }

    func regenerate(meetingId id: String) {
        guard !processingIds.contains(id) else { return }
        let text = speakerTranscript(store.transcript(meetingId: id))
        guard !text.isEmpty, let repo = SummaryCatalog.spec(for: SettingsStore.currentSummaryModelId())?.repoId else { return }
        processingIds.insert(id)
        Task {
            if await makeSummary(meetingId: id, text: text, repo: repo) {
                showToast(tr("toast.summaryReady"), tone: .good)
            }
            processingIds.remove(id)
            revision += 1
        }
    }

    /// Auto-saves the summary as a Markdown file in the user-chosen export folder.
    private func exportSummary(meetingId id: String, markdown md: String, title: String?) {
        let m = meeting(id)
        SummaryExport.write(markdown: md,
                            title: title ?? m?.title ?? "",
                            createdAt: m?.createdAt ?? Date(),
                            typeLabel: tr("meeting.exportType"),
                            folder: SettingsStore.exportFolder())
    }

    /// Move the sidebar selection up/down (list is sorted newest-first).
    func selectAdjacentMeeting(_ delta: Int) {
        let list = store.meetings
        route = .meetings
        let cur = selectedMeetingId.flatMap { id in list.firstIndex(where: { $0.id == id }) }
        guard let next = Nav.adjacentIndex(count: list.count, current: cur, delta: delta) else { return }
        selectedMeetingId = list[next].id
    }

    func requestDeleteSelected() {
        if let id = selectedMeetingId, let m = meeting(id) { deleting = m }
    }

    func meeting(_ id: String) -> Meeting? {
        store.meetings.first { $0.id == id }
    }

    func isProcessing(_ id: String) -> Bool {
        processingIds.contains(id)
    }

    func rename(_ id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.rename(id, title: trimmed) }
        renaming = nil
    }

    func confirmDelete(_ id: String) {
        store.delete(id)
        if selectedMeetingId == id { selectedMeetingId = nil; route = .home }
        deleting = nil
    }

    /// Neutral placeholder until the AI names the meeting from its summary.
    /// (The sidebar/header already prefix the time, so no date/time here.)
    private func defaultTitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .ru: "Новая запись"
        case .zh: "新录音"
        case .en: "New recording"
        }
    }
}
