import Combine
import Core
import Foundation
import WhisperKit

public enum TranscriptionStatus: Equatable {
    case idle
    case loading
    case ready
    case transcribing
    case error(String)
}

/// Wraps WhisperKit: loads a CoreML Whisper model and transcribes audio files
/// into transcript segments. Local + offline.
@MainActor
public final class TranscriptionService: ObservableObject {
    @Published public private(set) var status: TranscriptionStatus = .idle
    /// Per-model download state (keyed by WhisperKit variant id). Drives the UI.
    @Published public private(set) var states: [String: ModelDownloadState] = [:]

    private var kit: WhisperKit?
    private var loadedModel: String?
    private var tasks: [String: Task<Void, Never>] = [:]

    public init() {
        refreshStates()
    }

    public var isReady: Bool {
        kit != nil
    }

    /// Re-scans disk and updates `states` for every catalog model.
    public func refreshStates() {
        for m in TranscriptionCatalog.all {
            if case .downloading = states[m.id] { continue }
            states[m.id] = isDownloaded(m.id) ? .ready : .absent
        }
    }

    public func isDownloaded(_ variant: String) -> Bool {
        let dir = ModelPaths.whisperModelDir(variant)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        func has(_ prefix: String) -> Bool {
            items.contains { $0.hasPrefix(prefix) && ($0.hasSuffix(".mlmodelc") || $0.hasSuffix(".mlpackage")) }
        }
        return has("MelSpectrogram") && has("AudioEncoder") && has("TextDecoder")
    }

    public var isDownloading: Bool {
        tasks.values.contains { !$0.isCancelled }
    }

    /// Starts a cancellable download with byte-accurate progress (disk size vs the
    /// catalog size — the Hub's own progress reports file count, not bytes, so it
    /// jumps to 50% instantly).
    public func startDownload(_ variant: String) {
        guard tasks[variant] == nil else { return }
        if isDownloaded(variant) { states[variant] = .ready; return }
        states[variant] = .downloading(0)
        tasks[variant] = Task { @MainActor [weak self] in
            await self?.runDownload(variant)
            self?.tasks[variant] = nil
        }
    }

    public func cancelDownload(_ variant: String) {
        tasks[variant]?.cancel()
        tasks[variant] = nil
        try? FileManager.default.removeItem(at: ModelPaths.whisperModelDir(variant))
        states[variant] = isDownloaded(variant) ? .ready : .absent
    }

    public func cancelAllDownloads() {
        for (id, t) in tasks {
            t.cancel()
            try? FileManager.default.removeItem(at: ModelPaths.whisperModelDir(id))
            states[id] = .absent
        }
        tasks.removeAll()
    }

