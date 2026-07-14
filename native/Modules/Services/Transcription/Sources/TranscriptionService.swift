import AVFAudio
import Combine
import Core
import Foundation
import SherpaOnnx
import WhisperKit

/// Serialized, Sendable holder for a sherpa-onnx recognizer (GigaAM). The C-backed
/// recognizer isn't documented as reentrant, and the final pass decodes mic+system
/// CONCURRENTLY — the lock turns that into two sequential CPU decodes.
private final class GigaBox: @unchecked Sendable {
    private let rec: SherpaOnnxOfflineRecognizer
    private let lock = NSLock()

    init(rec: SherpaOnnxOfflineRecognizer) {
        self.rec = rec
    }

    struct Decoded {
        let text: String
        let tokens: [String]
        let timestamps: [Float]
    }

    func decode(_ samples: [Float]) -> Decoded {
        lock.lock()
        defer { lock.unlock() }
        let r = rec.decode(samples: samples, sampleRate: 16000)
        return Decoded(text: r.text, tokens: r.tokens, timestamps: r.timestamps)
    }
}

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
    private var giga: GigaBox?
    private var loadedModel: String?
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Engine-aware on-disk location for a catalog model.
    private static func modelDir(_ variant: String) -> URL {
        TranscriptionCatalog.engine(for: variant) == .gigaAM
            ? ModelPaths.gigaAMModelDir(variant)
            : ModelPaths.whisperModelDir(variant)
    }

    public init() {
        refreshStates()
    }

    public var isReady: Bool {
        kit != nil || giga != nil
    }

    /// Re-scans disk and updates `states` for every catalog model.
    public func refreshStates() {
        for m in TranscriptionCatalog.all {
            if case .downloading = states[m.id] { continue }
            states[m.id] = isDownloaded(m.id) ? .ready : .absent
        }
    }

    public func isDownloaded(_ variant: String) -> Bool {
        if TranscriptionCatalog.engine(for: variant) == .gigaAM {
            let dir = ModelPaths.gigaAMModelDir(variant)
            return GigaAMFiles.names.allSatisfy {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
        }
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
        try? FileManager.default.removeItem(at: Self.modelDir(variant))
        states[variant] = isDownloaded(variant) ? .ready : .absent
    }

    public func cancelAllDownloads() {
        for (id, t) in tasks {
            t.cancel()
            try? FileManager.default.removeItem(at: Self.modelDir(id))
            states[id] = .absent
        }
        tasks.removeAll()
    }

    private func runDownload(_ variant: String) async {
        let expected = Int64(TranscriptionCatalog.spec(for: variant)?.sizeMB ?? 1) * 1_000_000
        let dir = Self.modelDir(variant)
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
            if TranscriptionCatalog.engine(for: variant) == .gigaAM {
                try await Self.downloadGigaFiles(to: dir)
            } else {
                _ = try await WhisperKit.download(variant: variant, downloadBase: ModelPaths.whisperDownloadBase, progressCallback: { _ in })
            }
            if Task.isCancelled { return }
            states[variant] = isDownloaded(variant) ? .ready : .failed("incomplete")
        } catch {
            if Task.isCancelled { return }
            states[variant] = isDownloaded(variant) ? .ready : .failed(error.localizedDescription)
        }
    }

    /// Plain sequential HuggingFace file downloads (encoder/decoder/joiner/tokens);
    /// progress comes from the generic dirSize poll like every other model.
    private nonisolated static func downloadGigaFiles(to dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in GigaAMFiles.names {
            let dest = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            try Task.checkCancellation()
            let (tmp, resp) = try await URLSession.shared.download(from: GigaAMFiles.url(name))
            if let http = resp as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }

    public func delete(_ variant: String) {
        cancelDownload(variant)
        try? FileManager.default.removeItem(at: Self.modelDir(variant))
        states[variant] = .absent
        if loadedModel == variant { kit = nil; giga = nil; loadedModel = nil; status = .idle }
    }

    /// Loads (downloading on first use) the given catalog model on its engine.
    public func ensureLoaded(model: String) async {
        if loadedModel == model, isReady { return }
        status = .loading
        if TranscriptionCatalog.engine(for: model) == .gigaAM {
            await ensureGigaLoaded(model: model)
            return
        }
        do {
            let config = WhisperKitConfig(model: model, downloadBase: ModelPaths.whisperDownloadBase)
            let kit = try await WhisperKit(config)
            self.kit = kit
            giga = nil
            loadedModel = model
            states[model] = .ready
            status = .ready
        } catch {
            kit = nil
            loadedModel = nil
            status = .error(error.localizedDescription)
        }
    }

    /// Builds the sherpa-onnx recognizer off the main thread (reads ~230 MB of ONNX
    /// and builds CPU sessions). Downloads the files first when missing.
    private func ensureGigaLoaded(model: String) async {
        if !isDownloaded(model) {
            do {
                try await Self.downloadGigaFiles(to: Self.modelDir(model))
            } catch {
                status = .error(error.localizedDescription)
                return
            }
        }
        let dir = Self.modelDir(model)
        let box = await Task.detached(priority: .userInitiated) { () -> GigaBox? in
            var config = sherpaOnnxOfflineRecognizerConfig(
                featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 64),
                modelConfig: sherpaOnnxOfflineModelConfig(
                    tokens: dir.appendingPathComponent("tokens.txt").path,
                    transducer: sherpaOnnxOfflineTransducerModelConfig(
                        encoder: dir.appendingPathComponent("encoder.int8.onnx").path,
                        decoder: dir.appendingPathComponent("decoder.onnx").path,
                        joiner: dir.appendingPathComponent("joiner.onnx").path
                    ),
                    numThreads: 4,
                    modelType: "nemo_transducer"
                )
            )
            return GigaBox(rec: SherpaOnnxOfflineRecognizer(config: &config))
        }.value
        if let box {
            giga = box
            kit = nil
            loadedModel = model
            states[model] = .ready
            status = .ready
        } else {
            giga = nil
            loadedModel = nil
            status = .error("gigaam load failed")
        }
    }

    /// Frees the loaded ASR model (WhisperKit CoreML or GigaAM ONNX) to reclaim RAM.
    /// Called IMMEDIATELY after each session's final pass — the model (1.5–2+ GB)
    /// must not stay resident between meetings; the next recording reloads it in
    /// seconds. No-op while actively transcribing.
    public func unload() {
        if case .transcribing = status { return }
        kit = nil
        giga = nil
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
        guard !samples.isEmpty else { return [] }
        if let giga { return await Self.transcribeGiga(giga, samples: samples, meetingId: meetingId) }
        guard let kit else { return [] }
        do {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: Self.decodeOptions(language: language, strict: strict))
            let segs = results.flatMap(\.segments).compactMap { s -> TranscriptSegment? in
                let text = Self.cleanText(s.text)
                guard Self.hasSpeech(text), !Self.isHallucination(text) else { return nil }
                return TranscriptSegment(meetingId: meetingId, text: text,
                                         startSeconds: Double(s.start), endSeconds: Double(s.end))
            }
            return Self.collapseRepeats(segs)
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

    /// Reads an audio file into 16 kHz mono Float samples (GigaAM file path — the
    /// sherpa-onnx recognizer takes raw samples, not file URLs).
    private nonisolated static func loadSamples16k(_ url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return [] }
        var out: [Float] = []
        let inCap: AVAudioFrameCount = 48000
        while true {
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inCap),
                  (try? file.read(into: inBuf)) != nil, inBuf.frameLength > 0 else { break }
            let ratio = 16000.0 / file.processingFormat.sampleRate
            let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 32)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { break }
            var fed = false
            var err: NSError?
            converter.convert(to: outBuf, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return inBuf
            }
            guard err == nil, let ch = outBuf.floatChannelData?[0] else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
        }
        return out
    }

    /// GigaAM decode off the main thread: split into ≤28s chunks at the quietest
    /// point (the model is built for ≤~30s segments), decode sequentially, then
    /// split every chunk into UTTERANCES at inter-token pauses. One coarse segment
    /// per 25s chunk made speaker diarization useless (a segment can carry only
    /// one speaker label); utterance-level segments restore per-phrase labels.
    private nonisolated static func transcribeGiga(_ box: GigaBox, samples: [Float], meetingId: String) async -> [TranscriptSegment] {
        await Task.detached(priority: .userInitiated) {
            var segs: [TranscriptSegment] = []
            for chunk in Self.gigaChunks(samples) {
                let decoded = box.decode(chunk.samples)
                let base = Double(chunk.offset) / 16000.0
                let chunkEnd = Double(chunk.offset + chunk.samples.count) / 16000.0
                let pieces = Self.gigaUtterances(tokens: decoded.tokens, timestamps: decoded.timestamps)
                if pieces.isEmpty {
                    let text = Self.cleanText(decoded.text)
                    guard Self.hasSpeech(text), !Self.isHallucination(text) else { continue }
                    segs.append(TranscriptSegment(
                        meetingId: meetingId, text: text, startSeconds: base, endSeconds: chunkEnd
                    ))
                    continue
                }
                for piece in pieces {
                    let text = Self.cleanText(piece.text)
                    guard Self.hasSpeech(text), !Self.isHallucination(text) else { continue }
                    segs.append(TranscriptSegment(
                        meetingId: meetingId, text: text,
                        startSeconds: base + piece.start,
                        endSeconds: min(base + piece.end, chunkEnd)
                    ))
                }
            }
            return Self.collapseRepeats(segs)
        }.value
    }

    /// Splits one decoded GigaAM chunk into utterances at inter-token pauses.
    /// Tokens are sentencepiece BPE ("▁" marks a word start) with per-token start
    /// times; a gap ≥ `pauseSeconds` opens a new utterance. The model emits no
    /// per-token durations, so an utterance ends ~`tailSeconds` after its last
    /// token. Empty/mismatched inputs → empty (caller falls back to whole-chunk).
    nonisolated static func gigaUtterances(
        tokens: [String], timestamps: [Float], pauseSeconds: Float = 0.9
    ) -> [(text: String, start: Double, end: Double)] {
        guard !tokens.isEmpty, tokens.count == timestamps.count else { return [] }
        let tailSeconds: Float = 0.3
        var out: [(text: String, start: Double, end: Double)] = []
        var current = ""
        var start = timestamps[0]
        var last = timestamps[0]
        func flush() {
            let text = current.replacingOccurrences(of: "▁", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append((text, Double(start), Double(last + tailSeconds))) }
            current = ""
        }
        for (i, token) in tokens.enumerated() {
            let ts = timestamps[i]
            if !current.isEmpty, ts - last >= pauseSeconds {
                flush()
                start = ts
            }
            current += token
            last = ts
        }
        flush()
        return out
    }

    /// Splits 16 kHz audio into chunks of at most `maxSeconds`, cutting at the
    /// quietest 0.3s window near the `targetSeconds` mark so words aren't sliced.
    nonisolated static func gigaChunks(_ samples: [Float], maxSeconds: Double = 28,
                                       targetSeconds: Double = 25) -> [(offset: Int, samples: [Float])] {
        let sr = 16000
        let maxLen = Int(maxSeconds * Double(sr))
        guard samples.count > maxLen else { return samples.isEmpty ? [] : [(0, samples)] }
        var chunks: [(Int, [Float])] = []
        var from = 0
        while samples.count - from > maxLen {
            let searchLo = from + Int((targetSeconds - 3) * Double(sr))
            let searchHi = min(from + Int((targetSeconds + 3) * Double(sr)), samples.count - sr)
            let cut = quietestCut(samples, lo: searchLo, hi: searchHi)
            chunks.append((from, Array(samples[from ..< cut])))
            from = cut
        }
        chunks.append((from, Array(samples[from...])))
        return chunks
    }

    /// Start of the quietest 0.3s window in [lo, hi) (energy = Σ|x| over the window).
    private nonisolated static func quietestCut(_ samples: [Float], lo: Int, hi: Int) -> Int {
        let win = 4800, step = 800
        var best = lo, bestEnergy = Float.greatestFiniteMagnitude
        var i = lo
        while i + win <= hi {
            var e: Float = 0
            for j in i ..< (i + win) {
                e += abs(samples[j])
            }
            if e < bestEnergy { bestEnergy = e; best = i }
            i += step
        }
        return best + win / 2
    }

    /// True when the cleaned text carries real speech (≥ one letter/digit). Filters
    /// punctuation-only segments like "-", "—", "…" that Whisper emits on music /
    /// near-silence (which otherwise showed up as empty "[С]" transcript rows).
    public nonisolated static func hasSpeech(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .alphanumerics) != nil
    }

    /// Collapses a run of consecutive segments with IDENTICAL normalized text into one
    /// (start of the first, end of the last). Whisper's repetition loop on quiet/music
    /// audio emits dozens of degenerate one-word segments ("и" ×12) from a single decode
    /// window — per-segment thresholds and the merge dedup (< 3 words) can't catch them.
    /// Real speech is untouched: adjacent utterances are practically never verbatim-equal.
    public nonisolated static func collapseRepeats(_ segs: [TranscriptSegment]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var lastNorm = ""
        for seg in segs {
            let norm = seg.text.lowercased()
                .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
            if !out.isEmpty, norm == lastNorm {
                out[out.count - 1].endSeconds = max(out[out.count - 1].endSeconds, seg.endSeconds)
                continue
            }
            out.append(seg)
            lastNorm = norm
        }
        return out
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
    /// Tokens so specific to Whisper's YouTube-credits training data that their
    /// presence ANYWHERE marks a hallucination ("Субтитры создавал DimaTorzok" slipped
    /// past the prefix rule — 28 chars > prefix+18 window). Never occur in real speech.
    private static let hallucinationSubstrings = [
        "dimatorzok", "торзок", "amara.org", "субтитры создавал", "субтитры сделал"
    ]
    nonisolated static func isHallucination(_ text: String) -> Bool {
        let trimSet = CharacterSet(charactersIn: " []()【】.,!?…—-*\"'«»\n\t")
        let n = text.lowercased().trimmingCharacters(in: trimSet)
        for m in hallucinationMarkers {
            if n == m { return true }
            if n.hasPrefix(m), n.count <= m.count + 18 { return true }
        }
        for s in hallucinationSubstrings where n.contains(s) {
            return true
        }
        return false
    }

    /// Transcribes an audio file into segments. The empty-result mixed fallback in
    /// AppModel.process passes `strict: false` — if both strict per-channel passes
    /// already rejected everything, re-running the mix with the same strict thresholds
    /// would reject it too.
    public func transcribe(url: URL, meetingId: String, language: String?, strict: Bool = false) async -> [TranscriptSegment] {
        if let giga {
            let samples = Self.loadSamples16k(url)
            return await Self.transcribeGiga(giga, samples: samples, meetingId: meetingId)
        }
        guard let kit else { return [] }
        status = .transcribing
        do {
            let results: [TranscriptionResult] = try await kit.transcribe(audioPath: url.path, decodeOptions: Self.decodeOptions(language: language, strict: strict))
            var segments: [TranscriptSegment] = []
            for result in results {
                for s in result.segments {
                    let text = Self.cleanText(s.text)
                    guard Self.hasSpeech(text), !Self.isHallucination(text) else { continue }
                    segments.append(TranscriptSegment(
                        meetingId: meetingId,
                        text: text,
                        startSeconds: Double(s.start),
                        endSeconds: Double(s.end)
                    ))
                }
            }
            status = .ready
            return Self.collapseRepeats(segments)
        } catch {
            status = .error(error.localizedDescription)
            return []
        }
    }
}
