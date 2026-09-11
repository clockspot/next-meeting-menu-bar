import Foundation
import SwiftUI

/// How a countdown is rendered wherever one is shown.
enum CountdownFormat: String, CaseIterable, Identifiable {
    /// Abbreviated units, e.g. "2h 23m", "15m", "<1m".
    case abbreviated
    /// Fixed-width clock style, e.g. "2:23", "0:15".
    case digital

    var id: String { rawValue }

    /// Shown in the settings picker; the format is easier to recognize from a
    /// sample than from a name.
    var displayName: String {
        switch self {
        case .abbreviated: return "2h 23m"
        case .digital: return "2:23"
        }
    }
}

struct Meeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarColor: Color
    let calendarName: String
    let meetingURL: URL?

    /// Occurrences of a recurring event share one `eventIdentifier`, and some
    /// events (e.g. unsynced Exchange invites) have none at all — combine with
    /// the start date so every occurrence gets a distinct, stable id.
    static func makeID(eventIdentifier: String?, startDate: Date) -> String {
        "\(eventIdentifier ?? "no-identifier")-\(startDate.timeIntervalSince1970)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var timeString: String {
        Self.timeFormatter.string(from: startDate)
    }

    // Time-dependent checks take an explicit `now` so they are deterministic
    // in tests; the parameterless properties are conveniences for views.

    func isHappeningNow(at now: Date = Date()) -> Bool {
        now >= startDate && now <= endDate
    }

    var isHappeningNow: Bool { isHappeningNow() }

    func isJustStarting(at now: Date = Date()) -> Bool {
        let secondsSinceStart = now.timeIntervalSince(startDate)
        return secondsSinceStart >= 0 && secondsSinceStart <= 60
    }

    var isJustStarting: Bool { isJustStarting() }

    func countdownString(at now: Date = Date(), format: CountdownFormat = .abbreviated) -> String {
        if isHappeningNow(at: now) {
            return "Now"
        }

        let interval = startDate.timeIntervalSince(now)

        if interval < 0 {
            return "Past"
        }

        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        switch format {
        case .abbreviated:
            if hours > 0 {
                // Including a zero ("2h 0m") keeps the width steady. Dropping
                // the minutes for one minute in every hour made the label
                // narrow and then widen again, shoving its neighbors twice.
                return "\(hours)h \(remainingMinutes)m"
            }

            if minutes < 1 {
                return "<1m"
            }

            return "\(minutes)m"

        case .digital:
            // Mirrors the abbreviated "<1m": truncating to 0:00 would read as
            // though the meeting had already started.
            if minutes < 1 {
                return "<0:01"
            }

            return String(format: "%d:%02d", hours, remainingMinutes)
        }
    }

    var countdownString: String { countdownString() }

    /// The event name as it appears in the menu bar, shortened so a long name
    /// can't crowd out the rest of the bar.
    var menuBarEventName: String {
        title.count > 20 ? String(title.prefix(17)) + "..." : title
    }

    /// The countdown as drawn into the menu bar label, including the colon that
    /// separates it from the event name when nothing else does.
    ///
    /// The abbreviated countdown ends in a unit letter, so a colon reads as
    /// punctuation. The digital one already contains one — "2:23: Standup"
    /// reads as a typo — and a colored dot is itself a separator, so neither
    /// takes a colon. Nor does a label with no event name after it.
    func menuBarCountdown(at now: Date = Date(),
                          format: CountdownFormat = .abbreviated,
                          showTitle: Bool = true,
                          hasColorDot: Bool = false) -> String {
        let countdown = countdownString(at: now, format: format)

        guard showTitle, !hasColorDot, format == .abbreviated else {
            return countdown
        }

        return "\(countdown):"
    }

    /// Countdown phrased for the meeting list, where it sits next to the event's
    /// actual start time and is otherwise easy to misread as another clock time.
    /// "Now" and "Past" already read as phrases, so they are left alone.
    func relativeCountdownString(at now: Date = Date(),
                                 format: CountdownFormat = .abbreviated) -> String {
        let countdown = countdownString(at: now, format: format)

        guard !isHappeningNow(at: now), startDate > now else {
            return countdown
        }

        return "in \(countdown)"
    }
}

extension Meeting {
    /// Everything the views draw from a given instant: each meeting's countdown
    /// text and whether it is in progress.
    ///
    /// Two instants with the same signature are indistinguishable on screen, so
    /// the display clock only needs to be republished when this changes. Keep it
    /// in step with what the views actually render — a view that formats a time
    /// some other way would drift out from under the comparison.
    static func displaySignature(for meetings: [Meeting],
                                 at now: Date,
                                 format: CountdownFormat) -> String {
        meetings.reduce(into: "") { signature, meeting in
            signature += meeting.id
            signature += "|"
            signature += meeting.countdownString(at: now, format: format)
            signature += meeting.isHappeningNow(at: now) ? "|now;" : "|;"
        }
    }
}