    private func runDownload(_ variant: String) async {
        let expected = Int64(TranscriptionCatalog.spec(for: variant)?.sizeMB ?? 1) * 1_000_000
        let dir = ModelPaths.whisperModelDir(variant)
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let size = ModelPaths.dirSize(dir)
                let frac = expected > 0 ? min(0.99, Double(size) / Double(expected)) : 0
                await MainActor.run { [weak self] in
                    if case .downloading? = self?.states[variant] { self?.states[variant] = .downloading(frac) }
                }
            }
        }
        defer { poll.cancel() }
        do {
            _ = try await WhisperKit.download(variant: variant, downloadBase: ModelPaths.whisperDownloadBase, progressCallback: { _ in })
            if Task.isCancelled { return }
            states[variant] = isDownloaded(variant) ? .ready : .failed("incomplete")
        } catch {
            if Task.isCancelled { return }
            states[variant] = isDownloaded(variant) ? .ready : .failed(error.localizedDescription)
        }
    }

    public func delete(_ variant: String) {
        cancelDownload(variant)
        try? FileManager.default.removeItem(at: ModelPaths.whisperModelDir(variant))
        states[variant] = .absent
        if loadedModel == variant { kit = nil; loadedModel = nil; status = .idle }
    }

    /// Loads (downloading on first use) the given WhisperKit model.
    public func ensureLoaded(model: String) async {
        if loadedModel == model, kit != nil { return }
        status = .loading
        do {
            let config = WhisperKitConfig(model: model, downloadBase: ModelPaths.whisperDownloadBase)
            let kit = try await WhisperKit(config)
            self.kit = kit
            loadedModel = model
            states[model] = .ready
            status = .ready
        } catch {
            kit = nil
            loadedModel = nil
            status = .error(error.localizedDescription)
        }
    }

    /// Frees the loaded WhisperKit model to reclaim RAM (e.g. before loading the
    /// large MLX summary model on memory-tight machines). The next transcription
    /// reloads it. No-op while actively transcribing.
    public func unload() {
        if case .transcribing = status { return }
        kit = nil
        loadedModel = nil
        status = .idle
    }

    /// Transcribes a 16 kHz mono sample array (used for live transcription).
    /// Does not change `status` so it can run alongside recording.
    /// `strict` enables WhisperKit's no-speech/low-confidence thresholds. The LIVE pass
    /// uses `strict: false` — those thresholds make WhisperKit return NOTHING on the
    /// short 1.8s growing-window clips; live relies on the caller's RMS gate to skip
    /// silence instead. The FINAL pass (long audio) uses `strict: true`.
    public func transcribeSamples(_ samples: [Float], meetingId: String, language: String?, strict: Bool = false) async -> [TranscriptSegment] {
        guard let kit, !samples.isEmpty else { return [] }
        do {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: Self.decodeOptions(language: language, strict: strict))
            return results.flatMap(\.segments).compactMap { s in
                let text = Self.cleanText(s.text)
                guard !text.isEmpty, !Self.isHallucination(text) else { return nil }
                return TranscriptSegment(meetingId: meetingId, text: text,
                                         startSeconds: Double(s.start), endSeconds: Double(s.end))
            }
        } catch {
            return []
        }
    }

    /// DecodingOptions. When `strict`, enables no-speech / low-confidence / repetition
    /// thresholds (kills "[музыка]"/subtitle hallucinations on silence in the FINAL,
    /// long-audio pass). LIVE passes `strict: false` — on short clips those thresholds
    /// make WhisperKit return nothing, so live relies on the RMS gate for silence.
    nonisolated static func decodeOptions(language: String?, strict: Bool = true) -> DecodingOptions {
        var o = DecodingOptions()
        o.skipSpecialTokens = true
        if strict {
            o.noSpeechThreshold = 0.6
            o.logProbThreshold = -1.0
            o.compressionRatioThreshold = 2.4
            o.chunkingStrategy = .vad
            o.temperatureFallbackCount = 2
        }
        if let language { o.language = language }
        return o
    }

    /// Strips WhisperKit control/timestamp tokens (`<|...|>`) that can leak into
    /// segment text and trims whitespace.
    nonisolated static func cleanText(_ s: String) -> String {
        s.replacingOccurrences(of: "<\\|[^>]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a segment is a well-known Whisper silence/non-speech hallucination
    /// ("[музыка]", "Редактор субтитров …", "Продолжение следует", "Subscribe", …) —
    /// these are produced on silent/near-silent audio and must never reach the UI.
    private static let hallucinationMarkers = [
        "музыка", "music", "аплодисменты", "applause",
        "субтитры", "субтитров", "редактор субтитров", "корректор",
        "продолжение следует", "спасибо за просмотр", "спасибо за внимание",
        "подписывайтесь", "thanks for watching", "subscribe"
    ]
    nonisolated static func isHallucination(_ text: String) -> Bool {
        let trimSet = CharacterSet(charactersIn: " []()【】.,!?…—-*\"'«»\n\t")
        let n = text.lowercased().trimmingCharacters(in: trimSet)
        for m in hallucinationMarkers {
            if n == m { return true }
            if n.hasPrefix(m), n.count <= m.count + 18 { return true }
        }
        return false
    }

    /// Transcribes an audio file into segments. The empty-result mixed fallback in
    /// AppModel.process passes `strict: false` — if both strict per-channel passes
    /// already rejected everything, re-running the mix with the same strict thresholds
    /// would reject it too.
    public func transcribe(url: URL, meetingId: String, language: String?, strict: Bool = false) async -> [TranscriptSegment] {
        guard let kit else { return [] }
        status = .transcribing
        do {
            let results: [TranscriptionResult] = try await kit.transcribe(audioPath: url.path, decodeOptions: Self.decodeOptions(language: language, strict: strict))
            var segments: [TranscriptSegment] = []
            for result in results {
                for s in result.segments {
                    let text = Self.cleanText(s.text)
                    guard !text.isEmpty, !Self.isHallucination(text) else { continue }
                    segments.append(TranscriptSegment(
                        meetingId: meetingId,
                        text: text,
                        startSeconds: Double(s.start),
                        endSeconds: Double(s.end)
                    ))
                }
            }
            status = .ready
            return segments
        } catch {
            status = .error(error.localizedDescription)
            return []
        }
    }
}
