import Core
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Dedicated MLX container for the live-context overlay (Qwen3 1.7B). Kept
/// SEPARATE from `SummaryService`: the overlay generates continuously during a
/// call, while SummaryService loads the (often larger) post-meeting model after
/// the call — sharing one container would make each evict the other. Loaded at
/// recording start when the local route is active, unloaded at stop BEFORE the
/// full summary runs, so the RAM is free again.
@MainActor
public final class LiveLLM: ObservableObject {
    @Published public private(set) var isReady = false
    private var container: ModelContainer?
    /// Which repo is loaded — picks the bench-tuned sampling per model family.
    private var loadedRepoId: String?

    /// Token-level interrupt for the DETACHED generation loop: parent-task
    /// cancellation does NOT propagate into Task.detached, so a watchdog that
    /// gave up on a pass must abort it explicitly or the awaiter hangs until the
    /// generation finishes on its own (the "stops responding" failure mode).
    public private(set) nonisolated(unsafe) var abortRequested = false
    /// Last load/generation failure, for the overlay's diagnostics log.
    public private(set) nonisolated(unsafe) var lastError: String?
    /// One-line stats of the last pass ("P=812 delta=41tok 1.24s") for live.log —
    /// the proof that the prefix cache actually hits.
    public private(set) nonisolated(unsafe) var lastPassStats: String?

    /// KV PREFIX CACHE reused across passes. The transcript is append-only, so
    /// every pass used to re-prefill the same ~1000 prompt tokens from scratch
    /// (~1s of the ~3s pass on 1.7B). Instead the layer caches plus the raw token
    /// render of the last prompt are kept; the next pass diffs token arrays,
    /// trims the cache tail (old answer + diverged suffix — an O(1) offset
    /// rollback) and prefills ONLY the new transcript tokens. State is touched
    /// exclusively inside `container.perform` (passes are single-flight).
    /// kvBits is deliberately NOT set: TokenIterator swaps quantized caches into
    /// ITS OWN array copy, silently orphaning an externally retained cache.
    private nonisolated(unsafe) var kvCache: [KVCache]?
    private nonisolated(unsafe) var cachedTokens: [Int] = []
    /// Char offset where the ANCHORED transcript tail begins. A sliding
    /// suffix(1600) would shift the head every pass and break the prefix match.
    private nonisolated(unsafe) var anchorChars = 0
    /// Plain fp16 KV for 1.7B ≈ 115 KB/token → re-anchor near 3000 tokens
    /// (~350 MB peak, freed by the reset) at the cost of one cold prefill.
    private nonisolated static let reanchorTokens = 3000
    private nonisolated static let tailChars = 1600

    public nonisolated func requestAbort() {
        abortRequested = true
    }

    public init() {}

    /// Loads the live model if it's downloaded and the machine can hold it.
    /// Returns false (silently) otherwise — the overlay degrades, never blocks.
    @discardableResult
    public func load(repoId: String) async -> Bool {
        if container != nil { return true }
        let needGB = SummaryCatalog.all.first { $0.repoId == repoId }?.ramHintGB ?? 8
        let physGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        guard SummaryService.hasEnoughRAM(minGB: needGB, physicalGB: physGB) else {
            lastError = "low-memory (\(needGB)GB needed)"
            return false
        }
        let dir = ModelPaths.mlxModelDir(repoId)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              items.contains("config.json"), items.contains(where: { $0.hasSuffix(".safetensors") })
        else {
            lastError = "model not downloaded (\(repoId))"
            return false
        }
        do {
            MLX.Memory.cacheLimit = 128 * 1024 * 1024
            resetPromptCache()
            container = try await LLMModelFactory.shared.loadContainer(from: dir, using: EmberTokenizerLoader())
            loadedRepoId = repoId
            isReady = true
            lastError = nil
            return true
        } catch {
            container = nil
            isReady = false
            lastError = String(describing: error)
            return false
        }
    }

    public func unload() {
        container = nil
        loadedRepoId = nil
        isReady = false
        resetPromptCache()
        MLX.Memory.clearCache()
    }

    private nonisolated func resetPromptCache() {
        kvCache = nil
        cachedTokens = []
        anchorChars = 0
    }

    /// Prefills the stable system prompt into the KV cache right after load, so
    /// the FIRST content pass only pays for the transcript tokens.
    public func prewarm(system: String) async {
        _ = await generate(system: system, transcript: "", maxTokens: 1)
    }

