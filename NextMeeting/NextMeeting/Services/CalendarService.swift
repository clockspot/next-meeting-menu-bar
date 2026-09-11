import EventKit
import SwiftUI
import os

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    let source: String
}

@MainActor
class CalendarService: ObservableObject {
    private static let logger = Logger(subsystem: "com.nextmeeting.app", category: "CalendarService")

    private let eventStore = EKEventStore()
    private let preferencesService: PreferencesService
    private var alertedMeetingIds: Set<String> = []
    private var refreshTimer: Timer?
    private var displayTimer: Timer?

    @Published var meetings: [Meeting] = []
    @Published var hasAccess: Bool = false
    @Published var availableCalendars: [CalendarInfo] = []

    /// Advances only when something rendered from it would actually change,
    /// which is at most once a minute for a countdown. The display timer still
    /// ticks every second underneath.
    @Published private(set) var now: Date = Date()

    /// The rendering `now` was last published for, so an unchanged tick can be
    /// dropped instead of republished.
    private var lastDisplaySignature: String?

    /// Set on the display tick when a meeting enters its alert window.
    /// Evaluated every second (not on the slower fetch cadence) so the
    /// one-minute alert window can't be skipped by a long refresh interval.
    @Published private(set) var meetingToAlert: Meeting?

    @Published var fullScreenAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(fullScreenAlertsEnabled, forKey: "fullScreenAlertsEnabled")
        }
    }

    var currentMeeting: Meeting? {
        meetings.first { $0.isHappeningNow(at: now) }
    }

    var nextMeeting: Meeting? {
        meetings.first { !$0.isHappeningNow(at: now) }
    }

    init(preferencesService: PreferencesService) {
        self.preferencesService = preferencesService
        self.fullScreenAlertsEnabled = UserDefaults.standard.bool(forKey: "fullScreenAlertsEnabled")
        checkAuthorizationStatus()
        if hasAccess {
            startTimers()
        }
    }

    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            hasAccess = status == .fullAccess
        } else {
            hasAccess = status == .authorized
        }
    }

    func requestAccess() async {
        if #available(macOS 14.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                hasAccess = granted
                if granted {
                    startTimers()
                }
            } catch {
                Self.logger.error("Failed to request calendar access: \(error)")
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.hasAccess = granted
                    if granted {
                        self?.startTimers()
                    }
                }
            }
        }
    }

    // MARK: - Timers

    /// Fetches immediately, then refetches on the configured interval and
    /// re-renders/checks alerts every second.
    func startTimers() {
        startRefreshTimer()
        startDisplayTimer()
    }

    /// Call when the refresh-interval preference changes.
    func restartRefreshTimer() {
        guard hasAccess else { return }
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        fetchUpcomingMeetings()

        let interval = TimeInterval(preferencesService.refreshIntervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.fetchUpcomingMeetings()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func startDisplayTimer() {
        // isValid, not nil: a timer that was invalidated must be replaced, or
        // the clock would never tick again for the life of the process.
        guard displayTimer?.isValid != true else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.displayTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    /// Brings the display clock to the present and makes sure the tick is still
    /// running.
    ///
    /// Views render the countdown from `now` rather than reading the clock
    /// themselves, which keeps the menu bar and the dropdown in agreement but
    /// also means a clock that fell behind stays visibly behind. The menu
    /// content is only on screen while the menu is open, so opening it is both
    /// when staleness would show and a free moment to recover.
    func syncDisplayClock() {
        let tick = Date()

        lastDisplaySignature = Meeting.displaySignature(
            for: meetings,
            at: tick,
            format: preferencesService.countdownFormat
        )
        now = tick

        if hasAccess {
            startDisplayTimer()
        }
    }

    private func displayTick() {
        let tick = Date()

        // Republishing `now` every second rebuilds the MenuBarExtra label and
        // relays out the status item, which nudges neighboring menu bar items
        // even when the text is identical. Publish only on a real change.
        let signature = Meeting.displaySignature(
            for: meetings,
            at: tick,
            format: preferencesService.countdownFormat
        )
        if signature != lastDisplaySignature {
            lastDisplaySignature = signature
            now = tick
        }

        // Alerts are still evaluated against the raw tick every second, so a
        // one-minute window can't be missed just because the text held steady.
        let candidate: Meeting?
        if fullScreenAlertsEnabled {
            candidate = MeetingAlertPolicy.meetingToAlert(
                in: meetings,
                alertedIDs: alertedMeetingIds,
                alertMinutesBefore: preferencesService.alertMinutesBefore,
                now: tick
            )
        } else {
            candidate = nil
        }

        if meetingToAlert?.id != candidate?.id {
            meetingToAlert = candidate
        }
    }

    func markMeetingAlerted(_ meeting: Meeting) {
        alertedMeetingIds.insert(meeting.id)
        if meetingToAlert?.id == meeting.id {
            meetingToAlert = nil
        }
    }

    private func cleanupAlertedMeetingIds() {
        let currentMeetingIds = Set(meetings.map { $0.id })
        alertedMeetingIds = alertedMeetingIds.intersection(currentMeetingIds)
    }

    // MARK: - Fetching

    func loadAvailableCalendars() {
        guard hasAccess else { return }
        let ekCalendars = eventStore.calendars(for: .event)
        availableCalendars = ekCalendars.map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: Color(cgColor: cal.cgColor),
                source: cal.source.title
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetchUpcomingMeetings() {
        guard hasAccess else { return }

        let now = Date()
        guard let endDate = Calendar.current.date(byAdding: .hour, value: preferencesService.lookaheadHours, to: now) else {
            return
        }

        let excludedIDs = preferencesService.excludedCalendarIDs
        let calendars: [EKCalendar]? = excludedIDs.isEmpty
            ? nil
            : eventStore.calendars(for: .event).filter { !excludedIDs.contains($0.calendarIdentifier) }

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: calendars
        )

        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        meetings = events.map { event in
            Meeting(
                id: Meeting.makeID(eventIdentifier: event.eventIdentifier, startDate: event.startDate),
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                calendarColor: Color(cgColor: event.calendar.cgColor),
                calendarName: event.calendar.title,
                meetingURL: extractMeetingURL(from: event)
            )
        }

        cleanupAlertedMeetingIds()
    }

    private func extractMeetingURL(from event: EKEvent) -> URL? {
        let extracted = MeetingURLExtractor.extractURL(from: [
            event.url?.absoluteString,
            event.location,
            event.notes
        ])
        return extracted ?? event.url
    }
}
