import AudioService
import CallDetectService
import Combine
import Core
import MeetingsFeature
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
    let summaryEditor = SummaryEditorModel()
    let callDetect = CallDetectService()
    let liveContext = LiveContextEngine()
    private let overlayController = OverlayController()
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
    @Published private(set) var processingStages: [String: ProcessingProgress] = [:]
    @Published private(set) var revision = 0

    private var recordingId: String?
    /// When the current recording STARTED — the meeting's createdAt. Stamping Date()
    /// at stop labeled every meeting with its END time (sidebar + Obsidian export).
    private var recordingStartedAt: Date?
    private var recordingCalendarTitle: String?
    private var calendarMeetingTitles: [String: String] = [:]
    private var isStarting = false
    private var isSummarizing = false

    /// Deferred-processing queue (Settings → Recording): heavy post-processing of
    /// finished calls waits here until NO recording is active. Jobs reference the
    /// ALIGNED 16k spill files on disk (not RAM: ~460 MB/hour would pile up during
    /// back-to-back calls). In-memory only — on relaunch purgeRecordings() wipes the
    /// spill files and the queue is gone; the live transcript is already in the DB,
    /// the summary is one "Regenerate" away. Nothing is lost silently.
    private enum QueuedWork {
        case full(mic16k: URL?, sys16k: URL?, lang: String)
        case summaryOnly
    }

    private struct QueuedJob {
        let meetingId: String
        let work: QueuedWork
    }

    private var deferredQueue: [QueuedJob] = []
    private var isDraining = false
    private var drainTask: Task<Void, Never>?
    /// The job the drain is compute-ing right now (nil between jobs). When a call
    /// interrupts it, this is re-queued at the FRONT and the meeting flips to
    /// `.queued` INSTANTLY — without waiting for the (mid-window-uninterruptible)
    /// transcription/summary to actually unwind.
    private var drainingJob: QueuedJob?
    /// Meetings whose in-flight compute was interrupted and already re-queued by
    /// `interruptDraining` — `process()` bails at its next checkpoint without saving
    /// or re-queuing a second time.
    private var interruptedIds: Set<String> = []

    /// The deferred queue is IN EFFECT only together with auto-summary — the
    /// settings toggle is disabled without it (nothing to defer), and the pipeline
    /// mirrors that so a stale stored flag can't change behavior.
    private var deferredActive: Bool {
        SettingsStore.deferredProcessingOn() && SettingsStore.autoSummaryOn()
    }

    private var liveTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    /// Quit was requested — no new pipeline work may start while the in-flight
    /// decode drains (see `beginQuitDrain`).
    private var isQuitting = false

    init() {
        for obj in [store.objectWillChange, engine.objectWillChange,
                    transcription.objectWillChange, summary.objectWillChange] {
            obj.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        summaryEditor.onSave = { [weak self] id, md in self?.saveEditedSummary(meetingId: id, markdown: md) }
        liveContext.onCloudError = { [weak self] reason in
            self?.showToast("DeepSeek: \(reason)", tone: .warn)
        }
        engine.$status
            .removeDuplicates()
            .sink { [weak self] st in
                guard st == .idle || st == .completed else { return }
                Task { @MainActor in self?.drainIfIdle() }
            }
            .store(in: &cancellables)
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
        // Launch-at-login defaults to ON (the app's whole point is catching calls,
        // which needs it running) — but only ONCE: a user who turns it off must not
        // be re-enrolled on the next launch.
        if !UserDefaults.standard.bool(forKey: "ember.launchAtLoginDefaulted") {
            UserDefaults.standard.set(true, forKey: "ember.launchAtLoginDefaulted")
            LaunchAtLogin.setEnabled(true)
        }
        // Calendar titles are ON but the system grant is gone (an update changed the
        // signing identity, or the user reset privacy settings) — re-request right at
        // launch instead of silently stopping to pick titles until the toggle is
        // flipped off and on again.
        if SettingsStore.calendarTitlesOn(), CalendarTitles.accessStatus() == .notDetermined {
            Task { _ = await CalendarTitles.requestAccess() }
        }
        AppDelegate.model = self
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
            if deferredActive {
                // A call just started: stop the heavy pipeline NOW (token-level for
                // MLX, per-window for Whisper, per-chunk for GigaAM) and flip the
                // in-flight meeting back to "queued" immediately.
                drainTask?.cancel()
                summary.requestAbort()
                transcription.requestAbort()
                interruptDraining()
            }
            recordingStartedAt = Date()
            recordingCalendarTitle = SettingsStore.calendarTitlesOn() ? CalendarTitles.eventTitle(at: Date()) : nil
            startLiveLoop(id)
            syncLiveOverlay()
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
                syncLiveOverlay()
                if SettingsStore.liveOverlayOn() {
                    liveContext.ingest(text: speakerTranscript(liveSegments))
                }
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

    /// Keeps the overlay in step with the settings toggle DURING a recording:
    /// flipping it on shows the panel (and warms the engine), flipping it off
    /// hides the panel and frees the live model.
    private func syncLiveOverlay() {
        guard isRecordingActive else { return }
        // canServe: no DeepSeek key AND no downloaded 1.7B → the overlay has
        // nothing to run on; Settings shows the disabled state with the reason.
        if SettingsStore.liveOverlayOn(), liveContext.canServe {
            if !overlayController.isVisible, !overlayController.dismissedForSession {
                overlayController.show(engine: liveContext)
                if liveContext.phase == .idle { Task { await liveContext.start() } }
            }
        } else if overlayController.isVisible {
            overlayController.hide()
            liveContext.stop()
        }
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
        overlayController.end()
        liveContext.stop()
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
            recordingStartedAt = nil
            recordingCalendarTitle = nil
            autoStarted = false
            transcription.unload()
            showToast(tr("toast.autoDiscarded"), tone: .info)
            return
        }
        let micSamples = engine.liveSamples()
        let systemSamples = engine.systemSamples()
        let id = recordingId ?? UUID().uuidString
        let calendarTitle = recordingCalendarTitle
        recordingCalendarTitle = nil
        if let calendarTitle { calendarMeetingTitles[id] = calendarTitle }
        let meeting = Meeting(id: id, title: calendarTitle ?? defaultTitle(language),
                              createdAt: recordingStartedAt ?? Date(), durationSeconds: engine.elapsed)
        store.upsert(meeting)
        engine.reset()
        recordingId = nil
        recordingStartedAt = nil
        autoStarted = false
        route = .home
        guard mic != nil || system != nil else {
            transcription.unload()
            return
        }
        processingIds.insert(id)
        if deferredActive {
            notify("Recording queued — processing after your calls", "Запись в очереди — обработаю после звонков",
                   "录音已排队——通话结束后处理")
            showToast(tr("toast.recQueued"), tone: .info)
            Task {
                await live?.value
                await enqueueDeferred(meetingId: id, liveFinal: liveFinal, micSamples: micSamples,
                                      systemSamples: systemSamples, mic: mic, system: system)
                drainIfIdle()
            }
        } else {
            notify("Recording stopped — processing…", "Запись остановлена — обработка…", "录音已停止——处理中…")
            showToast(tr("toast.recStopped"), tone: .info)
            Task {
                await live?.value
                await process(meetingId: id, liveFinal: liveFinal, micSamples: micSamples,
                              systemSamples: systemSamples, mic: mic, system: system)
            }
        }
    }

    /// Deferred mode, at stop: save the live transcript NOW (the user sees content
    /// immediately), spill the ALIGNED 16k accumulators to the transit dir off-main,
    /// delete the unaligned 48k engine files, and mark the meeting as queued. The
    /// recognition language is captured here — the user may switch it before drain.
    private func enqueueDeferred(meetingId id: String, liveFinal: [TranscriptSegment],
                                 micSamples: [Float], systemSamples: [Float], mic: URL?, system: URL?) async {
        let segs = liveFinal.filter { TranscriptionService.hasSpeech($0.text) }
        if !segs.isEmpty {
            store.saveTranscript(meetingId: id, segments: segs)
        }
        processingStages[id] = ProcessingProgress(stage: .queued, step: 1, total: 1)
        revision += 1
        let dir = RecordingEngine.recordingsDir()
        let micURL = dir.appendingPathComponent("\(id)-mic16k.caf")
        let sysURL = dir.appendingPathComponent("\(id)-sys16k.caf")
        let written = await Task.detached(priority: .utility) {
            (mic: AudioMixer.writeSamples16k(micSamples, to: micURL),
             sys: AudioMixer.writeSamples16k(systemSamples, to: sysURL))
        }.value
        if let mic { try? FileManager.default.removeItem(at: mic) }
        if let system { try? FileManager.default.removeItem(at: system) }
        deferredQueue.append(QueuedJob(meetingId: id, work: .full(mic16k: written.mic, sys16k: written.sys,
                                                                  lang: whisperLang())))
        refreshQueuedStages()
    }

    /// Re-stamps every queued meeting with its live position ("В очереди: N из M").
    private func refreshQueuedStages() {
        let total = deferredQueue.count
        for (i, job) in deferredQueue.enumerated() {
            processingStages[job.meetingId] = ProcessingProgress(stage: .queued, step: i + 1, total: total)
        }
        revision += 1
    }

    /// Drains the deferred queue sequentially while NO recording is active. Runs
    /// regardless of the toggle (turning it OFF with a non-empty queue must still
    /// drain). Re-entrancy-safe via `isDraining` (everything is MainActor); the loop
    /// re-checks `isRecordingActive` before every job so a new call pauses the queue
    /// — the engine-status sink re-triggers the drain when it ends.
    private func drainIfIdle() {
        guard !isQuitting, !isDraining, !deferredQueue.isEmpty, !isRecordingActive else { return }
        isDraining = true
        drainTask = Task {
            while !deferredQueue.isEmpty, !isRecordingActive, !Task.isCancelled {
                let job = deferredQueue.removeFirst()
                refreshQueuedStages()
                await runDeferred(job)
            }
            isDraining = false
            // Queue fully drained and nothing recording → free BOTH models right
            // away so the GPU/CPU go quiet (an interrupted drain skips this — the
            // live loop still needs the ASR model).
            if deferredQueue.isEmpty, !isRecordingActive {
                transcription.unload()
                summary.unload()
            }
        }
    }

    private func runDeferred(_ job: QueuedJob) async {
        let id = job.meetingId
        processingIds.insert(id)
        drainingJob = job
        defer { if drainingJob?.meetingId == id { drainingJob = nil } }
        switch job.work {
        case let .full(mic16k, sys16k, lang):
            let samples = await Task.detached(priority: .utility) {
                (mic: mic16k.flatMap { AudioMixer.decode16kMono($0) } ?? [],
                 sys: sys16k.flatMap { AudioMixer.decode16kMono($0) } ?? [])
            }.value
            let liveFinal = store.transcript(meetingId: id)
            await process(meetingId: id, liveFinal: liveFinal, micSamples: samples.mic,
                          systemSamples: samples.sys, mic: mic16k, system: sys16k,
                          fromQueue: true, langOverride: lang)
        case .summaryOnly:
            var requeued = false
            defer {
                if !requeued { processingIds.remove(id); processingStages.removeValue(forKey: id) }
                revision += 1
            }
            let text = speakerTranscript(store.transcript(meetingId: id))
            guard !text.isEmpty, SettingsStore.autoSummaryOn(),
                  let repo = SummaryCatalog.spec(for: SettingsStore.currentSummaryModelId())?.repoId else { return }
            processingStages[id] = ProcessingProgress(stage: .summarize, step: 1, total: 1)
            if await makeSummary(meetingId: id, text: text, repo: repo) {
                notify("Summary ready", "Саммари готово", "摘要已就绪")
                showToast(tr("toast.summaryReady"), tone: .good)
            } else if requeueIfInterrupted(id: id, work: .summaryOnly) {
                requeued = true
            }
        }
    }

    /// A call started mid-drain: instantly reflect the in-flight job as queued and
    /// re-queue it at the FRONT (its spill files are still on disk), so the UI shows
    /// "waiting" without waiting for the compute to unwind. `process()` /
    /// `runDeferred` see the id in `interruptedIds` and bail without saving.
    private func interruptDraining() {
        guard let job = drainingJob else { return }
        let id = job.meetingId
        interruptedIds.insert(id)
        if !deferredQueue.contains(where: { $0.meetingId == id }) {
            deferredQueue.insert(job, at: 0)
        }
        drainingJob = nil
        refreshQueuedStages()
    }

    /// Requeue decision at a `process()` checkpoint: if this meeting was interrupted
    /// it is ALREADY back in the queue (just consume the flag); otherwise re-queue it
    /// when a recording is active or the drain task was cancelled. Returns whether the
    /// caller should bail.
    private func requeueIfInterrupted(id: String, work: QueuedWork) -> Bool {
        if interruptedIds.contains(id) {
            interruptedIds.remove(id)
            return true
        }
        if isRecordingActive || Task.isCancelled {
            deferredQueue.append(QueuedJob(meetingId: id, work: work))
            refreshQueuedStages()
            return true
        }
        return false
    }

    /// Drops a meeting's queued job and its spill files (user deleted the meeting).
    private func removeDeferred(meetingId id: String) {
        deferredQueue.removeAll { $0.meetingId == id }
        refreshQueuedStages()
        let dir = RecordingEngine.recordingsDir()
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id)-mic16k.caf"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id)-sys16k.caf"))
    }

    private func process(meetingId id: String, liveFinal: [TranscriptSegment], micSamples: [Float],
                         systemSamples: [Float], mic: URL?, system: URL?,
                         fromQueue: Bool = false, langOverride: String? = nil) async {
        var requeued = false
        defer {
            if !requeued { processingIds.remove(id); processingStages.removeValue(forKey: id) }
            revision += 1
        }
        let lang = langOverride ?? whisperLang()
        let plan = ProcessingStage.plan(
            summarize: SettingsStore.autoSummaryOn()
                && SummaryCatalog.spec(for: SettingsStore.currentSummaryModelId())?.repoId != nil
        )
        func enterStage(_ stage: ProcessingStage) {
            guard let i = plan.firstIndex(of: stage) else { return }
            processingStages[id] = ProcessingProgress(stage: stage, step: i + 1, total: plan.count)
        }
        enterStage(.transcribe)

        // 1. Instant: persist the full live transcript right away (no blank wait).
        var segs = liveFinal.filter { TranscriptionService.hasSpeech($0.text) }
        if !segs.isEmpty {
            store.saveTranscript(meetingId: id, segments: segs)
            revision += 1
        }

        // Deferred mode: a call is active (or the job was interrupted) — bail before
        // any heavy work; the job is/goes back in the queue with its spill files.
        if fromQueue, requeueIfInterrupted(id: id, work: .full(mic16k: mic, sys16k: system, lang: lang)) {
            requeued = true
            return
        }

        // 2. Full re-pass WITHOUT VAD (strict: false) — VAD-chunking dropped quiet speech
        // and truncated the final; the plain pass (leading-silence trimmed per channel)
        // transcribes the whole buffer with correct timecodes.
        await transcription.ensureLoaded(model: SettingsStore.currentWhisperModelId())
        transcription.clearAbort()
        async let micRaw = transcribeChannel(micSamples, meetingId: id, source: .mic, language: lang)
        async let sysRaw = transcribeChannel(systemSamples, meetingId: id, source: .system, language: lang)
        let micSegs = await micRaw
        let sysSegs = await sysRaw
        // Aborted mid-transcription: the partial re-pass is unusable — bail and let
        // the whole job re-run from the queue after the calls end.
        if fromQueue, requeueIfInterrupted(id: id, work: .full(mic16k: mic, sys16k: system, lang: lang)) {
            requeued = true
            return
        }
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
        store.saveTranscript(meetingId: id, segments: segs)
        revision += 1
        if let mic { try? FileManager.default.removeItem(at: mic) }
        if let system { try? FileManager.default.removeItem(at: system) }
        let text = speakerTranscript(segs)
        if !text.isEmpty, SettingsStore.autoSummaryOn(),
           let repo = SummaryCatalog.spec(for: SettingsStore.currentSummaryModelId())?.repoId {
            // Deferred mode: a call is running (or interrupted) — the transcript is
            // saved, only the summary goes back to the queue (mirrors regenerate).
            if deferredActive, requeueIfInterrupted(id: id, work: .summaryOnly) {
                requeued = true
                return
            }
            enterStage(.summarize)
            if await makeSummary(meetingId: id, text: text, repo: repo) {
                notify("Summary ready", "Саммари готово", "摘要已就绪")
                showToast(tr("toast.summaryReady"), tone: .good)
            } else if deferredActive, requeueIfInterrupted(id: id, work: .summaryOnly) {
                // Aborted mid-generation: silently hand the summary back to the queue.
                requeued = true
                return
            }
        }
        // Free the ASR model IMMEDIATELY — it otherwise stays resident (1.5–2+ GB)
        // between meetings; the next recording reloads it in seconds. Skipped when a
        // new recording already started: its live loop is using the model, and that
        // session's own processing will unload at its end.
        if !isRecordingActive { transcription.unload() }
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
        // The meeting's chosen template (empty → global default). A broken/missing
        // template file yields nil → the summary falls back to the built-in prompt.
        let templateId = meeting(id)?.templateId.isEmpty == false
            ? meeting(id)!.templateId : SettingsStore.currentSummaryTemplateId()
        let systemOverride = SummaryTemplates.renderedSystem(id: templateId, languageCode: lang)

        // Cloud path first (optional DeepSeek key): fast, no local RAM/GPU cost.
        // ANY failure — no network, bad key, HTTP error, empty answer — falls through
        // to the local model, so a summary is always produced.
        if let cloudMd = await cloudSummary(text: text, lang: lang, systemOverride: systemOverride) {
            persistSummary(meetingId: id, markdown: cloudMd, templateId: templateId)
            return true
        }

        // Reclaim the ASR model's RAM before loading MLX — unless a NEW recording is
        // already live and its loop still needs it.
        if !isRecordingActive { transcription.unload() }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 200_000_000)

        // The MLX weights are freed IMMEDIATELY after generation on every exit path
        // (the error message is read from status BEFORE unload resets it).
        await summary.ensureLoaded(repoId: repo)
        guard summary.isReady else {
            if Task.isCancelled || summary.abortRequested { summary.unload(); return false }
            showToast(summaryErrorMessage(), tone: .error)
            summary.unload()
            return false
        }
        let md = await summary.summarize(transcript: text, languageCode: lang, systemOverride: systemOverride)
        guard !md.isEmpty else {
            // An abort (a call started, deferred mode) is not an error — no toast.
            if Task.isCancelled || summary.abortRequested { summary.unload(); return false }
            showToast(summaryErrorMessage(), tone: .error)
            summary.unload()
            return false
        }
        summary.unload()
        persistSummary(meetingId: id, markdown: md, templateId: templateId)
        return true
    }

    /// DeepSeek attempt. nil = no key configured or the cloud failed (logged + toast)
    /// — the caller continues with the local model.
    private func cloudSummary(text: String, lang: String, systemOverride: String?) async -> String? {
        guard let key = SettingsStore.deepseekKey() else { return nil }
        do {
            // Re-validate the stored id against /models on every summary: DeepSeek
            // RETIRES model ids (deepseek-chat/-reasoner die 2026-07-24) — a stale
            // stored id would fail every cloud summary until the user re-picked one.
            guard let model = try await DeepSeekClient.resolveModel(
                key: key, stored: SettingsStore.deepseekModelId(), preferFast: false
            ) else { return nil }
            return try await summary.summarizeCloud(key: key, model: model, transcript: text,
                                                    languageCode: lang, systemOverride: systemOverride)
        } catch {
            Self.log.error("deepseek failed → local fallback: \(String(describing: error), privacy: .public)")
            showToast(tr("toast.deepseekFellBack"), tone: .warn)
            return nil
        }
    }

    /// Write-through for the live summary editor: DB first (with the edited-at
    /// stamp), then the exported .md — Sage/Obsidian watch that file and update
    /// live. The file write echoing back through the editor's folder watcher is
    /// a no-op (body == buffer). Deliberately NO `revision` bump: reloading the
    /// detail container mid-typing would churn the view for nothing.
    func saveEditedSummary(meetingId id: String, markdown md: String) {
        store.saveSummary(meetingId: id, summary: MeetingSummary(markdown: md, editedAt: Date()))
        exportSummary(meetingId: id, markdown: md, title: nil)
    }

    /// The exported .md path of a meeting under the CURRENT settings — the file
    /// the live editor watches and Sage/Obsidian open.
    func exportedSummaryURL(for meeting: Meeting) -> URL? {
        let folder = SettingsStore.exportFolder()
        guard !folder.isEmpty else { return nil }
        return URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent(SummaryExport.dateFolder(createdAt: meeting.createdAt), isDirectory: true)
            .appendingPathComponent(SummaryExport.fileName(title: meeting.title, createdAt: meeting.createdAt))
    }

    /// Shared tail for both summary paths: save, AI-title rename, auto-export.
    /// A calendar-sourced title wins over the AI one: the meeting was named at
    /// stop from the event running at recording start, so the AI rename is
    /// skipped (session-scoped — after a relaunch "Перегенерировать" renames
    /// again; acceptable edge).
    private func persistSummary(meetingId id: String, markdown md: String, templateId: String) {
        store.saveSummary(meetingId: id, summary: MeetingSummary(markdown: md))
        // Pin the template the summary was actually made with, so the picker keeps
        // showing it even after the global default changes (state is preserved).
        store.setMeetingTemplate(id, templateId: templateId)
        if let calendarTitle = calendarMeetingTitles[id] {
            exportSummary(meetingId: id, markdown: md, title: calendarTitle)
            return
        }
        let topic = SummaryMarkdown.title(from: md)
        if let topic { store.rename(id, title: topic) }
        exportSummary(meetingId: id, markdown: md, title: topic)
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
    private func transcribeChannel(_ samples: [Float], meetingId id: String, source: TranscriptSource,
                                   language: String) async -> [TranscriptSegment] {
        guard AudioLevel.peak(samples) > Self.silencePeak else { return [] }
        let lead = AudioLevel.leadingSilence(samples, threshold: Self.silencePeak)
        let trimmed = lead > 0 ? Array(samples[lead...]) : samples
        let base = Double(lead) / 16000.0
        let segs = await transcription.transcribeSamples(trimmed, meetingId: id, language: language, strict: false,
                                                         interruptible: true)
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

    /// Builds channel-attributed transcript text for the summary AI: each line is
    /// prefixed with its side ("Я"/"Собеседник") from the mic/system channel. The
    /// model tells distinct participants apart from the content itself. Unknown
    /// lines pass through.
    private func speakerTranscript(_ segs: [TranscriptSegment]) -> String {
        let me = tr("speaker.me"), them = tr("speaker.them")
        return segs.map { seg in
            if let label = SpeakerLabel.text(source: seg.source, me: me, them: them) {
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
        processingStages[id] = ProcessingProgress(stage: .summarize, step: 1, total: 1)
        Task {
            if await makeSummary(meetingId: id, text: text, repo: repo) {
                showToast(tr("toast.summaryReady"), tone: .good)
            }
            processingIds.remove(id)
            processingStages.removeValue(forKey: id)
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

    /// Persists the per-meeting summary template and bumps `revision` so the open
    /// detail view re-reads the meeting with its new `templateId`.
    func setMeetingTemplate(_ id: String, templateId: String) {
        store.setMeetingTemplate(id, templateId: templateId)
        revision += 1
    }

    func confirmDelete(_ id: String) {
        removeDeferred(meetingId: id)
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

/// Quit-drain: exit() runs C++ static destructors (the ONNX OpSchema registry)
/// while a background Ort::Session::Run may still be executing — ORT then throws
/// into the dying runtime and the process SIGABRTs (the crash-on-quit report).
extension AppModel {
    /// Called from `applicationShouldTerminate`. Aborts the whole pipeline
    /// (token-level MLX, per-window Whisper, per-chunk GigaAM) so the in-flight
    /// decode is the LAST one, and — when quitting mid-recording — saves the live
    /// transcript so the meeting isn't lost.
    /// Returns false when it's already safe to exit right now.
    func beginQuitDrain() -> Bool {
        let mustDrain = TranscriptionService.hasInFlightWork || !processingIds.isEmpty || isRecordingActive
        guard mustDrain else { return false }
        guard !isQuitting else { return true }
        isQuitting = true
        liveTask?.cancel()
        drainTask?.cancel()
        overlayController.end()
        liveContext.stop()
        summary.requestAbort()
        transcription.requestAbort()
        if isRecordingActive {
            let liveFinal = liveSegments.filter { TranscriptionService.hasSpeech($0.text) }
            liveSegments = []
            let (mic, system) = engine.stop()
            if let mic { try? FileManager.default.removeItem(at: mic) }
            if let system { try? FileManager.default.removeItem(at: system) }
            if !liveFinal.isEmpty {
                let id = recordingId ?? UUID().uuidString
                store.upsert(Meeting(id: id, title: recordingCalendarTitle ?? defaultTitle(.current),
                                     createdAt: recordingStartedAt ?? Date(), durationSeconds: engine.elapsed))
                store.saveTranscript(meetingId: id, segments: liveFinal)
            }
            engine.reset()
            recordingId = nil
        }
        return true
    }

    /// Waits (bounded) until no decode is inside sherpa-onnx/WhisperKit. Requires a
    /// few consecutive clear samples — an aborting pass may enter one last decode
    /// right after a single check.
    func awaitQuitDrain() async {
        var clear = 0
        for _ in 0 ..< 80 {
            clear = TranscriptionService.hasInFlightWork ? 0 : clear + 1
            if clear >= 3 { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
