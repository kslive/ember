import Foundation

/// Human-facing speaker label for a transcript segment, derived purely from the
/// CHANNEL (mic vs system) — no ML speaker diarization. "Я" for the mic, a single
/// "Собеседник"/"С" for the other side; the AI works out distinct participants
/// from the transcript content itself.
public enum SpeakerLabel {
    /// Full word for the summary text fed to the AI ("Я" / "Собеседник").
    public static func text(source: TranscriptSource, me: String, them: String) -> String? {
        switch source {
        case .mic: me
        case .system: them
        case .unknown: nil
        }
    }

    /// Compact bracketed tag for the transcript UI ("[Я]" / "[С]"). `meShort`/
    /// `themShort` are the localized short tokens (ru "Я"/"С", en "Me"/"S", zh "我"/"对").
    public static func tag(source: TranscriptSource, meShort: String, themShort: String) -> String? {
        switch source {
        case .mic: "[\(meShort)]"
        case .system: "[\(themShort)]"
        case .unknown: nil
        }
    }
}
