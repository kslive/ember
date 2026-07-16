import Core
import Foundation
import OSLog
import SummaryService
import SwiftUI

/// One entry of the overlay's context FEED — an APPEND-ONLY list: a block is
/// born, streams in, and is then frozen forever; the next block lands below it.
/// The meeting's storyline, scrollable in the overlay.
struct LiveContextEntry: Identifiable, Equatable {
    let id: UUID
    /// Recording-clock stamp of the block's birth.
    let at: TimeInterval
    var context: LiveContext
}

/// Generates the overlay's "what's being discussed right now" from the live
/// transcript in REAL TIME, STREAMED: replies render progressively as tokens
/// arrive (topic ~1.5s on cloud SSE, sooner locally). Single-flight latest-wins;
/// a wall-clock watchdog kills hung requests (DeepSeek keeps loaded connections
/// alive with `: keep-alive` for minutes, so idle timeouts never fire); a failed
/// cloud is retried after a cooldown instead of being written off for the whole
/// session. AI-only content — the overlay NEVER shows raw transcript lines.
@MainActor
final class LiveContextEngine: ObservableObject {
    enum Phase {
        case idle
        /// Recording, no context yet (shimmer, capped at ~8s → unavailable note).
        case waiting
        /// The feed has content.
        case active
        /// AI unavailable (no key / model missing / network) — status note.
        case degraded
    }

    @Published private(set) var entries: [LiveContextEntry] = []
    @Published private(set) var phase: Phase = .idle
    /// Surfaces the FIRST cloud failure of a session to the app (toast) — "AI
    /// unavailable" without the actual reason (401 key, 402 balance, timeout)
    /// was undebuggable for the user.
    var onCloudError: ((String) -> Void)?

    private static let log = Logger(subsystem: "com.kslff.ember", category: "live")
    /// Wall-clock cap for ONE generation pass (stream included) — the anti-hang.
    private static let passDeadline: Duration = .seconds(20)
    /// No first delta by this point → the request is stuck, kill it early.
    private static let firstTokenDeadline: Duration = .seconds(6)
    /// A failed cloud is re-tried after this cooldown (a transient network blip
    /// must not exile the fast path for the rest of the call).
    private static let cloudRetryCooldown: TimeInterval = 30
    private static let maxEntries = 200

    private let llm = LiveLLM()
    private var running = false
    private var inFlight = false
    private var latestText = ""
    /// Transcript length when the last feed block was BORN — a new block (and a
    /// new generation) happens only after `blockChars` of fresh speech, so the
    /// feed is an append-only list: no rephrase-spam, no in-place mutations.
    private var lastBlockChars = 0
    private var lastGeneratedAt = Date.distantPast
    private var cloudFailedAt: Date?
    private var cachedCloudModel: String?
    private var consecutiveFailures = 0
    private var startedAt = Date()
    private var lastLaunchAt = Date.distantPast
    private var lastCloudErrorText = ""
    private var cloudErrorToastShown = false
    private var probeInFlight = false
    /// Streaming state of the CURRENT pass. `passId` fences stale deltas — a
    /// deadline-cut detached generation must not bleed late tokens into the next
    /// pass; `currentPassEntry` pins which feed entry this pass is writing into.
    private var partialBuffer = ""
    private var lastFlush = ContinuousClock.now
    private var passId = 0
    private var currentPassEntry: UUID?
    /// Snapshot of the target block BEFORE the current pass started enriching it
    /// — each partial re-merges against this base, so streaming stays idempotent.
    private var passBase: LiveContext?
    /// Recent transcript window the CURRENT pass reads — topics that verbatim-
    /// copy it are echoes (model parroting input) and never reach the feed.
    private var currentEchoTail = ""

    /// The overlay's local model: the user's pick if downloaded, else the first
    /// downloaded allowed one (1.7B pair + 4B pair — see `allowedLocalIds`).
    private var localRepoId: String? {
        let downloaded = SummaryCatalog.all.filter { Self.isDownloaded($0.repoId) }.map(\.id)
        guard let id = LiveContextLogic.pickLocalModel(
            selected: SettingsStore.liveOverlayLocalModelId(), downloadedIds: downloaded
        ) else { return nil }
        return SummaryCatalog.spec(for: id)?.repoId
    }

