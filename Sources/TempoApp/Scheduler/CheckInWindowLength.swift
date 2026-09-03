import Foundation

/// Length the user commits to when answering a check-in prompt. A fixed length keeps Tempo
/// quiet for the whole window and attributes it to the selected project, which is what makes
/// long meetings trackable without a prompt interrupting them.
enum CheckInWindowLength: Hashable, Identifiable {
    case pollingDefault
    case fixed(minutes: Int)

    static let selectableOptions: [CheckInWindowLength] = [
        .pollingDefault,
        .fixed(minutes: 30),
        .fixed(minutes: 60),
        .fixed(minutes: 120),
        .fixed(minutes: 180),
        .fixed(minutes: 240),
        .fixed(minutes: 300),
        .fixed(minutes: 360),
        .fixed(minutes: 420),
        .fixed(minutes: 480),
    ]

    var id: Int {
        switch self {
        case .pollingDefault:
            return 0
        case let .fixed(minutes):
            return minutes
        }
    }

    var isCommitted: Bool {
        committedMinutes != nil
    }

    var committedMinutes: Int? {
        guard case let .fixed(minutes) = self, minutes > 0 else {
            return nil
        }

        return minutes
    }

    func displayName(pollingIntervalMinutes: Int) -> String {
        switch self {
        case .pollingDefault:
            return "Default (\(pollingIntervalMinutes) min)"
        case let .fixed(minutes):
            return Self.lengthLabel(minutes: minutes)
        }
    }

    /// End of the committed window, or `nil` when the regular polling interval applies.
    func committedWindowEnd(from startDate: Date) -> Date? {
        guard let committedMinutes else {
            return nil
        }

        return startDate.addingTimeInterval(TimeInterval(committedMinutes * 60))
    }

    private static func lengthLabel(minutes: Int) -> String {
        guard minutes >= 60 else {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let hoursLabel = hours == 1 ? "1 hour" : "\(hours) hours"

        guard remainingMinutes > 0 else {
            return hoursLabel
        }

        return "\(hoursLabel) \(remainingMinutes) min"
    }
}
