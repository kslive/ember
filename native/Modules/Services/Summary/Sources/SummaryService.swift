import Combine
import Core
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

public enum SummaryStatus: Equatable {
    case idle
    case loading
    case ready
    case generating
    case error(String)
}

/// In-process Apple MLX summarization (Qwen3 4-bit). Local + offline.
@MainActor
public final class SummaryService: ObservableObject {
    @Published public private(set) var status: SummaryStatus = .idle
    /// Per-model download state (keyed by SummaryCatalog id, e.g. "qwen3:8b").
    @Published public private(set) var states: [String: ModelDownloadState] = [:]

    private var container: ModelContainer?
    private var loadedRepo: String?
    private var loadedContextTokens = 8192
    private var tasks: [String: Task<Void, Never>] = [:]
    private var idleUnloadTask: Task<Void, Never>?

    public init() {
        refreshStates()
    }

    public var isReady: Bool {
        container != nil
    }

    public func refreshStates() {
        for m in SummaryCatalog.all {
            if case .downloading = states[m.id] { continue }
            states[m.id] = isDownloaded(m.repoId) ? .ready : .absent
        }
    }

    public func isDownloaded(_ repoId: String) -> Bool {
        let dir = ModelPaths.mlxModelDir(repoId)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains("config.json") && items.contains { $0.hasSuffix(".safetensors") }
    }

    public var isDownloading: Bool {
        tasks.values.contains { !$0.isCancelled }
    }

    /// Starts a cancellable MLX repo download (no RAM load) with byte-accurate
    /// progress (disk size vs catalog size).
    public func startDownload(id: String, repoId: String) {
        guard tasks[id] == nil else { return }
        if isDownloaded(repoId) { states[id] = .ready; return }
        states[id] = .downloading(0)
        tasks[id] = Task { @MainActor [weak self] in
            await self?.runDownload(id: id, repoId: repoId)
            self?.tasks[id] = nil
        }
    }

    public func cancelDownload(id: String, repoId: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        try? FileManager.default.removeItem(at: ModelPaths.mlxModelDir(repoId))
        states[id] = isDownloaded(repoId) ? .ready : .absent
    }

    public func cancelAllDownloads() {
        for (id, t) in tasks {
            t.cancel()
            if let repo = SummaryCatalog.spec(for: id)?.repoId {
                try? FileManager.default.removeItem(at: ModelPaths.mlxModelDir(repo))
            }
            states[id] = .absent
        }
        tasks.removeAll()
    }