    /// The overlay can actually produce content: a DeepSeek key (cloud) or a
    /// downloaded 1.7B (local). Without both the panel never shows — Settings
    /// disables the toggle and explains why.
    var canServe: Bool {
        SettingsStore.deepseekKey() != nil || localRepoId != nil
    }

    private static func isDownloaded(_ repoId: String) -> Bool {
        let dir = ModelPaths.mlxModelDir(repoId)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains("config.json") && items.contains { $0.hasSuffix(".safetensors") }
    }

    func start() async {
        entries = []
        latestText = ""
        lastBlockChars = 0
        cloudFailedAt = nil
        inFlight = false
        consecutiveFailures = 0
        partialBuffer = ""
        currentPassEntry = nil
        lastGeneratedAt = .distantPast
        startedAt = Date()
        running = true
        // NO timed fallback to "unavailable": the first local pass can honestly
        // take 10-20s (model load + first transcript + generation) and an error
        // flash before real content read as broken. The shimmer stays until the
        // first snapshot; .degraded only on CONFIRMED failure (load fail below /
        // 3 straight empty passes).
        phase = .waiting
        let route = SettingsStore.liveOverlayModelRoute()
        let hasKey = SettingsStore.deepseekKey() != nil
        LiveLog.reset()
        LiveLog.append("start route=\(route) hasKey=\(hasKey) lang=\(AppLanguage.current.rawValue)")
        // Pre-resolve the cloud model so the first pass doesn't spend its
        // first-token budget on GET /models.
        if route != "local", hasKey, cachedCloudModel == nil, let key = SettingsStore.deepseekKey() {
            Task { [weak self] in
                let model = try? await DeepSeekClient.resolveModel(
                    key: key, stored: SettingsStore.deepseekModelId(), preferFast: true
                )
                await MainActor.run {
                    self?.cachedCloudModel = model
                    LiveLog.append("cloud model resolved: \(model ?? "NONE")")
                }
            }
        }
        // Warm the 1.7B up front whenever the local path may serve the first
        // snapshot: the local route, or any key-less route (cloud without a key
        // behaves as auto → local). The system prompt is prefilled into the KV
        // cache right away so the first content pass only pays for transcript.
        let needsLocalNow = route == "local" || !hasKey
        if needsLocalNow, let repo = localRepoId {
            let ok = await llm.load(repoId: repo)
            LiveLog.append("local prewarm \(ok ? "OK" : "FAILED: \(llm.lastError ?? "-")")")
            if ok {
                await llm.prewarm(system: LiveContextLogic.systemLocal(for: AppLanguage.current))
                LiveLog.append("local system KV cached")
            } else {
                phase = .degraded
            }
        }
    }

    func stop() {
        running = false
        llm.requestAbort()
        llm.unload()
        entries = []
        phase = .idle
        LiveLog.append("stop")
    }

    /// Fed on every live-loop tick with the speaker-labeled transcript so far.
    func ingest(text: String) {
        guard running else { return }
        latestText = text
        maybeProbeCloud()
        maybeGenerate()
    }

