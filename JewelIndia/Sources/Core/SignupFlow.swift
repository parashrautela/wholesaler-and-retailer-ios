import Foundation
import Observation

/// The signup hand-off state the web keeps in `sessionStorage`:
/// `auth_identity`, `otp_sent_at`, `otp_remaining_resends`, `otp_locked_until`,
/// `referral_code`, `referral_role`.
///
/// The OTP timing keys are persisted (not just held in memory) so the countdown
/// and the 24-hour lockout survive an app relaunch. On the web they live in
/// `sessionStorage`, which a tab close wipes — persisting them here matches the
/// server's own rate-limit state more closely rather than less.
@MainActor
@Observable
final class SignupFlow {

    /// Latched for the OTP → set-password leg of a **new** signup.
    ///
    /// `verify-otp` installs a real session as a side effect (its tokens come
    /// back as cookies and are adopted by `auth.setSession`). That fires
    /// `authStateChanges`, which would otherwise make `SessionStore` re-route
    /// the whole app — tearing down `AuthFlowView` and the navigation path it
    /// owns before `.setPassword` can be pushed. The set-password screen is
    /// then never seen and the user lands straight on Select Role.
    ///
    /// While this is set, `SessionStore` adopts the user but leaves routing
    /// alone, so the auth stack keeps control until the password is saved.
    /// Google is unaffected: OAuth users never take this leg.
    ///
    /// Static because `SessionStore` is built independently of any
    /// `SignupFlow` instance and only needs this one bit.
    static var isCompletingSignup = false

    /// The normalised identity (`+91XXXXXXXXXX` or a lower-cased email).
    var identity: String? {
        didSet { defaults.set(identity, forKey: Keys.identity) }
    }

    /// From `?ref=` on the entry screen or from a `/join/<code>` landing.
    var referralCode: String? {
        didSet { defaults.set(referralCode, forKey: Keys.referralCode) }
    }

    /// From `?role=`; picks which onboarding the signup lands in.
    var referralRole: UserRole? {
        didSet { defaults.set(referralRole?.rawValue, forKey: Keys.referralRole) }
    }

    /// The door chosen on the first screen, kept across the OTP → password
    /// leg (and a relaunch in the middle of it).
    var chosenRole: UserRole? {
        didSet { defaults.set(chosenRole?.rawValue, forKey: Keys.chosenRole) }
    }

    /// The inviting wholesaler's name, for the "Invited by" banners.
    var invitedBy: String? {
        didSet { defaults.set(invitedBy, forKey: Keys.invitedBy) }
    }

    var otpSentAt: Date? {
        didSet { defaults.set(otpSentAt, forKey: Keys.otpSentAt) }
    }

    var remainingResends: Int {
        didSet { defaults.set(remainingResends, forKey: Keys.remainingResends) }
    }

    var lockedUntil: Date? {
        didSet { defaults.set(lockedUntil, forKey: Keys.lockedUntil) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let identity = "auth_identity"
        static let referralCode = "referral_code"
        static let referralRole = "referral_role"
        static let chosenRole = "signup_role"
        static let invitedBy = "referral_wholesaler"
        static let otpSentAt = "otp_sent_at"
        static let remainingResends = "otp_remaining_resends"
        static let lockedUntil = "otp_locked_until"
    }

    init() {
        identity = defaults.string(forKey: Keys.identity)
        referralCode = defaults.string(forKey: Keys.referralCode)
        referralRole = defaults.string(forKey: Keys.referralRole).flatMap(UserRole.init)
        chosenRole = defaults.string(forKey: Keys.chosenRole).flatMap(UserRole.init)
        invitedBy = defaults.string(forKey: Keys.invitedBy)
        otpSentAt = defaults.object(forKey: Keys.otpSentAt) as? Date
        remainingResends = defaults.object(forKey: Keys.remainingResends) as? Int
            ?? Copy.otpMaxResends
        lockedUntil = defaults.object(forKey: Keys.lockedUntil) as? Date

        // The web drops a stale lockout on mount.
        if let until = lockedUntil, until <= Date() {
            lockedUntil = nil
        }
    }

    /// The web had `role = ?role || sessionStorage.referral_role || "wholesaler"`
    /// — the silent default that made everyone a wholesaler. There is no
    /// default any more: nil means the role question is still to come.
    var signupRole: UserRole? { chosenRole ?? referralRole }

    var isLocked: Bool {
        guard let until = lockedUntil else { return false }
        return until > Date()
    }

    /// Seconds left of the 60-second OTP validity window, resumed from
    /// `otp_sent_at` exactly as `OtpForm` does on mount.
    var otpSecondsLeft: Int {
        guard let sentAt = otpSentAt else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(sentAt))
        return max(0, Copy.otpValiditySeconds - elapsed)
    }

    /// Cleared by `SetPasswordForm` on success.
    func clearOTPState() {
        identity = nil
        otpSentAt = nil
        lockedUntil = nil
        remainingResends = Copy.otpMaxResends
        chosenRole = nil
    }

    /// `Change` on the sign-in screen removes only the identity.
    func clearIdentity() {
        identity = nil
    }

    /// Captures an installed-app universal link such as
    /// `https://app.jewelindia.shop/join/PJ-a8k3x2`.
    @discardableResult
    func captureRetailerInvitation(from url: URL) -> Bool {
        guard url.scheme == "https",
              url.host?.lowercased() == AppConfig.siteURL.host?.lowercased()
        else { return false }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2,
              parts[0].lowercased() == "join",
              !parts[1].isEmpty
        else { return false }

        referralCode = parts[1]
        referralRole = .retailer
        return true
    }

    func clearReferral() {
        referralCode = nil
        referralRole = nil
        invitedBy = nil
    }
}
