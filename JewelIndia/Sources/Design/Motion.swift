import SwiftUI

/// Animation curves and durations transcribed from the `@keyframes` blocks in
/// `Jewel-India-Frontend/app/globals.css`.
///
/// The web app leans on one signature curve — `cubic-bezier(0.16, 1, 0.3, 1)`
/// (a strong ease-out) — for nearly every entrance. SwiftUI's `.timingCurve`
/// takes the same four control points, so these are exact, not eyeballed.
enum Motion {

    // MARK: - Curves

    /// `cubic-bezier(0.16, 1, 0.3, 1)` — the app's signature ease-out.
    static func signature(_ duration: Double) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    /// `cubic-bezier(0.4, 0, 0.2, 1)` — Material-style standard easing,
    /// used by the onboarding checkmark draw.
    static func standard(_ duration: Double) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }

    /// `cubic-bezier(0.36, 0.07, 0.19, 0.97)` — the rejection shake.
    static func shake(_ duration: Double) -> Animation {
        .timingCurve(0.36, 0.07, 0.19, 0.97, duration: duration)
    }

    // MARK: - Named animations
    //
    // Each maps 1:1 to a CSS utility class.

    /// `.animate-fade-in-up` — fadeInUp 0.5s, translateY(10px) → 0.
    static let fadeInUp = signature(0.5)
    static let fadeInUpOffset: CGFloat = 10

    /// `.animate-fade-in` — fadeIn 0.4s ease-out.
    static let fadeIn = Animation.easeOut(duration: 0.4)

    /// `.animate-scale-in` — scaleIn 0.4s, scale(0.98) → 1.
    static let scaleIn = signature(0.4)
    static let scaleInStart: CGFloat = 0.98

    /// `.card-enter.is-visible` — cardEnter 0.55s, translateY(28px) → 0.
    static let cardEnter = signature(0.55)
    static let cardEnterOffset: CGFloat = 28

    /// `.onboard-page-transition` — onboardFadeIn 350ms, translateY(8px) → 0.
    static let onboardPage = signature(0.35)
    static let onboardPageOffset: CGFloat = 8

    /// `.animate-step-fade` — stepFadeIn 400ms, translateY(6px) → 0.
    static let stepFade = signature(0.4)
    static let stepFadeOffset: CGFloat = 6

    /// `.animate-check-draw` — checkDraw 350ms, stroke-dashoffset 24 → 0.
    static let checkDraw = standard(0.35)

    /// `.animate-ripple-green` — rippleGreen 600ms.
    static let rippleGreen = signature(0.6)

    /// `.animate-pulse-amber` — pulseAmber 2s ease-in-out infinite.
    static let pulseAmber = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)

    /// `.animate-spin-slow` — spinClockHand 8s linear infinite.
    static let spinSlow = Animation.linear(duration: 8).repeatForever(autoreverses: false)

    /// `.animate-shake-red` — softShake 500ms.
    static let shakeRed = shake(0.5)

    /// `.skeleton-shimmer::after` — shimmer 1.6s ease-in-out infinite.
    static let shimmer = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: false)

    /// `.catalogue-skeleton-bg` — catalogue-shimmer 1.5s linear infinite.
    static let catalogueShimmer = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

    /// The web app's staggered `.delay-100 / -200 / -300` helpers.
    static func delay(_ index: Int, step: Double = 0.1) -> Double {
        Double(index) * step
    }
}

// MARK: - Transitions

extension AnyTransition {
    /// Matches `.animate-fade-in-up`.
    static var fadeInUp: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: Motion.fadeInUpOffset)),
            removal: .opacity
        )
    }

    /// Matches `.animate-scale-in`.
    static var scaleIn: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: Motion.scaleInStart)),
            removal: .opacity
        )
    }

    /// Matches `.onboard-page-transition`.
    static var onboardPage: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: Motion.onboardPageOffset)),
            removal: .opacity
        )
    }
}

// MARK: - Reduced motion

/// `globals.css` disables every entrance animation under
/// `@media (prefers-reduced-motion: reduce)`. This is the iOS equivalent —
/// it honours the system "Reduce Motion" switch the same way.
struct ReducedMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: UUID())
    }
}

extension View {
    /// Applies an entrance animation unless the user has asked for reduced
    /// motion, mirroring the web app's `prefers-reduced-motion` overrides.
    func motion(_ animation: Animation) -> some View {
        modifier(ReducedMotionAware(animation: animation))
    }
}
