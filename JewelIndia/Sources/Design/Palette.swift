import SwiftUI

/// Colour tokens transcribed verbatim from the web app's design system.
///
/// Source of truth: `Jewel-India-Frontend/app/globals.css` — the Tailwind v4
/// `@theme` block (`--color-celestique-*`) and the `:root` block.
/// Every value here is an exact hex from that file; nothing is approximated.
enum Palette {

    // MARK: - Celestique tokens (@theme)

    /// `--color-celestique-taupe: #E6DFD3` — skeleton base, muted surfaces.
    static let taupe = Color(hex: 0xE6DFD3)

    /// `--color-celestique-cream: #F5F2EB` — page/section fill.
    static let cream = Color(hex: 0xF5F2EB)

    /// `--color-celestique-dark: #111111` — primary text, dark buttons.
    static let dark = Color(hex: 0x111111)

    /// `--color-celestique-light: #ffffff`
    static let light = Color(hex: 0xFFFFFF)

    /// `--color-celestique-muted: #8C857B` — secondary/helper text.
    static let muted = Color(hex: 0x8C857B)

    /// `--color-celestique-border: #D9D0C5` — hairlines, input borders.
    static let border = Color(hex: 0xD9D0C5)

    // MARK: - Root tokens (:root)

    /// `--background: #FEFEFE` — note this is *not* pure white; `body` uses it.
    static let background = Color(hex: 0xFEFEFE)

    /// `--foreground: var(--color-celestique-dark)`
    static let foreground = dark

    // MARK: - Skeleton gradients

    /// `.catalogue-skeleton-bg` gradient stops: #f0f0f0 → #e0e0e0 → #f0f0f0.
    static let catalogueSkeletonLight = Color(hex: 0xF0F0F0)
    static let catalogueSkeletonMid = Color(hex: 0xE0E0E0)

    /// `.skeleton-shimmer::after` highlight: rgba(245,242,235,0.7).
    static let shimmerHighlight = Color(hex: 0xF5F2EB, opacity: 0.7)

    // MARK: - Status colours
    //
    // These come from the Tailwind palette classes the web app applies to
    // verification-status UI (see globals.css keyframes + onboard/submitted).

    /// `rgba(34, 197, 94, …)` in `@keyframes rippleGreen` — Tailwind green-500.
    static let statusVerified = Color(hex: 0x22C55E)

    /// Amber pending pulse — Tailwind amber-500.
    static let statusPending = Color(hex: 0xF59E0B)

    /// Crimson warning shake — Tailwind red-500.
    static let statusRejected = Color(hex: 0xEF4444)
}

extension Color {
    /// Builds a colour from a 24-bit RGB literal, so tokens can be written as
    /// the same hex that appears in the CSS.
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
