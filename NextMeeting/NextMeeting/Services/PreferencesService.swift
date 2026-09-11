import SwiftUI

@MainActor
class PreferencesService: ObservableObject {
    private enum Keys {
        static let lookaheadHours = "lookaheadHours"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let alertMinutesBefore = "alertMinutesBefore"
        static let excludedCalendarIDs = "excludedCalendarIDs"
        static let countdownFormat = "countdownFormat"
        static let hideEventTitle = "hideEventTitle"
        static let hideEventTitleOnExternalDisplay = "hideEventTitleOnExternalDisplay"
        static let showCalendarColor = "showCalendarColor"
        static let showNoMeetingsText = "showNoMeetingsText"
    }

    @Published var lookaheadHours: Int {
        didSet {
            UserDefaults.standard.set(lookaheadHours, forKey: Keys.lookaheadHours)
        }
    }

    @Published var refreshIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
        }
    }

    @Published var alertMinutesBefore: Int {
        didSet {
            UserDefaults.standard.set(alertMinutesBefore, forKey: Keys.alertMinutesBefore)
        }
    }

    @Published var excludedCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(excludedCalendarIDs), forKey: Keys.excludedCalendarIDs)
        }
    }

    @Published var countdownFormat: CountdownFormat {
        didSet {
            UserDefaults.standard.set(countdownFormat.rawValue, forKey: Keys.countdownFormat)
        }
    }

    /// Manual privacy toggle: hide the event name in the menu bar.
    @Published var hideEventTitle: Bool {
        didSet {
            UserDefaults.standard.set(hideEventTitle, forKey: Keys.hideEventTitle)
        }
    }

    /// Hide the event name automatically whenever an external display is
    /// attached, as a stand-in for "presenting". See DisplayMonitorService for
    /// why screen sharing itself can't be detected.
    @Published var hideEventTitleOnExternalDisplay: Bool {
        didSet {
            UserDefaults.standard.set(hideEventTitleOnExternalDisplay, forKey: Keys.hideEventTitleOnExternalDisplay)
        }
    }

    /// Tint the menu bar with the next meeting's calendar color.
    /// Whether a clear calendar still says so in words. Off leaves the glyph
    /// alone, which keeps the item narrow on a crowded menu bar. This governs
    /// "No Meetings" only — missing calendar access always says so, since that
    /// is a state the user has to act on.
    @Published var showNoMeetingsText: Bool {
        didSet {
            UserDefaults.standard.set(showNoMeetingsText, forKey: Keys.showNoMeetingsText)
        }
    }

    @Published var showCalendarColor: Bool {
        didSet {
            UserDefaults.standard.set(showCalendarColor, forKey: Keys.showCalendarColor)
        }
    }

    init() {
        // Load from UserDefaults with default values
        let savedLookahead = UserDefaults.standard.integer(forKey: Keys.lookaheadHours)
        self.lookaheadHours = savedLookahead > 0 ? savedLookahead : 24

        let savedRefresh = UserDefaults.standard.integer(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = savedRefresh > 0 ? savedRefresh : 30

        // alertMinutesBefore can be 0, so we need to check if the key exists
        if UserDefaults.standard.object(forKey: Keys.alertMinutesBefore) != nil {
            self.alertMinutesBefore = UserDefaults.standard.integer(forKey: Keys.alertMinutesBefore)
        } else {
            self.alertMinutesBefore = 0
        }

        let savedExcluded = UserDefaults.standard.stringArray(forKey: Keys.excludedCalendarIDs) ?? []
        self.excludedCalendarIDs = Set(savedExcluded)

        let savedFormat = UserDefaults.standard.string(forKey: Keys.countdownFormat)
        self.countdownFormat = savedFormat.flatMap(CountdownFormat.init(rawValue:)) ?? .abbreviated

        self.hideEventTitle = UserDefaults.standard.bool(forKey: Keys.hideEventTitle)
        self.hideEventTitleOnExternalDisplay = UserDefaults.standard.bool(forKey: Keys.hideEventTitleOnExternalDisplay)
        self.showCalendarColor = UserDefaults.standard.bool(forKey: Keys.showCalendarColor)

        // Defaults to true, so an existing install keeps saying "No Meetings".
        if UserDefaults.standard.object(forKey: Keys.showNoMeetingsText) != nil {
            self.showNoMeetingsText = UserDefaults.standard.bool(forKey: Keys.showNoMeetingsText)
        } else {
            self.showNoMeetingsText = true
        }
    }

    /// Whether the event name should be hidden right now, combining the manual
    /// toggle with the external-display rule.
    func shouldHideEventTitle(hasExternalDisplay: Bool) -> Bool {
        hideEventTitle || (hideEventTitleOnExternalDisplay && hasExternalDisplay)
    }
}
