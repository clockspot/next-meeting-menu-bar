import AppKit
import SwiftUI
import os

/// Tracks whether an external display is attached.
///
/// macOS exposes no sandbox-safe way to learn that another app is capturing the
/// screen — the only routes are private CoreGraphics SPI or the Screen Recording
/// entitlement, neither of which belongs in a calendar app. Being plugged into a
/// projector or second monitor is the closest public signal for "about to
/// present", so that is what drives the optional auto-hide.
@MainActor
final class DisplayMonitorService: ObservableObject {
    private static let logger = Logger(subsystem: "com.nextmeeting.app", category: "DisplayMonitor")

    @Published private(set) var hasExternalDisplay: Bool = false

    // nonisolated(unsafe): read from deinit, which is nonisolated under strict
    // concurrency. Safe because every other access is on the main actor.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        refresh()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        let detected = Self.detectExternalDisplay()
        guard detected != hasExternalDisplay else { return }

        hasExternalDisplay = detected
        Self.logger.info("External display \(detected ? "connected" : "disconnected")")
    }

    /// Queries the *online* display list rather than the active one so mirrored
    /// displays — the classic projector setup — are still counted.
    private static func detectExternalDisplay() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return false
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return false
        }

        let online = Array(displays.prefix(Int(displayCount)))
        let hasBuiltIn = online.contains { CGDisplayIsBuiltin($0) != 0 }

        // On a laptop any non-built-in panel is an external display. A desktop
        // Mac has no built-in panel, so its everyday monitor must not count as
        // one — there, a second display is the presenting signal instead.
        if hasBuiltIn {
            return online.contains { CGDisplayIsBuiltin($0) == 0 }
        }

        return online.count > 1
    }
}
