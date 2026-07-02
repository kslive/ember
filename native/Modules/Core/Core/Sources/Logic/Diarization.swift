import Foundation

/// One diarized speaker turn (produced by DiarizationService from FluidAudio, kept
/// as a pure Core type so the mapping logic is testable without the SDK).
public struct SpeakerTurn: Sendable, Equatable {
    public let rawId: String
    public let start: Double
    public let end: Double
    public init(rawId: String, start: Double, end: Double) {
        self.rawId = rawId
        self.start = start
        self.end = end
    }
}

/// Maps diarization turns onto the SYSTEM transcript segments.
public enum DiarizationMap {
    /// Diarization is unsupervised and tends to over-split (a brief blip/noise becomes
    /// a phantom speaker). Before numbering, drop clusters that carry too little speech:
    /// a raw speaker is "significant" only if its total turn duration is ≥ 3s AND ≥ 8%
    /// of all speech. Deliberately lenient (default config already separates real
    /// voices) — trims 1–2s phantom clusters without dropping a genuine, less-talkative
    /// second speaker. Deterministic safety net independent of the SDK's config.
    private static let minSignificantSeconds = 3.0
    private static let minSignificantFraction = 0.08

    /// Assigns each `.system` segment an ordinal speaker (1..N by first appearance in
    /// time) from the SIGNIFICANT turn it overlaps most. Mic/unknown segments are
    /// untouched. Phantom (tiny/sparse) clusters are ignored. If fewer than 2 significant
    /// speakers remain, leaves `speaker = 0` (a plain "Собеседник" — numbering one lone
    /// speaker is noise). No overlap with a significant turn → 0.
    public static func assign(_ segments: [TranscriptSegment], turns: [SpeakerTurn]) -> [TranscriptSegment] {
        guard !turns.isEmpty else { return segments }

        var durations: [String: Double] = [:]
        for t in turns {
            durations[t.rawId, default: 0] += max(0, t.end - t.start)
        }
        let total = durations.values.reduce(0, +)
        let floor = max(minSignificantSeconds, minSignificantFraction * total)
        let significant = Set(durations.filter { $0.value >= floor }.keys)

        var ordinal: [String: Int] = [:]
        for t in turns.sorted(by: { $0.start < $1.start })
            where significant.contains(t.rawId) && ordinal[t.rawId] == nil {
            ordinal[t.rawId] = ordinal.count + 1
        }
        let numbered = ordinal.count >= 2

        return segments.map { seg in
            guard seg.source == .system else { return seg }
            var bestId: String?
            var bestOverlap = 0.0
            for t in turns where significant.contains(t.rawId) {
                let overlap = min(seg.endSeconds, t.end) - max(seg.startSeconds, t.start)
                if overlap > bestOverlap { bestOverlap = overlap; bestId = t.rawId }
            }
            var s = seg
            s.speaker = (numbered && bestOverlap > 0) ? (ordinal[bestId ?? ""] ?? 0) : 0
            return s
        }
    }
}

/// Human-facing speaker label for a segment: "Я" for the mic, "Собеседник"/"Собеседник N"
/// for system audio, nil for unknown. `me`/`them` are the localized base words.
/// Used for the summary text fed to the AI (full words help attribution).
public enum SpeakerLabel {
    public static func text(source: TranscriptSource, speaker: Int, me: String, them: String) -> String? {
        switch source {
        case .mic: me
        case .system: speaker > 0 ? "\(them) \(speaker)" : them
        case .unknown: nil
        }
    }

    /// Compact bracketed tag for the transcript UI: "[Я]" for the mic, "[С]"/"[С1]"/"[С2]"
    /// for system audio, nil for unknown. `meShort`/`themShort` are the localized short
    /// tokens (e.g. ru "Я"/"С", en "Me"/"S", zh "我"/"对").
    public static func tag(source: TranscriptSource, speaker: Int, meShort: String, themShort: String) -> String? {
        switch source {
        case .mic: "[\(meShort)]"
        case .system: speaker > 0 ? "[\(themShort)\(speaker)]" : "[\(themShort)]"
        case .unknown: nil
        }
    }
}
