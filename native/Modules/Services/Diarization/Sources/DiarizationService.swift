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
    /// manager. Returns false on any failure. Uses FluidAudio's DEFAULT config
    /// (clusteringThreshold 0.7 etc.) — it separates distinct voices correctly; spurious
    /// tiny clusters are trimmed downstream by `DiarizationMap.assign`. (Raising the
    /// threshold to 0.8 over-merged two real voices into one — v55 regression.)
    private func ensureReady() async -> Bool {
        if manager != nil { return true }
        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            let m = DiarizerManager()
            m.initialize(models: models)
            manager = m
            return true
        } catch {
            return false
        }
    }

    /// Diarizes a 16 kHz mono buffer into speaker turns. Returns [] on any failure or
    /// for clips under ~2s (too short to cluster meaningfully). Logs the RAW speaker
    /// count + per-speaker durations so real-run behavior can be tuned from Console.
    public func diarize(_ samples: [Float]) async -> [SpeakerTurn] {
        guard samples.count > 32000 else { return [] }
        guard await ensureReady(), let manager else { return [] }
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
