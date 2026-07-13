import EventKit
import Foundation

/// Meeting titles from Apple Calendar: when a calendar event is in progress at
/// recording start (or starts within the tolerance), its title becomes the
/// meeting title instead of the AI-generated one. The calendar is read ONLY at
/// recording start, and only when the user enabled the toggle and granted access.
public enum CalendarTitles {
    public enum Access {
        case notDetermined
        case granted
        case denied
    }

    /// Candidate event for the pure picker (EKEvent cannot be fabricated in tests).
    public struct Candidate: Sendable {
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool

        public init(title: String, start: Date, end: Date, isAllDay: Bool = false) {
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }
    }

    /// Events starting up to this far in the future still count — calls usually
    /// connect a minute or two before the scheduled slot.
    public static let startTolerance: TimeInterval = 180

    public static func accessStatus() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public static func requestAccess() async -> Bool {
        await (try? EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// Title of the calendar event active at `date` (or starting within the
    /// tolerance). nil = no access or no matching event.
    public static func eventTitle(at date: Date) -> String? {
        guard accessStatus() == .granted else { return nil }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-60),
            end: date.addingTimeInterval(startTolerance),
            calendars: nil
        )
        let candidates = store.events(matching: predicate).map {
            Candidate(title: $0.title ?? "", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
        return pick(from: candidates, at: date)
    }

    /// Pure picker: skip all-day and untitled events; the event must cover `date`
    /// or start within the tolerance; of several matches the one that starts the
    /// LATEST wins (joining the next meeting beats the still-running previous one).
    public static func pick(from candidates: [Candidate], at date: Date) -> String? {
        candidates
            .filter { !$0.isAllDay }
            .map { Candidate(title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                             start: $0.start, end: $0.end, isAllDay: $0.isAllDay) }
            .filter { !$0.title.isEmpty }
            .filter { c in
                let ongoing = c.start <= date && date <= c.end
                let upcoming = c.start > date && c.start.timeIntervalSince(date) <= startTolerance
                return ongoing || upcoming
            }
            .max { $0.start < $1.start }
            .map(\.title)
    }
}
