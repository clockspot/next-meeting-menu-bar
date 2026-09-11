import AppKit
import SwiftUI
import UserNotifications
import os

@main
struct NextMeetingApp: App {
    private static let logger = Logger(subsystem: "com.nextmeeting.app", category: "App")

    @StateObject private var preferencesService: PreferencesService
    @StateObject private var calendarService: CalendarService
    @StateObject private var launchAtLoginService: LaunchAtLoginService
    @StateObject private var keyboardShortcutService: KeyboardShortcutService
    @StateObject private var displayMonitorService: DisplayMonitorService
    private let alertController = MeetingAlertWindowController()

    // Setup happens here rather than in the menu content's .onAppear: with the
    // .window MenuBarExtra style the content view isn't created until the menu
    // is first opened, so onAppear-based setup would leave the app without a
    // fetch, refresh timer, or hotkey after a launch-at-login start.
    init() {
        let preferences = PreferencesService()
        let calendar = CalendarService(preferencesService: preferences)
        let launchAtLogin = LaunchAtLoginService()
        let shortcut = KeyboardShortcutService()
        let displayMonitor = DisplayMonitorService()

        _preferencesService = StateObject(wrappedValue: preferences)
        _calendarService = StateObject(wrappedValue: calendar)
        _launchAtLoginService = StateObject(wrappedValue: launchAtLogin)
        _keyboardShortcutService = StateObject(wrappedValue: shortcut)
        _displayMonitorService = StateObject(wrappedValue: displayMonitor)

        shortcut.setup { [weak calendar] in
            guard let calendar else { return }
            Self.joinNextMeeting(from: calendar)
        }

        Self.requestNotificationPermissions()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                calendarService: calendarService,
                launchAtLoginService: launchAtLoginService,
                preferencesService: preferencesService,
                keyboardShortcutService: keyboardShortcutService,
                displayMonitorService: displayMonitorService
            )
        } label: {
            // MenuBarExtra draws only the first image and the first text of
            // whatever it is handed, image first, so the label is always at
            // most one of each. The countdown lives in the image because a
            // Text one cannot get tabular digits. See MenuBarLabelImage.
            if let label = menuBarLabel {
                Image(nsImage: MenuBarLabelImage.image(
                    text: label.countdown,
                    color: label.color,
                    trailingGap: label.eventName != nil
                ))

                if let eventName = label.eventName {
                    Text(eventName)
                }
            } else {
                Image(systemName: "calendar")

                if let status = menuBarStatusText {
                    Text(status)
                }
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: preferencesService.refreshIntervalSeconds) { _, _ in
            calendarService.restartRefreshTimer()
        }
        .onChange(of: preferencesService.excludedCalendarIDs) { _, _ in
            if calendarService.hasAccess {
                calendarService.fetchUpcomingMeetings()
            }
        }
        .onChange(of: calendarService.meetingToAlert?.id) { _, _ in
            if let meeting = calendarService.meetingToAlert {
                showAlert(for: meeting)
            }
        }
    }

    /// Fall back to the in-progress meeting so the menu bar doesn't claim
    /// "No Meetings" while your last meeting of the day is happening.
    private var displayedMeeting: Meeting? {
        calendarService.nextMeeting ?? calendarService.currentMeeting
    }

    private var hidesEventTitle: Bool {
        preferencesService.shouldHideEventTitle(
            hasExternalDisplay: displayMonitorService.hasExternalDisplay
        )
    }

    /// What the label says when there is nothing to count down to, or nil to
    /// leave the glyph standing on its own. Missing access always speaks up:
    /// a silent glyph would look like an empty calendar rather than a prompt.
    private var menuBarStatusText: String? {
        guard calendarService.hasAccess else {
            return "No Access"
        }

        return preferencesService.showNoMeetingsText ? "No Meetings" : nil
    }

    private struct MenuBarLabel {
        let countdown: String
        let color: Color?
        let eventName: String?
    }

    /// Nil when there is nothing to count down to, where the label falls back to
    /// a plain glyph and status text.
    private var menuBarLabel: MenuBarLabel? {
        guard calendarService.hasAccess, let meeting = displayedMeeting else {
            return nil
        }

        let showsName = !hidesEventTitle
        // The dot stays even with the name hidden — the countdown alone still
        // benefits from saying which calendar the meeting came from.
        let color = preferencesService.showCalendarColor ? meeting.calendarColor : nil

        return MenuBarLabel(
            countdown: meeting.menuBarCountdown(
                at: calendarService.now,
                format: preferencesService.countdownFormat,
                showTitle: showsName,
                hasColorDot: color != nil
            ),
            color: color,
            eventName: showsName ? meeting.menuBarEventName : nil
        )
    }

    private func showAlert(for meeting: Meeting) {
        calendarService.markMeetingAlerted(meeting)
        alertController.showAlert(for: meeting) { url in
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private static func joinNextMeeting(from calendarService: CalendarService) {
        let meetingToJoin = calendarService.currentMeeting ?? calendarService.nextMeeting

        guard let meeting = meetingToJoin else {
            notify(title: "No Meeting to Join", body: "There are no upcoming meetings at this time.")
            return
        }

        guard let url = meeting.meetingURL else {
            notify(title: "No Meeting URL", body: "'\(meeting.title)' doesn't have a meeting URL.")
            return
        }

        NSWorkspace.shared.open(url)
        notify(title: "Joining Meeting", body: meeting.title)
    }

    private static func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                logger.error("Notification permission error: \(error)")
            }
        }
    }

    private static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to show notification: \(error)")
            }
        }
    }
}
