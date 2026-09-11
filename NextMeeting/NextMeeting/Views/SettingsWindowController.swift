import AppKit
import SwiftUI

@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showSettings(
        preferencesService: PreferencesService,
        keyboardShortcutService: KeyboardShortcutService,
        calendarService: CalendarService
    ) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            preferencesService: preferencesService,
            keyboardShortcutService: keyboardShortcutService,
            calendarService: calendarService,
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        )

        let hostingView = NSHostingView(rootView: settingsView)

        // Resizable, and tall enough to show the form without clipping. The
        // form scrolls, so a short window stays usable; contentMinSize keeps it
        // from being dragged down to nothing.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NextMeeting Settings"
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 460, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