    /// One short live-context completion streamed via `onText` (full accumulated
    /// text every few chunks — the topic line renders long before the pass ends).
    /// `transcript` is the FULL live transcript; the anchored tail is managed
    /// here (see `anchorChars`). Empty string on any failure — the overlay keeps
    /// its last snapshot.
    public func generate(system: String, transcript: String, maxTokens: Int? = nil,
                         onText: (@Sendable (String) -> Void)? = nil) async -> String {
        guard let container else { return "" }
        abortRequested = false
        let sampling = LiveContextLogic.liveSampling(repoId: loadedRepoId ?? "1.7B")
        var params = GenerateParameters(
            maxTokens: maxTokens ?? Self.envInt("EMBER_LIVE_MAXTOK") ?? 110,
            temperature: Self.envFloat("EMBER_LIVE_TEMP") ?? sampling.temperature,
            topP: Self.envFloat("EMBER_LIVE_TOPP") ?? sampling.topP,
            prefillStepSize: 1024
        )
        let topK = Self.envInt("EMBER_LIVE_TOPK") ?? sampling.topK
        if topK > 0 { params.topK = topK }
        params.repetitionPenalty = 1.1
        params.repetitionContextSize = 128
        do {
            return try await Task.detached(priority: .utility) {
                try await container.perform { (ctx: ModelContext) -> String in
                    try await self.runPass(ctx: ctx, system: system, transcript: transcript,
                                           params: params, onText: onText)
                }
            }.value
        } catch {
            lastError = String(describing: error)
            resetPromptCache()
            return ""
        }
    }

    /// The pass body (runs inside container.perform, off the main thread).
    private nonisolated func runPass(ctx: ModelContext, system: String, transcript: String,
                                     params: GenerateParameters,
                                     onText: (@Sendable (String) -> Void)?) async throws -> String {
        let t0 = ContinuousClock.now
        if ProcessInfo.processInfo.environment["EMBER_LIVE_NOCACHE"] == "1" {
            resetPromptCache()
        }
        // First pass, or the live tail was rewritten SHORTER (re-decoded
        // hypotheses) → drop the cache and re-anchor near the end.
        if kvCache == nil || transcript.count < anchorChars {
            resetPromptCache()
            anchorChars = max(0, transcript.count - Self.tailChars)
        }
        func renderTokens() throws -> [Int] {
            let tail = String(transcript.dropFirst(anchorChars))
            let messages: [[String: any Sendable]] = [
                ["role": "system", "content": system],
                ["role": "user", "content": tail]
            ]
            // enable_thinking=false switches Qwen3's thinking off at the chat-
            // template level (the "/no_think" soft hint was ignored by 1.7B,
            // burning the whole token budget inside an unclosed <think>).
            return try ctx.tokenizer.applyChatTemplate(
                messages: messages, tools: nil,
                additionalContext: ["enable_thinking": false]
            )
        }
        var tokens = try renderTokens()
        if tokens.count > Self.reanchorTokens {
            resetPromptCache()
            anchorChars = max(0, transcript.count - Self.tailChars)
            tokens = try renderTokens()
        }
        var cache: [KVCache]
        var prefix: Int
        if let existing = kvCache {
            cache = existing
            prefix = Self.commonPrefix(cachedTokens, tokens)
            // Never feed an empty delta — the iterator needs ≥1 token to step from.
            if prefix >= tokens.count { prefix = max(0, tokens.count - 1) }
            let excess = (cache.first?.offset ?? 0) - prefix
            if excess > 0, trimPromptCache(cache, numTokens: excess) < excess {
                cache = ctx.model.newCache(parameters: params)
                prefix = 0
            }
        } else {
            cache = ctx.model.newCache(parameters: params)
            prefix = 0
        }
        let delta = Array(tokens[prefix...])
        let input = LMInput(tokens: MLXArray(delta))
        var text = ""
        var sinceFlush = 0
        for await generation in try MLXLMCommon.generate(
            input: input, cache: cache, parameters: params, context: ctx
        ) {
            if abortRequested { break }
            if let piece = generation.chunk {
                text += piece
                sinceFlush += 1
                // Flush every ~3 chunks (mlx-swift-examples' display cadence) —
                // never per token.
                if sinceFlush >= 3 {
                    sinceFlush = 0
                    onText?(text)
                }
            }
        }
        onText?(text)
        kvCache = cache
        cachedTokens = tokens
        let dt = (ContinuousClock.now - t0).components
        let secs = Double(dt.seconds) + Double(dt.attoseconds) / 1e18
        lastPassStats = "P=\(prefix) delta=\(delta.count)tok \(String(format: "%.2f", secs))s"
        return text
    }

    private nonisolated static func commonPrefix(_ a: [Int], _ b: [Int]) -> Int {
        var i = 0
        let n = min(a.count, b.count)
        while i < n, a[i] == b[i] {
            i += 1
        }
        return i
    }

    /// Bench seat (EMBER_LIVE_*): parameter overrides for scripts/live-bench —
    /// unset in production, so shipped behavior is byte-identical.
    private nonisolated static func envFloat(_ key: String) -> Float? {
        ProcessInfo.processInfo.environment[key].flatMap(Float.init)
    }

    private nonisolated static func envInt(_ key: String) -> Int? {
        ProcessInfo.processInfo.environment[key].flatMap(Int.init)
    }
}
