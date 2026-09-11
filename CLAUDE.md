# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NextMeeting is a macOS menu bar app (Swift/SwiftUI) that shows a live countdown to your next calendar event and provides a global keyboard shortcut (Cmd+Shift+J) to join meetings. It runs as an LSUIElement (no Dock icon), uses App Sandbox with calendar entitlement, and has zero third-party dependencies.

## Build & Run

```bash
# Build from command line
xcodebuild build -project NextMeeting/NextMeeting.xcodeproj -scheme NextMeeting -destination 'platform=macOS'

# Or open in Xcode and Cmd+R
open NextMeeting/NextMeeting.xcodeproj
```

Xcode project is at `NextMeeting/NextMeeting.xcodeproj`. No Package.swift, no CocoaPods, no SPM dependencies.

## Linting

```bash
swiftlint lint NextMeeting/
```

Config in `.swiftlint.yml`: `line_length` and `trailing_whitespace` are disabled. `force_unwrapping` is opted in. Function body limit is 50 lines (warning) / 100 (error).

## Testing

```bash
./test.sh
```

Tests run with the Command Line Tools alone — no Xcode or XCTest. `test.sh` compiles the pure-logic sources (`Meeting`, `MeetingURLExtractor`, `MeetingAlertPolicy`) together with `NextMeeting/NextMeetingTests/` (a small assertion harness, `TestHarness.swift`, plus `main.swift` runner) into a plain executable and runs it. Time-dependent tests inject a fixed `now` — never assert against the wall clock. Add new cases to the existing `run*Tests()` functions or register a new one in `main.swift`.

## Architecture

**Entry point:** `NextMeetingApp.swift` — SwiftUI `@main` App using `MenuBarExtra` with `.window` style. Creates and wires all four services in `App.init` (NOT in the content view's `.onAppear` — with the `.window` style the content view doesn't exist until the menu is first opened, so onAppear-based setup breaks launch-at-login starts).

**Services (all `@MainActor ObservableObject`):**

- **`CalendarService`** — EventKit integration; takes `PreferencesService` in its init. Owns two timers: a fetch timer on the configured refresh interval, and a 1-second display timer that evaluates `MeetingAlertPolicy` against the raw tick (so the one-minute alert window can't be skipped by a slow refresh interval) and publishes `now` **only when `displaySignature(at:)` changes**. The signature is every rendered countdown string plus each meeting's in-progress flag, so two instants with the same signature are indistinguishable on screen. Republishing `now` every second rebuilt the `MenuBarExtra` label and relaid out the status item, nudging neighboring menu bar items for no visible gain. Everything that renders a countdown must take `now` explicitly (both the menu bar label and `MeetingRowView`) — a view that calls `Date()` itself would drift from the signature and defeat the gating. Meeting ids come from `Meeting.makeID` (eventIdentifier + start date — recurring occurrences must not share an id).
- **`MeetingURLExtractor`** — pure regex-based URL extraction (Zoom, Google Meet, Teams, WebEx, Whereby, Around, Discord, Slack Huddle, Jitsi), no EventKit dependency, unit tested directly. Patterns live ONLY here — never duplicate them in tests.
- **`MeetingAlertPolicy`** — pure alert-window selection with injectable clock, unit tested directly.
- **`PreferencesService`** — UserDefaults-backed settings: lookahead hours, refresh interval, alert timing, excluded calendars, countdown format, event-name hiding, calendar color, and whether a clear calendar says "No Meetings" (`showNoMeetingsText`, the one preference defaulting to true so existing installs are unchanged). Each `@Published` property persists on `didSet`. `shouldHideEventTitle(hasExternalDisplay:)` combines the manual toggle with the external-display rule.
- **`KeyboardShortcutService`** — Carbon framework global hotkey registration (`RegisterEventHotKey`). Requires Accessibility permission.
- **`DisplayMonitorService`** — publishes `hasExternalDisplay` off `NSApplication.didChangeScreenParametersNotification`, backing the optional auto-hide of the event name. macOS gives sandboxed apps no way to detect screen capture (only private CoreGraphics SPI or the Screen Recording entitlement), so an attached external display is the public stand-in. Uses the *online* display list so mirrored displays count, and treats a desktop Mac's only monitor as not external.
- **`LaunchAtLoginService`** — `SMAppService.mainApp` wrapper.

**Views:**

- **`MenuContentView`** — Main dropdown: meeting list (max 5), calendar access request, toggles, settings/quit buttons.
- **`SettingsView`** — Preferences pickers + calendar exclusion picker. Hosted in `SettingsWindowController` (singleton NSWindow).
- **`MeetingAlertWindow`** — Full-screen overlay alert at `NSWindow.level = .screenSaver`. Managed by `MeetingAlertWindowController` (plain class, not ObservableObject).

**Model:** `Meeting` struct with time-parameterized functions for countdown formatting (`countdownString(at:format:)`, `menuBarTitle(at:format:showTitle:)`, `isHappeningNow(at:)`, `isJustStarting(at:)`) plus parameterless convenience properties for views. `CountdownFormat` (`.abbreviated` → `2h 23m`, `.digital` → `2:23`) lives alongside it in `Meeting.swift` so `test.sh` picks it up without extra wiring.

**Menu bar label — measured constraints.** `MenuBarExtra` does not render an arbitrary view hierarchy into the status item. All three of these were established by experiment on macOS 27, not from documentation:

- It draws the **first image and the first text only, image first**, and silently drops every other view. An `HStack` of `Text`/`Image`/`Text` loses the trailing text and reorders the image to the front; a SwiftUI `Circle` between them never appears at all. A dot *between* the countdown and the event name therefore cannot be its own view.
- It **ignores `Text.monospacedDigit()`**. `|11:11|` and `|88:88|` rendered to identical widths (32.0pt / 41.0pt) with and without the modifier, so a `Text` countdown changes width as digits tick and shoves its neighbors. The countdown is drawn into the image for this reason alone.
- Its `Text` renders at **13pt** (`NSFont.systemFontSize`), *not* the 14pt `NSFont.menuBarFont` used by the menu bar clock. `MenuBarLabelImage.fontSize` must match it or the drawn run looks visibly larger than the event name beside it. Verify by rendering the same letters-only string both ways and comparing ink widths — ink runs ~2pt narrower than advance width, so compare like with like.

`MenuBarLabelImage` draws the glyph, countdown, and optional color dot into one non-template `NSImage`; `menuBarEventName` stays a real `Text`. Dynamic colors such as `NSColor.labelColor` resolve against whichever appearance is drawing — one cached `NSImage` was verified to redraw correctly across light and dark — so no manual redraw on theme change. `Meeting.menuBarCountdown(at:format:showTitle:hasColorDot:)` owns the colon rule: only the abbreviated format takes one, and only when an event name follows and no dot already separates them.

## Key Patterns

- All persistence is UserDefaults — no Core Data or file storage.
- Pure Apple frameworks only: SwiftUI, EventKit, UserNotifications, ServiceManagement, Carbon, AppKit.
- Services are instantiated at the app level and injected downward; no EnvironmentObject usage.
- Deployment target: macOS 14.0. Bundle ID: `com.nextmeeting.app`.

## Git Conventions

- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`
- Branch prefixes: `feat/`, `fix/`, `docs/`, `refactor/`