    private func runDownload(id: String, repoId: String) async {
        let expected = Int64(SummaryCatalog.spec(for: id)?.sizeMB ?? 1) * 1_000_000
        let dir = ModelPaths.mlxModelDir(repoId)
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let size = ModelPaths.dirSize(dir)
                let frac = expected > 0 ? min(0.99, Double(size) / Double(expected)) : 0
                await MainActor.run { [weak self] in
                    if case .downloading? = self?.states[id] { self?.states[id] = .downloading(frac) }
                }
            }
        }
        defer { poll.cancel() }
        do {
            _ = try await downloadModel(hub: defaultHubApi, configuration: ModelConfiguration(id: repoId)) { _ in }
            if Task.isCancelled { return }
            states[id] = isDownloaded(repoId) ? .ready : .failed("incomplete")
        } catch {
            if Task.isCancelled { return }
            states[id] = isDownloaded(repoId) ? .ready : .failed(error.localizedDescription)
        }
    }

    public func delete(id: String, repoId: String) {
        cancelDownload(id: id, repoId: repoId)
        try? FileManager.default.removeItem(at: ModelPaths.mlxModelDir(repoId))
        states[id] = .absent
        if loadedRepo == repoId { container = nil; loadedRepo = nil; status = .idle }
    }

    /// Frees the loaded MLX weights + Metal cache. Without this the model lived in
    /// RAM forever after a summary — gigabytes resident at idle.
    public func unload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        container = nil
        loadedRepo = nil
        status = .idle
        MLX.GPU.clearCache()
    }

    /// Auto-unload after `seconds` of idle; any new load/generation cancels it.
    public func scheduleIdleUnload(seconds: UInt64 = 300) {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.unload()
        }
    }

    public func ensureLoaded(repoId: String) async {
        idleUnloadTask?.cancel()
        if loadedRepo == repoId, container != nil { return }
        status = .loading
        let needGB = SummaryCatalog.all.first { $0.repoId == repoId }?.ramHintGB ?? 4
        let physGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if !Self.hasEnoughRAM(minGB: needGB, physicalGB: physGB) {
            status = .error("low-memory")
            return
        }
        do {
            // Cap MLX's Metal buffer cache. Without a limit MLX caches EVERY
            // intermediate buffer of a long generation and never returns the memory —
            // gigabytes of pressure that swapped the whole Mac during long-meeting
            // summaries. Apple's own LLMEval sets a cache limit for exactly this.
            MLX.GPU.set(cacheLimit: 128 * 1024 * 1024)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: repoId)
            )
            self.container = container
            loadedRepo = repoId
            loadedContextTokens = SummaryCatalog.all.first { $0.repoId == repoId }?.contextTokens ?? 8192
            status = .ready
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Can this machine run a model that needs `minGB` of RAM? Gate on PHYSICAL
    /// (installed) memory, NOT momentary "reclaimable" free memory: on macOS the OS
    /// keeps RAM active/compressed and frees it on demand, so a reclaimable heuristic
    /// under-reports and falsely blocked capable Macs (even 32–64 GB). Matches how
    /// LM Studio / Ollama gate. The 0.5 slack absorbs the small reserved slice so a
    /// 16 GB Mac clears a 16 GB requirement.
    nonisolated static func hasEnoughRAM(minGB: Int, physicalGB: Double) -> Bool {
        physicalGB >= Double(minGB) - 0.5
    }

    /// Generates a Markdown summary in the given language code (en/ru/zh/…). A
    /// transcript that wouldn't fit the model's context is summarized in chunks
    /// (map) then reduced — otherwise the KV cache would silently drop the middle
    /// of the meeting (the smallest-context model, 8B/16k, is hit first).
    public func summarize(transcript: String, languageCode: String) async -> String {
        guard container != nil else { return "" }
        status = .generating
        idleUnloadTask?.cancel()
        defer {
            MLX.GPU.clearCache()
            scheduleIdleUnload()
        }

        let maxGen = 6144
        let budgetTokens = Self.promptBudgetTokens(context: loadedContextTokens, maxGen: maxGen)
        let budgetChars = budgetTokens * 2

        let raw: String
        if transcript.count <= budgetChars {
            raw = await generateOnce(system: SummaryPrompts.system(language: languageCode),
                                     transcript: transcript, languageCode: languageCode, maxTokens: maxGen)
        } else {
            var notes: [String] = []
            for chunk in Self.splitChunks(transcript, maxChars: budgetChars) {
                if Task.isCancelled { break }
                let n = await ThinkStripper.strip(generateOnce(
                    system: SummaryPrompts.chunkSystem(language: languageCode),
                    transcript: chunk, languageCode: languageCode, maxTokens: 1024
                ))
                if !n.isEmpty { notes.append(n) }
            }
            raw = notes.isEmpty ? "" : await generateOnce(
                system: SummaryPrompts.system(language: languageCode),
                transcript: notes.joined(separator: "\n"), languageCode: languageCode, maxTokens: maxGen
            )
        }

        guard !raw.isEmpty else {
            if case .error = status {} else { status = .error("empty") }
            return ""
        }
        status = .ready
        return SummarySanitize.clean(ThinkStripper.strip(raw), transcript: transcript)
    }

    /// Cloud (DeepSeek) summary path — same prompts, no local models touched. Throws
    /// on ANY failure so the caller falls back to the local MLX path. DeepSeek's 1M
    /// context fits any meeting in one pass (400k-char cap is a safety net only).
    public func summarizeCloud(key: String, model: String, transcript: String, languageCode: String) async throws -> String {
        status = .generating
        defer { if case .generating = status { status = container != nil ? .ready : .idle } }
        let capped = String(transcript.suffix(400_000))
        let raw = try await DeepSeekClient.chat(
            key: key, model: model,
            system: SummaryPrompts.system(language: languageCode),
            user: SummaryPrompts.user(transcript: capped, language: languageCode)
        )
        let md = SummarySanitize.clean(ThinkStripper.strip(raw), transcript: transcript)
        guard !md.isEmpty else { throw DeepSeekClient.ClientError.emptyResponse }
        return md
    }

    /// Prompt-token budget for ONE generation pass, capped at 12k for EVERY model.
    /// The uncapped budget (context − maxGen − headroom = up to ~33.6k tokens) let an
    /// 80-minute transcript run as a single pass: a multi-GB KV cache (prefill
    /// accumulates UNquantized) + minutes of uninterrupted 100% GPU — the whole Mac
    /// lagged. Capped, long meetings fall into the existing map-reduce chunking:
    /// small KV peaks, short GPU bursts, the UI breathes between chunks.
    nonisolated static func promptBudgetTokens(context: Int, maxGen: Int) -> Int {
        max(2000, min(context - maxGen - 1200, 12000))
    }

    /// One MLX generation pass. Uses `KVCacheSimple` (NO `maxKVSize`) so the
    /// `kvBits` cache quantization actually applies — `maybeQuantizeKVCache` skips
    /// rotating caches — keeping memory bounded WITHOUT silently dropping context.
    /// Runs detached at `.utility` priority so the tokenizer/detokenizer CPU work
    /// never competes with the main thread.
    private func generateOnce(system: String, transcript: String, languageCode: String, maxTokens: Int) async -> String {
        guard let container else { return "" }
        let user = SummaryPrompts.user(transcript: transcript, language: languageCode) + "\n\n/no_think"
        let params = GenerateParameters(
            maxTokens: maxTokens, kvBits: 8, quantizedKVStart: 256, temperature: 0.7, topP: 0.8
        )
        do {
            return try await Task.detached(priority: .utility) {
                try await container.perform { (ctx: ModelContext) -> String in
                    let input = try await ctx.processor.prepare(
                        input: UserInput(chat: [.system(system), .user(user)])
                    )
                    var detok = NaiveStreamingDetokenizer(tokenizer: ctx.tokenizer)
                    var text = ""
                    _ = try MLXLMCommon.generate(
                        input: input, parameters: params, context: ctx
                    ) { (tokens: [Int]) -> GenerateDisposition in
                        guard let last = tokens.last else { return .more }
                        detok.append(token: last)
                        if let piece = detok.next(), !piece.isEmpty { text += piece }
                        return .more
                    }
                    return text
                }
            }.value
        } catch {
            status = .error(error.localizedDescription)
            return ""
        }
    }

    /// Splits a transcript into chunks of at most `maxChars`, breaking on line
    /// boundaries (one transcript segment per line) so words aren't cut mid-token.
    nonisolated static func splitChunks(_ text: String, maxChars: Int) -> [String] {
        guard maxChars > 0 else { return [text] }
        var chunks: [String] = []
        var cur = ""
        for line in text.components(separatedBy: "\n") {
            if !cur.isEmpty, cur.count + line.count + 1 > maxChars {
                chunks.append(cur); cur = ""
            }
            cur += cur.isEmpty ? line : "\n" + line
        }
        if !cur.isEmpty { chunks.append(cur) }
        return chunks
    }

    /// Summary language = the user-selected UI language. We deliberately do NOT
    /// auto-detect: language recognizers frequently mistake short Russian transcripts
    /// for Ukrainian, producing summaries in the wrong language.
    public nonisolated static func summaryLanguageCode(selected: AppLanguage) -> String {
        selected.rawValue
    }
}

/// Removes Qwen3 `<think>…</think>` reasoning blocks and stray tags.
enum ThinkStripper {
    static func strip(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "(?is)<think>.*?</think>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "<think>", with: "")
        out = out.replacingOccurrences(of: "</think>", with: "")
        out = out.replacingOccurrences(of: "/no_think", with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
