import Core
import FluidAudio
import Foundation
import OSLog

/// On-device speaker diarization via FluidAudio (CoreML/ANE). An `actor` so the
/// (synchronous, multi-second) diarization runs off the main thread and is
/// serialized. Best-effort: every entry point degrades to an empty result instead
/// of throwing, so a missing model / offline / short clip never breaks the pipeline.
public actor DiarizationService {
    private var manager: DiarizerManager?
    private static let log = Logger(subsystem: "com.kslff.ember", category: "diar")

    public init() {}

    /// Lazily downloads + compiles the CoreML models (one-time) and initializes the
    /// manager. Returns false on any failure.
    ///
    /// The assign gate is set DIRECTLY on the SpeakerManager, not via
    /// `DiarizerConfig.clusteringThreshold`: the SDK multiplies the config value by
    /// 1.2 (its comment claims 0.9×), so config 0.7 really assigns a chunk to an
    /// existing speaker at cosine distance < 0.84 — wide enough to absorb a second
    /// same-gender narrator (similar voices sit at 0.6–0.8), which then never splits.
    /// 0.75 narrows only that gate (config 0.8 → effective 0.96 was the over-merge
    /// disaster; the default 0.84 still merged two real male voices). The lower
    /// embedding gate slows the centroid EMA drift that self-reinforces a merge.
    /// Over-split of one expressive voice is trimmed downstream by
    /// `DiarizationMap.assign` (significance floor + winners-only numbering).
    /// Re-verify both overrides on any FluidAudio bump — they bypass the config.
    private func ensureReady() async -> Bool {
        if manager != nil { return true }
        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            let m = DiarizerManager()
            m.initialize(models: models)
            m.speakerManager.speakerThreshold = 0.75
            m.speakerManager.embeddingThreshold = 0.50
            manager = m
            return true
        } catch {
            return false
        }
    }

    /// Diarizes a 16 kHz mono buffer into speaker turns. Returns [] on any failure or
    /// for clips under ~2s (too short to cluster meaningfully). Logs the RAW speaker
    /// count + per-speaker durations so real-run behavior can be tuned from Console.
    /// The CoreML models are released right after the pass — they must not stay
    /// resident between meetings; the on-disk cache makes the next init cheap.
    public func diarize(_ samples: [Float]) async -> [SpeakerTurn] {
        guard samples.count > 32000 else { return [] }
        guard await ensureReady(), let manager else { return [] }
        defer { self.manager = nil }
        do {
            let result = try manager.performCompleteDiarization(samples)
            let turns = result.segments.map {
                SpeakerTurn(rawId: String(describing: $0.speakerId),
                            start: Double($0.startTimeSeconds),
                            end: Double($0.endTimeSeconds))
            }
            var durations: [String: Double] = [:]
            for t in turns {
                durations[t.rawId, default: 0] += max(0, t.end - t.start)
            }
            let summary = durations.sorted { $0.value > $1.value }
                .map { "\($0.key)=\(String(format: "%.1f", $0.value))s" }.joined(separator: " ")
            Self.log.info("diarize raw speakers=\(durations.count, privacy: .public) [\(summary, privacy: .public)]")
            return turns
        } catch {
            Self.log.error("diarize failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
