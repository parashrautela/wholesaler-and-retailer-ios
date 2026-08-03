import SwiftUI

/// Typography ported from the web app.
///
/// The `.woff2` faces the web loads cannot be read by CoreText, so every face
/// was converted to bare TTF/OTF (identical outlines and metrics) and bundled
/// under `Resources/Fonts`. Names below are the fonts' **PostScript** names,
/// which is what `Font.custom(_:size:)` resolves against.
enum FontFace {
    // Cirka — wholesaler headings, `font-serif` / `font-cirka`.
    static let cirkaLight = "Cirka-Light"
    static let cirkaRegular = "Cirka-Regular"
    static let cirkaBold = "Cirka-Bold"

    // Manrope — wholesaler + employee body, `font-sans` / `font-manrope`.
    static let manropeExtraLight = "Manrope-ExtraLight"
    static let manropeLight = "Manrope-Light"
    static let manropeRegular = "Manrope-Regular"
    static let manropeMedium = "Manrope-Medium"
    static let manropeSemiBold = "Manrope-SemiBold"
    static let manropeBold = "Manrope-Bold"
    static let manropeExtraBold = "Manrope-ExtraBold"

    // Gilroy — the single most-used family in the app (64 usages).
    static let gilroyRegular = "Gilroy-Regular"
    static let gilroyMedium = "Gilroy-Medium"
    static let gilroySemiBold = "Gilroy-SemiBold"
    static let gilroyBold = "Gilroy-Bold"

    // Satoshi — the entire retailer theme.
    static let satoshiLight = "Satoshi-Light"
    static let satoshiRegular = "Satoshi-Regular"
    static let satoshiMedium = "Satoshi-Medium"
    static let satoshiBold = "Satoshi-Bold"
    static let satoshiBlack = "Satoshi-Black"

    // Gilda Display — employee-theme headings.
    static let gildaDisplay = "GildaDisplay-Regular"

    // Deliberately NOT bundled:
    //  • "SF Pro" — the web ships its own copy, but on iOS this *is* the system
    //    face. Shipping Apple's file would be a licence violation and 815 KB of
    //    redundancy, so `Font.sfPro` maps to `.system` instead.
    //  • "Switzer" — the `@font-face` and `@theme` token exist on the web but
    //    have zero usages anywhere in the app.
}

/// The web app swaps its whole type stack per role via the `.theme-wholesaler`,
/// `.theme-retailer` and `.theme-employee` classes in `globals.css`.
/// This reproduces that mapping exactly.
enum RoleTheme {
    case wholesaler
    case retailer
    case employee

    /// Headings (`h1`–`h6`, `.title-font`).
    var headingFace: String {
        switch self {
        case .wholesaler: FontFace.cirkaRegular   // font-family: "Cirka", serif
        case .retailer: FontFace.satoshiBold      // Satoshi, entirely
        case .employee: FontFace.gildaDisplay     // "Gilda Display", serif
        }
    }

    /// Body copy, buttons, inputs, selects, textareas.
    var bodyFace: String {
        switch self {
        case .wholesaler: FontFace.manropeRegular
        case .retailer: FontFace.satoshiRegular
        case .employee: FontFace.manropeRegular
        }
    }
}

extension Font {
    /// Cirka — the serif display face.
    static func cirka(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face =
            switch weight {
            case .light, .ultraLight, .thin: FontFace.cirkaLight
            case .bold, .heavy, .black, .semibold: FontFace.cirkaBold
            default: FontFace.cirkaRegular
            }
        return .custom(face, size: size)
    }

    /// Manrope — the sans body face.
    static func manrope(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face =
            switch weight {
            case .ultraLight, .thin: FontFace.manropeExtraLight
            case .light: FontFace.manropeLight
            case .medium: FontFace.manropeMedium
            case .semibold: FontFace.manropeSemiBold
            case .bold: FontFace.manropeBold
            case .heavy, .black: FontFace.manropeExtraBold
            default: FontFace.manropeRegular
            }
        return .custom(face, size: size)
    }

    /// Gilroy.
    static func gilroy(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face =
            switch weight {
            case .medium: FontFace.gilroyMedium
            case .semibold: FontFace.gilroySemiBold
            case .bold, .heavy, .black: FontFace.gilroyBold
            default: FontFace.gilroyRegular
            }
        return .custom(face, size: size)
    }

    /// Satoshi — the retailer face.
    static func satoshi(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face =
            switch weight {
            case .ultraLight, .thin, .light: FontFace.satoshiLight
            case .medium, .semibold: FontFace.satoshiMedium
            case .bold: FontFace.satoshiBold
            case .heavy, .black: FontFace.satoshiBlack
            default: FontFace.satoshiRegular
            }
        return .custom(face, size: size)
    }

    /// Gilda Display — employee headings.
    static func gilda(_ size: CGFloat) -> Font {
        .custom(FontFace.gildaDisplay, size: size)
    }

    /// The web bundles its own "SF Pro" web font; on iOS that *is* the system
    /// face, so we use the system font here — same typeface, plus optical
    /// sizing and Dynamic Type support that the bundled file cannot provide.
    static func sfPro(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

#if DEBUG
enum FontAudit {
    /// Logs any bundled face that failed to register, so a missing/renamed
    /// file surfaces immediately instead of silently falling back to Helvetica.
    static func verify() {
        let expected = [
            FontFace.cirkaLight, FontFace.cirkaRegular, FontFace.cirkaBold,
            FontFace.manropeExtraLight, FontFace.manropeLight, FontFace.manropeRegular,
            FontFace.manropeMedium, FontFace.manropeSemiBold, FontFace.manropeBold,
            FontFace.manropeExtraBold,
            FontFace.gilroyRegular, FontFace.gilroyMedium, FontFace.gilroySemiBold,
            FontFace.gilroyBold,
            FontFace.satoshiLight, FontFace.satoshiRegular, FontFace.satoshiMedium,
            FontFace.satoshiBold, FontFace.satoshiBlack,
            FontFace.gildaDisplay,
        ]
        let missing = expected.filter { UIFont(name: $0, size: 12) == nil }
        if missing.isEmpty {
            print("[FontAudit] all \(expected.count) faces registered")
        } else {
            print("[FontAudit] MISSING: \(missing.joined(separator: ", "))")
        }
    }
}
#endif
