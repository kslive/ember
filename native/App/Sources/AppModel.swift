import AudioService
import CallDetectService
import Combine
import Core
import DiarizationService
import OSLog
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
    private let diarization = DiarizationService()
    private var autoStarted = false
    private static let log = Logger(subsystem: "com.kslff.ember", category: "pipeline")

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
        startRecording(auto: true)
    }

    private func autoStopFromCall() {
        guard isRecordingActive, autoStarted else { return }
        stopRecording(language: .current, discardIfPhantom: true)
    }

    var isRecordingActive: Bool {
        engine.status == .recording || engine.status == .paused || engine.status == .starting
    }

    /// `auto` marks a call-detect-initiated session. The flag is committed ONLY after
    /// the engine actually starts — setting it before (and leaving it on a failed
    /// start) made a later call-end kill an unrelated MANUAL recording.
    func startRecording(auto: Bool = false) {
        guard !isStarting, !isRecordingActive else { return }
        route = .home
        isStarting = true
        Task {
            defer { isStarting = false }
            guard await RecordingEngine.requestMicPermission() else {
                autoStarted = false
                showToast(tr("toast.micDenied"), tone: .error)
                return
            }
            let id = UUID().uuidString
            recordingId = id
            do {
                try engine.start(meetingId: id)
            } catch {
                recordingId = nil
                autoStarted = false
                showToast(tr("toast.recFailed"), tone: .error)
                return
            }
            autoStarted = auto
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
    private struct LiveState {
        var confirmed: [TranscriptSegment] = []
        var confirmedSamples = 0
        var live: [TranscriptSegment] = []
        /// Accumulator size at the last decode — used to detect whether anything NEW
        /// arrived since, so unchanged tails aren't re-decoded every tick.
        var lastTotal = 0
        /// True once the tail was decoded after speech stopped (one "settling" pass).
        /// While settled and the incoming delta stays silent, decoding is skipped —
        /// re-decoding an unchanged 30s window every 1.8s kept the ANE at ~100% duty
        /// through every pause (the main heat source on long recordings).
        var settled = false
    }

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
            var sleepNs: UInt64 = 1_800_000_000
            while !Task.isCancelled, isRecordingActive {
                try? await Task.sleep(nanoseconds: sleepNs)
                guard !Task.isCancelled, engine.status == .recording, transcription.isReady else { continue }
                let t0 = ContinuousClock.now
                mic = await advanceLive(mic, meetingId: meetingId, source: .mic,
                                        total: engine.liveMicCount(),
                                        tailFrom: { self.engine.liveMicSlice(from: $0) })
                sys = await advanceLive(sys, meetingId: meetingId, source: .system,
                                        total: engine.liveSystemCount(),
                                        tailFrom: { self.engine.liveSystemSlice(from: $0) })
                if Task.isCancelled { break }
                liveSegments = TranscriptMerge.merge(mic: mic.live, system: sys.live)
                // Adaptive pacing: never stack decode cycles — if a cycle took longer
                // than the base interval, rest at least that long (capped at 4s).
                let d = (ContinuousClock.now - t0).components
                let cycleSeconds = Double(d.seconds) + Double(d.attoseconds) / 1e18
                sleepNs = UInt64(min(4.0, max(1.8, cycleSeconds)) * 1_000_000_000)
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
        // Duty-cycle gate: decode only when the NEW samples since the last decode carry
        // speech, or one final "settling" pass right after speech stops. A settled tail
        // with a silent delta is skipped entirely (no ANE work during pauses).
        let deltaLoud = total > s.lastTotal
            && AudioLevel.peak(tailFrom(max(s.confirmedSamples, s.lastTotal))) > Self.silencePeak
        if !deltaLoud, s.settled {
            s.lastTotal = total
            return s
        }
        let rawTail = tailFrom(s.confirmedSamples)
        guard AudioLevel.peak(rawTail) > Self.silencePeak else {
            s.lastTotal = total
            s.settled = true
            return s
        }
        let lead = AudioLevel.leadingSilence(rawTail, threshold: Self.silencePeak)
        let tail = lead > 0 ? Array(rawTail[lead...]) : rawTail
        let base = Double(s.confirmedSamples + lead) / 16000.0
        let segs = await transcription.transcribeSamples(tail, meetingId: meetingId, language: whisperLang())
        s.lastTotal = total
        s.settled = !deltaLoud
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

    /// An AUTO session shorter than this is a phantom (a push woke some app's
    /// full-duplex sound engine / a speech daemon held the mic for 10–20s), not a
    /// call — real calls run minutes. Discarded instead of saved. Manual recordings
    /// are never discarded.
    private static let phantomAutoSeconds: TimeInterval = 25

    /// `discardIfPhantom` is passed ONLY by the call-detect auto-stop: a detector-ended
    /// auto session shorter than the threshold is a push/daemon mic-blip, not a call.
    /// A USER-pressed stop always saves — even a short auto-started recording.
    func stopRecording(language: AppLanguage, discardIfPhantom: Bool = false) {
        let live = liveTask
        liveTask?.cancel()
        liveTask = nil
        let liveFinal = liveSegments
        liveSegments = []
        let (mic, system) = engine.stop()
        let elapsed = engine.elapsed
        if discardIfPhantom, autoStarted, elapsed < Self.phantomAutoSeconds {
            Self.log.info("phantom auto session (\(elapsed, format: .fixed(precision: 1), privacy: .public)s) — discarded")
            if let mic { try? FileManager.default.removeItem(at: mic) }
            if let system { try? FileManager.default.removeItem(at: system) }
            engine.reset()
            recordingId = nil
            autoStarted = false
            showToast(tr("toast.autoDiscarded"), tone: .info)
            return
        }
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
        Task {
            await live?.value
            await process(meetingId: id, liveFinal: liveFinal, micSamples: micSamples,
                          systemSamples: systemSamples, mic: mic, system: system)
        }
    }

    private func process(meetingId id: String, liveFinal: [TranscriptSegment], micSamples: [Float],
                         systemSamples: [Float], mic: URL?, system: URL?) async {
        defer { processingIds.remove(id); revision += 1 }
        let lang = whisperLang()
        let sysGated = !systemSamples.isEmpty && AudioLevel.peak(systemSamples) >= Self.silencePeak

        // 1. Instant: persist the full live transcript right away (no blank wait).
        var segs = liveFinal.filter { TranscriptionService.hasSpeech($0.text) }
        if !segs.isEmpty {
            store.saveTranscript(meetingId: id, segments: segs)
            revision += 1
        }

        // 2. Full re-pass WITHOUT VAD (strict: false) — VAD-chunking dropped quiet speech
        // and truncated the final; the plain pass (leading-silence trimmed per channel)
        // transcribes the whole buffer with correct timecodes.
        await transcription.ensureLoaded(model: SettingsStore.currentWhisperModelId())
        async let micRaw = transcribeChannel(micSamples, meetingId: id, source: .mic)
        async let sysRaw = transcribeChannel(systemSamples, meetingId: id, source: .system)
        let micSegs = await micRaw
        let sysSegs = await sysRaw
        Self.logChannels(micSamples: micSamples, systemSamples: systemSamples, micSegs: micSegs, sysSegs: sysSegs)
        let rePass = TranscriptMerge.merge(mic: micSegs, system: sysSegs)

        // 3. Keep the richer of {live, re-pass} → the final is never shorter than live.
        let liveLen = segs.reduce(0) { $0 + $1.text.count }
        let rePassLen = rePass.reduce(0) { $0 + $1.text.count }
        let useRepass = !rePass.isEmpty && rePassLen >= liveLen
        if useRepass { segs = rePass }
        Self.log.info("final source=\(useRepass ? "repass" : "live", privacy: .public) live=\(liveLen, privacy: .public) repass=\(rePassLen, privacy: .public)")

        // 4. File-mix fallback only if both live and re-pass produced nothing.
        if segs.isEmpty {
            let mixedURL = RecordingEngine.recordingsDir().appendingPathComponent("\(id).m4a")
            if let audioURL = await AudioMixer.mix(mic: mic, system: system, output: mixedURL) ?? mic ?? system {
                segs = await transcription.transcribe(url: audioURL, meetingId: id, language: lang, strict: false)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        // Offline speaker diarization of the SYSTEM channel → number distinct voices
        // ("Собеседник 1/2/3"). Best-effort: on any failure segments keep speaker 0.
        if SettingsStore.diarizationOn(), sysGated {
            let turns = await diarization.diarize(systemSamples)
            if !turns.isEmpty { segs = DiarizationMap.assign(segs, turns: turns) }
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
        // Free the CoreML model after 5 idle minutes — it otherwise stays resident
        // (1.5–2+ GB) between meetings; the next recording reloads it in seconds.
        transcription.scheduleIdleUnload()
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

    /// Transcribes ONE channel's full buffer with the leading silence trimmed off —
    /// Whisper snaps speech to t=0 on a long silent lead-in, so feed it only from the
    /// first real sample and add the trimmed offset back to each segment. Tags the
    /// source; empty when the channel is silent.
    private func transcribeChannel(_ samples: [Float], meetingId id: String, source: TranscriptSource) async -> [TranscriptSegment] {
        guard AudioLevel.peak(samples) > Self.silencePeak else { return [] }
        let lead = AudioLevel.leadingSilence(samples, threshold: Self.silencePeak)
        let trimmed = lead > 0 ? Array(samples[lead...]) : samples
        let base = Double(lead) / 16000.0
        let segs = await transcription.transcribeSamples(trimmed, meetingId: id, language: whisperLang(), strict: false)
        return segs.map { seg in
            var s = seg
            s.startSeconds += base
            s.endSeconds += base
            s.source = source
            return s
        }
    }

    /// Logs per-channel duration + transcribed segment time-ranges (timeline debugging:
    /// reveals if the system channel lands at ~0 when it should be offset, or if the mic
    /// channel is empty/lost).
    private static func logChannels(micSamples: [Float], systemSamples: [Float],
                                    micSegs: [TranscriptSegment], sysSegs: [TranscriptSegment]) {
        func rng(_ segs: [TranscriptSegment]) -> String {
            guard let lo = segs.map(\.startSeconds).min(), let hi = segs.map(\.endSeconds).max() else { return "—" }
            return String(format: "%.1f–%.1fs", lo, hi)
        }
        let mic = String(format: "%.1f", Double(micSamples.count) / 16000)
        let sys = String(format: "%.1f", Double(systemSamples.count) / 16000)
        let msg = "channels mic=\(mic)s (\(micSegs.count) segs \(rng(micSegs))) system=\(sys)s (\(sysSegs.count) segs \(rng(sysSegs)))"
        log.info("\(msg, privacy: .public)")
    }

    /// Builds speaker-attributed transcript text for the summary AI: each line is
    /// prefixed with who said it ("Я"/"Собеседник N") — including the diarized speaker
    /// number — so the model can tell participants apart. Unknown lines pass through.
    private func speakerTranscript(_ segs: [TranscriptSegment]) -> String {
        let me = tr("speaker.me"), them = tr("speaker.them")
        return segs.map { seg in
            if let label = SpeakerLabel.text(source: seg.source, speaker: seg.speaker, me: me, them: them) {
                return "\(label): \(seg.text)"
            }
            return seg.text
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
