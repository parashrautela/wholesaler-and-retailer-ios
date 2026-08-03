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
        static let otpSentAt = "otp_sent_at"
        static let remainingResends = "otp_remaining_resends"
        static let lockedUntil = "otp_locked_until"
    }

    init() {
        identity = defaults.string(forKey: Keys.identity)
        referralCode = defaults.string(forKey: Keys.referralCode)
        referralRole = defaults.string(forKey: Keys.referralRole).flatMap(UserRole.init)
        otpSentAt = defaults.object(forKey: Keys.otpSentAt) as? Date
        remainingResends = defaults.object(forKey: Keys.remainingResends) as? Int
            ?? Copy.otpMaxResends
        lockedUntil = defaults.object(forKey: Keys.lockedUntil) as? Date

        // The web drops a stale lockout on mount.
        if let until = lockedUntil, until <= Date() {
            lockedUntil = nil
        }
    }

    /// `role = ?role || sessionStorage.referral_role || "wholesaler"`.
    var signupRole: UserRole { referralRole ?? .wholesaler }

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
    }

    /// `Change` on the sign-in screen removes only the identity.
    func clearIdentity() {
        identity = nil
    }
}