    private func maybeGenerate() {
        guard running else { return }
        // The live transcript can be REWRITTEN shorter (re-decoded hypotheses).
        if latestText.count < lastBlockChars { lastBlockChars = latestText.count }
        // APPEND-ONLY feed pacing: a generation runs only when a block's worth of
        // NEW speech has arrived since the last block was born (~20s). Each run
        // appends ONE new list entry; nothing is ever rewritten. The first block
        // additionally waits for real material — the model only hallucinates on
        // a couple of opening sentences ("Приятствие" from ~150ch).
        let newChars = latestText.count - lastBlockChars
        guard newChars >= (entries.isEmpty ? 200 : Self.blockChars) else { return }
        // Self-heal: a pass that somehow outlived every deadline must not silence
        // the overlay forever — force the slot open and abort the stray generation.
        if inFlight, Date().timeIntervalSince(lastLaunchAt) > 45 {
            Self.log.error("in-flight pass exceeded 45s — force-releasing")
            llm.requestAbort()
            inFlight = false
        }
        // Same predicate as generate()'s useCloud: the cloud path gets live pacing
        // (1s floor, thermal ignored — it costs no local compute), the local path
        // keeps the GPU breather.
        let cloudNow = SettingsStore.liveOverlayModelRoute() != "local"
            && SettingsStore.deepseekKey() != nil && cloudFailedAt == nil
        guard LiveContextLogic.shouldGenerate(inFlight: inFlight, newChars: newChars,
                                              sinceLast: Date().timeIntervalSince(lastGeneratedAt),
                                              thermal: ProcessInfo.processInfo.thermalState,
                                              cloud: cloudNow) else { return }
        inFlight = true
        lastLaunchAt = Date()
        // Cloud gets a short tail (fast prefill; the stable system prompt +
        // append-only tail keeps DeepSeek's automatic prefix cache warm). The
        // local path receives the FULL transcript — LiveLLM manages its own
        // ANCHORED tail so its KV prefix cache survives between passes.
        let tail = String(latestText.suffix(1600))
        let full = latestText
        Task { [weak self] in
            guard let self else { return }
            await generate(tail: tail, full: full)
            inFlight = false
            lastGeneratedAt = Date()
            // Latest-wins: speech that arrived while this one was in flight starts
            // the next generation immediately.
            maybeGenerate()
        }
    }

    private func generate(tail: String, full: String) async {
        let hasKey = SettingsStore.deepseekKey() != nil
        let route = SettingsStore.liveOverlayModelRoute()
        partialBuffer = ""
        passId += 1
        currentPassEntry = nil
        passBase = nil
        // Echo guard window: a topic that verbatim-copies any recent transcript
        // run is the model parroting input — checked on partials and the final.
        currentEchoTail = String(full.suffix(4000))
        let pid = passId
        let started = ContinuousClock.now
        var raw = ""
        // A failed cloud is NEVER retried inside a content pass: each retry burned
        // the 6s first-token deadline and froze the feed right at the cooldown mark
        // (the "dies at 0:33" bug). A background probe (below) restores the cloud;
        // until then passes go straight to the local model.
        let useCloud = route != "local" && hasKey && cloudFailedAt == nil
        if useCloud {
            let system = LiveContextLogic.system(for: AppLanguage.current)
            raw = await deadlined { await self.cloudGenerate(system: system, tail: tail, pass: pid) }
            if raw.isEmpty {
                cloudFailedAt = Date()
                let reason = lastCloudErrorText.isEmpty ? "timeout (no first token)" : lastCloudErrorText
                LiveLog.append("cloud FAILED: \(reason) — switching to local, probing every \(Int(Self.cloudRetryCooldown))s")
                Self.log.warning("cloud pass failed: \(reason, privacy: .public)")
                if !cloudErrorToastShown {
                    cloudErrorToastShown = true
                    onCloudError?(String(reason.prefix(160)))
                }
            }
        }
        // Local fallback for EVERY route, "cloud" included: the overlay's job is
        // context NOW — content from the local model always beats a frozen card.
        if raw.isEmpty {
            raw = await deadlined { await self.localGenerate(full: full, pass: pid) }
        }
        guard running else { return }
        let elapsed = (ContinuousClock.now - started).components.seconds
        guard !raw.isEmpty, let visible = LiveContextLogic.visibleText(raw),
              let parsed = LiveContextLogic.parse(visible)
              .flatMap({ LiveContextLogic.rejectForeignScript($0, lang: AppLanguage.current) }) else {
            consecutiveFailures += 1
            LiveLog.append("pass #\(pid) EMPTY (fail \(consecutiveFailures)) raw=\(raw.count)ch llmErr=\(llm.lastError ?? "-")")
            if entries.isEmpty, consecutiveFailures >= 3 { phase = .degraded }
            return
        }
        guard !LiveContextLogic.isEcho(topic: parsed.topic, tail: currentEchoTail) else {
            consecutiveFailures += 1
            LiveLog.append("pass #\(pid) ECHO topic=\(parsed.topic.prefix(48))")
            if entries.isEmpty, consecutiveFailures >= 3 { phase = .degraded }
            return
        }
        consecutiveFailures = 0
        upsert(parsed)
        LiveLog.append("pass #\(pid) OK \(elapsed)s \(useCloud && cloudFailedAt == nil ? "cloud" : "local") tail=\(tail.count)ch")
        Self.log.info("pass done in \(elapsed, privacy: .public)s tail=\(tail.count, privacy: .public)")
    }

