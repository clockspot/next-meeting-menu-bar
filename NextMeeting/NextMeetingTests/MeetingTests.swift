import Foundation
import SwiftUI

/// All time-dependent behavior is exercised against a fixed reference date so
/// results don't depend on when the tests run.
func runMeetingTests() {
    print("Meeting")
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    func makeMeeting(
        id: String = "test-id",
        title: String = "Test Meeting",
        startOffset: TimeInterval = 900,
        endOffset: TimeInterval = 4500,
        meetingURL: URL? = nil
    ) -> Meeting {
        Meeting(
            id: id,
            title: title,
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(endOffset),
            calendarColor: .blue,
            calendarName: "Test Calendar",
            meetingURL: meetingURL
        )
    }

    // MARK: countdownString

    TestRunner.test("countdown is Now during the meeting") {
        let meeting = makeMeeting(startOffset: -30, endOffset: 1800)
        TestRunner.expectEqual(meeting.countdownString(at: now), "Now")
    }

    TestRunner.test("countdown is Past after the meeting ended") {
        let meeting = makeMeeting(startOffset: -7200, endOffset: -3600)
        TestRunner.expectEqual(meeting.countdownString(at: now), "Past")
    }

    TestRunner.test("countdown shows minutes") {
        let meeting = makeMeeting(startOffset: 900, endOffset: 4500)
        TestRunner.expectEqual(meeting.countdownString(at: now), "15m")
    }

    TestRunner.test("countdown shows hours and minutes") {
        let meeting = makeMeeting(startOffset: 5400, endOffset: 9000)
        TestRunner.expectEqual(meeting.countdownString(at: now), "1h 30m")
    }

    TestRunner.test("countdown keeps a zero minutes place on the hour") {
        // "2h" would be narrower than the "1h 59m" on either side of it, so the
        // label would shrink and grow again once an hour.
        let meeting = makeMeeting(startOffset: 7200, endOffset: 10800)
        TestRunner.expectEqual(meeting.countdownString(at: now), "2h 0m")
    }

    TestRunner.test("abbreviated countdown holds its shape across the hour") {
        let before = makeMeeting(startOffset: 7260, endOffset: 10800)
        let onHour = makeMeeting(startOffset: 7200, endOffset: 10800)
        let after = makeMeeting(startOffset: 7140, endOffset: 10800)
        TestRunner.expectEqual(before.countdownString(at: now), "2h 1m")
        TestRunner.expectEqual(onHour.countdownString(at: now), "2h 0m")
        TestRunner.expectEqual(after.countdownString(at: now), "1h 59m")
    }

    TestRunner.test("countdown shows <1m just before start") {
        let meeting = makeMeeting(startOffset: 30, endOffset: 3630)
        TestRunner.expectEqual(meeting.countdownString(at: now), "<1m")
    }

    // MARK: countdownString (digital format)

    TestRunner.test("digital countdown pads minutes under an hour") {
        let meeting = makeMeeting(startOffset: 900, endOffset: 4500)
        TestRunner.expectEqual(meeting.countdownString(at: now, format: .digital), "0:15")
    }

    TestRunner.test("digital countdown shows hours and minutes") {
        let meeting = makeMeeting(startOffset: 8580, endOffset: 12180)
        TestRunner.expectEqual(meeting.countdownString(at: now, format: .digital), "2:23")
    }

    TestRunner.test("digital countdown pads single-digit minutes") {
        let meeting = makeMeeting(startOffset: 3660, endOffset: 7260)
        TestRunner.expectEqual(meeting.countdownString(at: now, format: .digital), "1:01")
    }

    TestRunner.test("digital countdown shows whole hours as :00") {
        let meeting = makeMeeting(startOffset: 7200, endOffset: 10800)
        TestRunner.expectEqual(meeting.countdownString(at: now, format: .digital), "2:00")
    }

    TestRunner.test("digital countdown shows <0:01 in the last minute") {
        let meeting = makeMeeting(startOffset: 30, endOffset: 3630)
        TestRunner.expectEqual(meeting.countdownString(at: now, format: .digital), "<0:01")
    }

    TestRunner.test("both formats mark the sub-minute window the same way") {
        let meeting = makeMeeting(startOffset: 30, endOffset: 3630)
        let abbreviated = meeting.countdownString(at: now, format: .abbreviated)
        let digital = meeting.countdownString(at: now, format: .digital)
        TestRunner.expect(abbreviated.hasPrefix("<") && digital.hasPrefix("<"),
                          "expected both to be prefixed: \(abbreviated) / \(digital)")
    }

    TestRunner.test("digital countdown still reports Now and Past") {
        let running = makeMeeting(startOffset: -30, endOffset: 1800)
        TestRunner.expectEqual(running.countdownString(at: now, format: .digital), "Now")
        let finished = makeMeeting(startOffset: -7200, endOffset: -3600)
        TestRunner.expectEqual(finished.countdownString(at: now, format: .digital), "Past")
    }

    TestRunner.test("abbreviated is the default format") {
        let meeting = makeMeeting(startOffset: 5400, endOffset: 9000)
        TestRunner.expectEqual(meeting.countdownString(at: now),
                               meeting.countdownString(at: now, format: .abbreviated))
    }

    // MARK: isHappeningNow

    TestRunner.test("isHappeningNow true mid-meeting") {
        let meeting = makeMeeting(startOffset: -300, endOffset: 1500)
        TestRunner.expect(meeting.isHappeningNow(at: now))
    }

    TestRunner.test("isHappeningNow false before start") {
        let meeting = makeMeeting(startOffset: 300, endOffset: 3900)
        TestRunner.expect(!meeting.isHappeningNow(at: now))
    }

    TestRunner.test("isHappeningNow false after end") {
        let meeting = makeMeeting(startOffset: -3600, endOffset: -300)
        TestRunner.expect(!meeting.isHappeningNow(at: now))
    }

    // MARK: isJustStarting

    TestRunner.test("isJustStarting true within 60s of start") {
        let meeting = makeMeeting(startOffset: -30, endOffset: 3570)
        TestRunner.expect(meeting.isJustStarting(at: now))
    }

    TestRunner.test("isJustStarting false after 60s") {
        let meeting = makeMeeting(startOffset: -120, endOffset: 3480)
        TestRunner.expect(!meeting.isJustStarting(at: now))
    }

    TestRunner.test("isJustStarting false before start") {
        let meeting = makeMeeting(startOffset: 30, endOffset: 3630)
        TestRunner.expect(!meeting.isJustStarting(at: now))
    }

    // MARK: menuBarCountdown and menuBarEventName

    TestRunner.test("short event name is not truncated") {
        let meeting = makeMeeting(title: "Team Standup")
        TestRunner.expectEqual(meeting.menuBarEventName, "Team Standup")
    }

    TestRunner.test("long event name is truncated with ellipsis") {
        let meeting = makeMeeting(title: "Very Long Meeting Title That Should Be Truncated")
        let name = meeting.menuBarEventName
        TestRunner.expect(name.contains("..."), "expected ellipsis in \(name)")
        TestRunner.expect(name.count <= 20, "name too long: \(name)")
    }

    TestRunner.test("menuBarEventName truncates to a fixed width") {
        let meeting = makeMeeting(title: "Very Long Meeting Title That Should Be Truncated")
        TestRunner.expectEqual(meeting.menuBarEventName, "Very Long Meeting...")
    }

    TestRunner.test("abbreviated countdown carries the colon before the name") {
        let meeting = makeMeeting(startOffset: 8580, endOffset: 12180)
        TestRunner.expectEqual(meeting.menuBarCountdown(at: now, format: .abbreviated), "2h 23m:")
    }

    TestRunner.test("digital countdown takes no colon, it already has one") {
        let meeting = makeMeeting(startOffset: 8580, endOffset: 12180)
        TestRunner.expectEqual(meeting.menuBarCountdown(at: now, format: .digital), "2:23")
    }

    TestRunner.test("a color dot separates well enough to drop the colon") {
        let meeting = makeMeeting(startOffset: 8580, endOffset: 12180)
        TestRunner.expectEqual(
            meeting.menuBarCountdown(at: now, format: .abbreviated, hasColorDot: true),
            "2h 23m"
        )
    }

    TestRunner.test("hiding the name drops the trailing colon too") {
        let meeting = makeMeeting(title: "Performance Review", startOffset: 5400, endOffset: 9000)
        TestRunner.expectEqual(meeting.menuBarCountdown(at: now, showTitle: false), "1h 30m")
    }

    TestRunner.test("hiding the name respects the countdown format") {
        let meeting = makeMeeting(title: "Performance Review", startOffset: 5400, endOffset: 9000)
        TestRunner.expectEqual(
            meeting.menuBarCountdown(at: now, format: .digital, showTitle: false),
            "1:30"
        )
    }

    TestRunner.test("hidden name never leaks into the drawn countdown") {
        let meeting = makeMeeting(title: "Layoff Planning", startOffset: 900, endOffset: 4500)
        let drawn = meeting.menuBarCountdown(at: now, showTitle: false)
        TestRunner.expect(!drawn.contains("Layoff"), "event name leaked into \(drawn)")
        TestRunner.expect(!drawn.hasSuffix(":"), "separator left behind in \(drawn)")
    }

    TestRunner.test("menuBarEventName leaves a short name alone") {
        let meeting = makeMeeting(title: "Standup")
        TestRunner.expectEqual(meeting.menuBarEventName, "Standup")
    }

    // MARK: relative countdown

    TestRunner.test("list countdown is prefixed with in") {
        let meeting = makeMeeting(startOffset: 8580, endOffset: 12180)
        TestRunner.expectEqual(meeting.relativeCountdownString(at: now, format: .abbreviated), "in 2h 23m")
    }

    TestRunner.test("list countdown leaves Now alone") {
        let meeting = makeMeeting(startOffset: -60, endOffset: 3600)
        TestRunner.expectEqual(meeting.relativeCountdownString(at: now, format: .abbreviated), "Now")
    }

    TestRunner.test("list countdown leaves Past alone") {
        let meeting = makeMeeting(startOffset: -7200, endOffset: -3600)
        TestRunner.expectEqual(meeting.relativeCountdownString(at: now, format: .abbreviated), "Past")
    }

    TestRunner.test("list countdown carries the digital format through") {
        let meeting = makeMeeting(startOffset: 8580, endOffset: 12180)
        TestRunner.expectEqual(meeting.relativeCountdownString(at: now, format: .digital), "in 2:23")
    }

    // MARK: displaySignature

    TestRunner.test("signature holds steady while the rendered text does") {
        // 90.5 minutes out, so the whole-minute countdown reads 1h 30m across
        // the next 29 seconds and nothing on screen changes.
        let meetings = [makeMeeting(startOffset: 5430, endOffset: 9030)]
        let first = Meeting.displaySignature(for: meetings, at: now, format: .abbreviated)
        let later = Meeting.displaySignature(for: meetings, at: now.addingTimeInterval(29), format: .abbreviated)
        TestRunner.expectEqual(first, later)
        TestRunner.expect(first.contains("1h 30m"), "unexpected probe text: \(first)")
    }

    TestRunner.test("signature changes when the countdown rolls over a minute") {
        let meetings = [makeMeeting(startOffset: 5400, endOffset: 9000)]
        let before = Meeting.displaySignature(for: meetings, at: now, format: .abbreviated)
        let after = Meeting.displaySignature(for: meetings, at: now.addingTimeInterval(60), format: .abbreviated)
        TestRunner.expect(before != after, "expected a change across the minute boundary")
    }

    TestRunner.test("signature changes the moment a meeting starts") {
        let meetings = [makeMeeting(startOffset: 5, endOffset: 3600)]
        let before = Meeting.displaySignature(for: meetings, at: now, format: .abbreviated)
        let after = Meeting.displaySignature(for: meetings, at: now.addingTimeInterval(6), format: .abbreviated)
        TestRunner.expect(before != after, "expected a change when the meeting starts")
    }

    TestRunner.test("signature distinguishes the two countdown formats") {
        let meetings = [makeMeeting(startOffset: 5400, endOffset: 9000)]
        let abbreviated = Meeting.displaySignature(for: meetings, at: now, format: .abbreviated)
        let digital = Meeting.displaySignature(for: meetings, at: now, format: .digital)
        TestRunner.expect(abbreviated != digital, "format change must force a republish")
    }

    TestRunner.test("signature tracks every listed meeting, not just the first") {
        let base = makeMeeting(id: "a", startOffset: 5400, endOffset: 9000)
        let second = makeMeeting(id: "b", startOffset: 60, endOffset: 3600)
        let before = Meeting.displaySignature(for: [base, second], at: now, format: .abbreviated)
        let after = Meeting.displaySignature(for: [base, second], at: now.addingTimeInterval(1), format: .abbreviated)
        TestRunner.expect(before != after, "a change in any listed meeting must republish")
    }

    TestRunner.test("gating publishes about once a minute, not once a second") {
        let meetings = [makeMeeting(startOffset: 5400, endOffset: 9000)]
        var published = 0
        var last: String?

        // Three minutes of one-second ticks.
        for second in 0..<180 {
            let signature = Meeting.displaySignature(
                for: meetings,
                at: now.addingTimeInterval(TimeInterval(second)),
                format: .abbreviated
            )
            if signature != last {
                last = signature
                published += 1
            }
        }

        // One initial publish plus one per minute rolled over.
        TestRunner.expectEqual(published, 4)
    }

    TestRunner.test("an empty meeting list yields a stable signature") {
        let first = Meeting.displaySignature(for: [], at: now, format: .abbreviated)
        let later = Meeting.displaySignature(for: [], at: now.addingTimeInterval(3600), format: .abbreviated)
        TestRunner.expectEqual(first, later)
    }

    // MARK: makeID

    TestRunner.test("makeID distinguishes occurrences of a recurring event") {
        let first = Meeting.makeID(eventIdentifier: "recurring-standup", startDate: now)
        let second = Meeting.makeID(eventIdentifier: "recurring-standup", startDate: now.addingTimeInterval(86400))
        TestRunner.expect(first != second, "occurrences must not share an id")
    }

    TestRunner.test("makeID is stable for the same occurrence") {
        let a = Meeting.makeID(eventIdentifier: "abc", startDate: now)
        let b = Meeting.makeID(eventIdentifier: "abc", startDate: now)
        TestRunner.expectEqual(a, b)
    }

    TestRunner.test("makeID tolerates a nil event identifier") {
        let id = Meeting.makeID(eventIdentifier: nil, startDate: now)
        TestRunner.expect(!id.isEmpty)
    }
}
