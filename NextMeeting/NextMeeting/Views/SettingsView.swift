import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferencesService: PreferencesService
    @ObservedObject var keyboardShortcutService: KeyboardShortcutService
    @ObservedObject var calendarService: CalendarService
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // A grouped Form aligns every label and control on its own without
            // hand-tuned padding, and scrolls when the content outgrows the
            // window instead of running off the bottom edge.
            Form {
                meetingsSection
                menuBarSection
                alertsSection
                shortcutSection
                calendarsSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    onDismiss?()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 460, minHeight: 400)
        .onAppear {
            calendarService.loadAvailableCalendars()
        }
    }

    private var meetingsSection: some View {
        Section {
            Picker("Lookahead window", selection: $preferencesService.lookaheadHours) {
                Text("12 hours").tag(12)
                Text("24 hours").tag(24)
                Text("48 hours").tag(48)
            }

            Picker("Refresh interval", selection: $preferencesService.refreshIntervalSeconds) {
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
            }
        } header: {
            Text("Meetings")
        }
    }

    private var menuBarSection: some View {
        Section {
            Picker("Countdown format", selection: $preferencesService.countdownFormat) {
                ForEach(CountdownFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            Toggle("Show calendar color", isOn: $preferencesService.showCalendarColor)

            Toggle("Show \u{201C}No Meetings\u{201D} when the calendar is clear",
                   isOn: $preferencesService.showNoMeetingsText)

            Toggle("Hide event name on an external display",
                   isOn: $preferencesService.hideEventTitleOnExternalDisplay)
        } header: {
            Text("Menu Bar")
        }
    }

    private var alertsSection: some View {
        Section {
            Picker("Alert timing", selection: $preferencesService.alertMinutesBefore) {
                Text("At start").tag(0)
                Text("1 minute before").tag(1)
                Text("5 minutes before").tag(5)
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("When to show the full screen alert. Turn the alerts themselves on or off in the menu.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var shortcutSection: some View {
        Section {
            Toggle("Join the next meeting", isOn: $keyboardShortcutService.isEnabled)
        } header: {
            Text("Keyboard Shortcut")
        } footer: {
            Text("Press \(keyboardShortcutService.shortcutDisplayString) from any app. Requires Accessibility permission.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var calendarsSection: some View {
        let grouped = Dictionary(grouping: calendarService.availableCalendars) { $0.source }

        return Section {
            ForEach(grouped.keys.sorted(), id: \.self) { source in
                if grouped.keys.count > 1 {
                    Text(source)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                ForEach(grouped[source] ?? []) { cal in
                    Toggle(isOn: Binding(
                        get: { !preferencesService.excludedCalendarIDs.contains(cal.id) },
                        set: { enabled in
                            if enabled {
                                preferencesService.excludedCalendarIDs.remove(cal.id)
                            } else {
                                preferencesService.excludedCalendarIDs.insert(cal.id)
                            }
                        }
                    )) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(cal.color)
                                .frame(width: 8, height: 8)
                            Text(cal.title)
                        }
                    }
                }
            }
        } header: {
            Text("Calendars")
        } footer: {
            Text("Turn a calendar off to leave its meetings out of the countdown and the list.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