    /// Background cloud probe: after a failure, a tiny 1-token request checks the
    /// API every cooldown OFF the content path — content passes never wait on a
    /// broken cloud, and a recovered cloud is picked up automatically.
    private func maybeProbeCloud() {
        guard let failedAt = cloudFailedAt, !probeInFlight,
              Date().timeIntervalSince(failedAt) >= Self.cloudRetryCooldown,
              SettingsStore.liveOverlayModelRoute() != "local",
              let key = SettingsStore.deepseekKey() else { return }
        probeInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let ok = await withTaskGroup(of: Bool.self) { group in
                group.addTask { [cachedCloudModel] in
                    guard let model = cachedCloudModel else { return false }
                    return await (try? DeepSeekClient.chat(key: key, model: model, system: "ping", user: "ping",
                                                           maxTokens: 1, timeout: 8)) != nil
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(10))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if ok {
                cloudFailedAt = nil
                LiveLog.append("cloud probe OK — cloud restored")
            } else {
                cloudFailedAt = Date()
                LiveLog.append("cloud probe failed: \(lastCloudErrorText)")
            }
            probeInFlight = false
        }
    }

    /// Feed maintenance: the pass's first snapshot decides where it lands — the
    /// same topic refreshes the latest entry, a new topic appends. Every later
    /// partial of the SAME pass keeps updating that one entry.
    private func upsert(_ parsed: LiveContext) {
        if let id = currentPassEntry, let idx = entries.firstIndex(where: { $0.id == id }) {
            // The current pass keeps streaming into its target block. When the
            // target is an EXISTING topic block, the stream only ENRICHES it on
            // top of the pre-pass snapshot (passBase) — never rewrites history.
            let next = passBase.map { LiveContextLogic.enriched($0, with: parsed) } ?? parsed
            guard entries[idx].context != next else { return }
            entries[idx].context = next
        } else if let last = entries.last, last.context.points.count < 10,
                  LiveContextLogic.sameTopic(last.context.topic, parsed.topic) {
            // Topic unchanged → the SAME block keeps growing: old points stay,
            // new distinct ones append below («дополнять, а не стирать»), the
            // topic wording never flips. A block that already reached 10 points
            // is CLOSED — the next pass opens a continuation below it, so long
            // monologues read as chapters instead of one dump.
            passBase = last.context
            currentPassEntry = last.id
            lastBlockChars = latestText.count
            let next = LiveContextLogic.enriched(last.context, with: parsed)
            if entries[entries.count - 1].context != next {
                entries[entries.count - 1].context = next
            }
        } else {
            // New topic → new block appended; everything above is history and
            // never changes.
            passBase = nil
            lastBlockChars = latestText.count
            let entry = LiveContextEntry(id: UUID(), at: Date().timeIntervalSince(startedAt), context: parsed)
            entries.append(entry)
            if entries.count > Self.maxEntries { entries.removeFirst() }
            currentPassEntry = entry.id
        }
        phase = .active
    }

    /// A new block needs ~this much NEW transcript (≈20s of speech).
    private static let blockChars = 250

