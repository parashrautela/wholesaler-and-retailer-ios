import SwiftUI

/// Spacing, radii and sizing tokens.
///
/// The web app styles with Tailwind utilities rather than named spacing tokens,
/// so this reproduces Tailwind's default scale (0.25rem = 4pt base) that those
/// utilities compile to. `space(4)` is Tailwind's `p-4` / `gap-4` = 16pt.
enum Spacing {
    /// Tailwind step → points. `step(4)` == `p-4` == 1rem == 16pt.
    static func step(_ n: CGFloat) -> CGFloat { n * 4 }

    static let xs = step(1)     // 4
    static let sm = step(2)     // 8
    static let md = step(3)     // 12
    static let base = step(4)   // 16
    static let lg = step(5)     // 20
    static let xl = step(6)     // 24
    static let xxl = step(8)    // 32
    static let xxxl = step(12)  // 48
    static let huge = step(16)  // 64

    /// The horizontal gutter the web layouts use for mobile content.
    static let screenGutter: CGFloat = 20

    /// `.wholesaler-main-content { padding-bottom: 72px }` — the clearance the
    /// web app reserves for its floating mobile bottom nav. On iOS the system
    /// `TabView` manages this itself via safe-area insets, so this constant is
    /// only for content that deliberately sits outside the tab bar's inset.
    static let floatingNavClearance: CGFloat = 72
}

/// Corner radii observed across the web components.
enum Radius {
    static let sm: CGFloat = 4      // rounded
    static let md: CGFloat = 6      // rounded-md
    static let lg: CGFloat = 8      // rounded-lg
    static let xl: CGFloat = 12     // rounded-xl
    static let xxl: CGFloat = 16    // rounded-2xl
    static let pill: CGFloat = 999  // rounded-full
}

/// Hairline widths. The web uses 1px borders throughout; on iOS a true hairline
/// is `1 / displayScale`, but the web app's 1px reads as a deliberate 1pt rule,
/// so we keep 1pt to preserve the visual weight.
enum Stroke {
    static let hairline: CGFloat = 1
    static let emphasis: CGFloat = 1.5
}
