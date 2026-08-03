import Foundation

/// Exact port of `Jewel-India-Frontend/lib/utils/credentials.js`.
/// The regexes and the normalisation branches are reproduced character for
/// character so the client accepts and rejects exactly what the web accepts.
enum Credentials {

    /// `/^[^\s@]+@[^\s@]+\.[^\s@]+$/` — the loose email test used by
    /// EntryForm, check-user, send-otp, verify-otp and signIn.
    static func isEmail(_ input: String) -> Bool {
        input.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
            options: .regularExpression
        ) != nil
    }

    struct MobileCheck {
        let valid: Bool
        let normalized: String?
    }

    /// Port of `validateIndianMobile(input)`.
    ///
    /// ```js
    /// digits = String(input).replace(/\D/g, "")
    /// /^[6-9]\d{9}$/   -> +91<digits>
    /// /^0[6-9]\d{9}$/  -> +91<digits.slice(1)>
    /// /^91[6-9]\d{9}$/ -> +<digits>
    /// ```
    static func validateIndianMobile(_ input: String) -> MobileCheck {
        let digits = input.filter(\.isNumber)

        func matches(_ pattern: String) -> Bool {
            digits.range(of: pattern, options: .regularExpression) != nil
        }

        if matches(#"^[6-9]\d{9}$"#) {
            return MobileCheck(valid: true, normalized: "+91\(digits)")
        }
        if matches(#"^0[6-9]\d{9}$"#) {
            return MobileCheck(valid: true, normalized: "+91\(digits.dropFirst())")
        }
        if matches(#"^91[6-9]\d{9}$"#) {
            return MobileCheck(valid: true, normalized: "+\(digits)")
        }
        return MobileCheck(valid: false, normalized: nil)
    }

    /// The server-side password rule enforced by `POST /api/auth/set-password`:
    /// `/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,}$/`
    ///
    /// The client checklist on the Set Password screen is expressed as four
    /// separate predicates (see `PasswordRule`), which together are equivalent.
    static func meetsServerPasswordRule(_ password: String) -> Bool {
        password.range(
            of: #"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,}$"#,
            options: .regularExpression
        ) != nil
    }
}

/// The four checklist rules rendered on `/entry_page/signup/set-password`,
/// ported from the `RULES` array in `components/auth/SetPasswordForm.jsx`.
/// Labels are verbatim, including the en-dashes.
enum PasswordRule: String, CaseIterable, Identifiable {
    case length
    case upper
    case lower
    case special

    var id: String { rawValue }

    var label: String {
        switch self {
        case .length: "At least 8 characters"
        case .upper: "1 uppercase letter (A–Z)"
        case .lower: "1 lowercase letter (a–z)"
        case .special: "1 number (0–9) and 1 special character (!@#$%^&*...)"
        }
    }

    func passes(_ p: String) -> Bool {
        switch self {
        case .length:
            p.count >= 8
        case .upper:
            p.range(of: "[A-Z]", options: .regularExpression) != nil
        case .lower:
            p.range(of: "[a-z]", options: .regularExpression) != nil
        case .special:
            p.range(of: "[0-9]", options: .regularExpression) != nil
                && p.range(
                    of: #"[!@#$%^&*()\-_=+\[\]{};:'",.<>/?\\|`~]"#,
                    options: .regularExpression
                ) != nil
        }
    }

    static func allPass(_ p: String) -> Bool {
        allCases.allSatisfy { $0.passes(p) }
    }
}
