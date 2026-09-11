import AppKit
import SwiftUI

/// Draws the leading run of the menu bar label — calendar glyph, countdown, and
/// optionally the meeting's calendar color — as one image.
///
/// Two `MenuBarExtra` limits force this, both measured rather than assumed:
///
/// 1. It renders only the **first image and the first text, image first**, and
///    silently drops every other view. An `HStack` of `Text`/`Image`/`Text`
///    loses the trailing text; a SwiftUI `Circle` between them never appears.
///    So a dot between the countdown and the event name cannot be its own view.
/// 2. It **ignores `Text.monospacedDigit()`**. Rendering `|11:11|` and
///    `|88:88|` with and without the modifier produced identical widths
///    (32.0pt and 41.0pt in both cases), so a `Text` countdown changes width
///    as its digits change and shoves its neighbors around once a second.
///
/// Drawing the countdown here is the only way to get tabular figures into the
/// menu bar. The event name stays a real `Text`, since it has no digits to
/// jitter and benefits from the system's own truncation.
@MainActor
enum MenuBarLabelImage {
    private static let dotDiameter: CGFloat = 7
    private static let gap: CGFloat = 5

    /// The dot's own gaps, which are deliberately lopsided so that it *looks*
    /// centered. With an equal 5pt on both sides it measured 6.5pt of clear ink
    /// before and 8.5pt after: the countdown's right side bearing and the event
    /// name's left side bearing are not the same, and MenuBarExtra adds its own
    /// spacing between image and text. Splitting that 2pt difference evens it.
    private static let dotLeadingGap: CGFloat = 6
    private static let dotTrailingGap: CGFloat = 4

    /// Space left after the countdown when the event name follows it with no
    /// dot between them. `MenuBarExtra` already inserts spacing of its own
    /// between image and text, so this is only the remainder — and at the 5pt
    /// used elsewhere the result read as wider than a word space. Measured
    /// against a single `Text` reading "HHH: HHH", where an ordinary space
    /// leaves 12px of clear ink after the colon: 5pt here left 19px, 1.5pt
    /// lands on the reference.
    private static let nameTrailingGap: CGFloat = 1.5

    /// `MenuBarExtra` centers the label image on a slightly different axis than
    /// the `Text` beside it. With every element centered in the image, the drawn
    /// run measured 1px low against the native text on a 2x display — ink at
    /// y 24...42 where the `Text` sat at 23...41, same height, just lower.
    /// Raising the content by half a point puts the two on one baseline.
    private static let verticalNudge: CGFloat = 0.5

    /// The size `MenuBarExtra` renders its own `Text` at, so the drawn run and
    /// the event name beside it match.
    ///
    /// Measured, not assumed: rendering `|Pick up Mom|` both ways put SwiftUI's
    /// `Text` at 83.0pt of ink against 77.0pt for this image at 12pt. Ink runs
    /// about 2.1pt narrower than the advance width for that string, which puts
    /// `Text` at roughly 85.1pt of advance — 13pt (84.73). The same correction
    /// fits the digit strings too. `NSFont.menuBarFont` is 14pt, the menu bar
    /// *clock's* size, and is visibly larger than the event name.
    private static let fontSize: CGFloat = NSFont.systemFontSize

    /// - Parameters:
    ///   - text: the countdown as it should read, including any trailing colon.
    ///   - color: calendar color for the trailing dot, or nil to omit the dot.
    ///   - trailingGap: reserve space after the run, for when an event name
    ///     follows — `MenuBarExtra` butts the text straight against the image.
    static func image(text: String,
                      color: Color?,
                      trailingGap: Bool,
                      symbolName: String = "calendar") -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        let textSize = attributed.size()

        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular))
        let symbolSize = symbol?.size ?? .zero
        let symbolRun = symbol == nil ? 0 : symbolSize.width + gap

        let dotRun = color == nil ? 0 : dotLeadingGap + dotDiameter
        let trailing = trailingGap ? (color == nil ? nameTrailingGap : dotTrailingGap) : 0
        let contentHeight = max(max(symbolSize.height, textSize.height), dotDiameter)
        let size = NSSize(
            width: symbolRun + textSize.width + dotRun + trailing,
            // Grown by the nudge on both sides so raising the content cannot
            // clip whichever element is tallest.
            height: contentHeight + verticalNudge * 2
        )

        let image = NSImage(size: size, flipped: false) { rect in
            var x: CGFloat = 0
            let centerY = rect.height / 2 + verticalNudge

            if let symbol {
                let symbolRect = NSRect(
                    x: x,
                    y: centerY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                // SF Symbols are template images; drawn into a plain bitmap they
                // arrive black, so tint them the way the status item would.
                symbol.draw(in: symbolRect)
                NSColor.labelColor.set()
                symbolRect.fill(using: .sourceAtop)
                x += symbolRun
            }

            attributed.draw(at: NSPoint(x: x, y: centerY - textSize.height / 2))
            x += textSize.width

            if let color {
                x += dotLeadingGap
                NSColor(color).setFill()
                NSBezierPath(ovalIn: NSRect(
                    x: x,
                    y: centerY - dotDiameter / 2,
                    width: dotDiameter,
                    height: dotDiameter
                )).fill()
            }

            return true
        }

        // Not a template: a template image is flattened to a monochrome
        // silhouette, which would lose the calendar color. The text and glyph
        // are drawn in NSColor.labelColor instead, which resolves against
        // whichever appearance is drawing, so one image still follows the theme.
        image.isTemplate = false
        image.accessibilityDescription = text
        return image
    }
}