    /// Wall-clock watchdog around one generation pass: cancels the operation when
    /// the FULL deadline passes, or early when not even a first token arrived.
    /// Whatever streamed in before the cut is the result — never a hang.
    ///
    /// CRITICAL detail: the local MLX loop runs in Task.detached, which parent
    /// cancellation does NOT reach — and withTaskGroup awaits ALL children on
    /// exit. Without the explicit `llm.requestAbort()` the group would sit on the
    /// abandoned generation and the in-flight slot would never free ("model stops
    /// responding" after a few tens of seconds).
    private func deadlined(_ op: @escaping @MainActor () async -> String) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { @MainActor in await op() }
            group.addTask { @MainActor [weak self] in
                try? await Task.sleep(for: Self.firstTokenDeadline)
                if !(self?.partialBuffer.isEmpty ?? true) {
                    try? await Task.sleep(for: Self.passDeadline - Self.firstTokenDeadline)
                }
                self?.llm.requestAbort()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            llm.requestAbort()
            if let first { return first }
            let partial = partialBuffer
            Self.log.warning("pass deadline hit — partial \(partial.count, privacy: .public) chars")
            return partial
        }
    }

    /// Called with the full accumulated reply on every stream delta: throttled
    /// progressive render (≤1 flush / 100ms, never per token). The topic line is
    /// parseable long before the reply completes.
    private func applyPartial(_ text: String, pass: Int) {
        guard running, pass == passId, text.count > partialBuffer.count else { return }
        if partialBuffer.isEmpty {
            Self.log.info("first token")
            LiveLog.append("first token (pass #\(pass))")
        }
        partialBuffer = text
        let now = ContinuousClock.now
        // 250ms flush floor: every UI update reflows the card AND resizes the
        // panel (preferredContentSize) — at 10Hz that alone lagged the system.
        guard now - lastFlush > .milliseconds(250) else { return }
        lastFlush = now
        // visibleText returns nil while the model is inside an unclosed <think>
        // block — nothing showable yet (small Qwen3 emits it despite /no_think).
        guard let visible = LiveContextLogic.visibleText(text) else { return }
        // Never make the new-block-or-update decision off a HALF-STREAMED first
        // line: an incomplete topic ("Уровень из…") can't match the previous
        // entry, so every pass opened a fresh block — the same discussion stacked
        // up 4 times on the user's screen. Wait until the topic line AND the
        // first point line are complete (two newlines) before touching the feed.
        guard visible.filter({ $0 == "\n" }).count >= 2 else { return }
        if let parsed = LiveContextLogic.parse(visible)
            .flatMap({ LiveContextLogic.rejectForeignScript($0, lang: AppLanguage.current) }),
            !LiveContextLogic.isEcho(topic: parsed.topic, tail: currentEchoTail) {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { upsert(parsed) }
        }
    }

    private func cloudGenerate(system: String, tail: String, pass: Int) async -> String {
        guard let key = SettingsStore.deepseekKey() else { return "" }
        do {
            if cachedCloudModel == nil {
                // Prewarm in start() usually beat us here; re-resolve as a fallback
                // (DeepSeek retires ids; thinking models are useless live — ~55s TTFT).
                cachedCloudModel = try await DeepSeekClient.resolveModel(
                    key: key, stored: SettingsStore.deepseekModelId(), preferFast: true
                )
            }
            guard let model = cachedCloudModel else { return "" }
            return try await DeepSeekClient.chatStream(key: key, model: model, system: system, user: tail,
                                                       maxTokens: 144) { [weak self] text in
                Task { @MainActor in self?.applyPartial(text, pass: pass) }
            }
        } catch {
            let reason = (error as? DeepSeekClient.ClientError)?.errorDescription
                ?? error.localizedDescription
            lastCloudErrorText = reason
            Self.log.warning("cloud error: \(reason, privacy: .public)")
            return ""
        }
    }

    private func localGenerate(full: String, pass: Int) async -> String {
        if !llm.isReady {
            guard let repo = localRepoId, await llm.load(repoId: repo) else {
                if entries.isEmpty { phase = .degraded }
                return ""
            }
        }
        let system = LiveContextLogic.systemLocal(for: AppLanguage.current)
        let out = await llm.generate(system: system, transcript: full) { [weak self] text in
            Task { @MainActor in self?.applyPartial(text, pass: pass) }
        }
        if let stats = llm.lastPassStats { LiveLog.append("local \(stats)") }
        return out
    }
}

/// Plain-file diagnostics for the overlay (`Application Support/Ember/live.log`,
/// reset on every recording): the system log store proved unreadable on the
/// user's machine, and without WHY (cloud error text, local load failure, pass
/// timings) the overlay was undebuggable. Tiny appends, main-actor only.
@MainActor
enum LiveLog {
    private static let url = ModelPaths.appSupport().appendingPathComponent("live.log")
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func reset() {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    static func append(_ s: String) {
        let line = "\(df.string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
