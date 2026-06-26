import Foundation

/// Thread-safe cache of `DateFormatter`s keyed by `language|format`. Allocating a
/// DateFormatter (ICU/locale setup) per call was a per-row, per-render cost in the
/// sidebar and meeting list; reuse one instance instead. (`string(from:)` is
/// thread-safe; the lock only guards the dictionary.)
private final class FormatterCache: @unchecked Sendable {
    static let shared = FormatterCache()
    private var cache: [String: DateFormatter] = [:]
    private let lock = NSLock()
    func formatter(_ format: String, _ language: AppLanguage) -> DateFormatter {
        let key = "\(language.rawValue)|\(format)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: language.bcp47)
        f.dateFormat = format
        cache[key] = f
        return f
    }
}

public enum Format {
    /// Formats `date` with a cached formatter for `format` + `language`.
    public static func date(_ date: Date, format: String, language: AppLanguage = .en) -> String {
        FormatterCache.shared.formatter(format, language).string(from: date)
    }

    /// `mm:ss` timecode for transcript lines.
    public static func timecode(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Human duration: `32 min` / `1 h 05 min`.
    public static func duration(_ seconds: Double, language: AppLanguage = .en) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0, m == 0, total > 0 {
            let secLabel = language == .ru ? "сек" : (language == .zh ? "秒" : "sec")
            return "\(total) \(secLabel)"
        }
        let minLabel = switch language {
        case .ru: "мин"
        case .zh: "分钟"
        case .en: "min"
        }
        if h > 0 {
            let hLabel = language == .ru ? "ч" : (language == .zh ? "小时" : "h")
            return "\(h) \(hLabel) \(String(format: "%02d", m)) \(minLabel)"
        }
        return "\(m) \(minLabel)"
    }

    /// Clock time `HH:mm` in the meeting locale.
    public static func clock(_ date: Date, language: AppLanguage = .en) -> String {
        Self.date(date, format: "HH:mm", language: language)
    }
}

/// Sidebar date grouping (Today / Yesterday / explicit date).
public enum DateGroup: Hashable, Sendable {
    case today
    case yesterday
    case day(Date)

    public static func of(_ date: Date, now _: Date = Date(), calendar: Calendar = .current) -> DateGroup {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        return .day(calendar.startOfDay(for: date))
    }
}
