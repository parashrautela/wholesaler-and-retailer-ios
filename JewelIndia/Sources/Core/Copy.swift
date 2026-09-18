import Foundation

/// Every user-facing string in the auth + shell surface, copied verbatim from
/// the web app. Centralising them keeps the parity pass mechanical: a diff
/// against the web source is a diff against this file.
///
/// Punctuation is significant and intentional — the web mixes `...` and `…`,
/// uses en-dashes in the password rules, and ends the same sentence with and
/// without a period on different screens. All of that is preserved.
enum Copy {

    // MARK: - Shared chrome (AuthLayout)

    static let brandMark = "JI"
    static let brandWordmark = "Jewels India"
    static let legal = "By continuing, you agree to our "
    static let legalTerms = "Terms of Service"
    static let legalAnd = " and "
    static let legalPrivacy = "Privacy Policy"

    // MARK: - Entry screen · /entry_page/signup

    static let entryHeading = "Welcome"
    static let entrySubheading = "Sign in to explore Jewellery all over India"
    static let entryFieldLabel = "Email or Phone number"
    static let entryFieldPlaceholder = "Enter"
    static let entryDivider = "OR"
    static let entryGoogleIdle = "Google"
    static let entryGoogleBusy = "Redirecting..."
    static let entrySubmitIdle = "Continue"
    static let entrySubmitBusy = "Checking..."

    static let bannedError = "Your account has been banned. Please use a different number or email."
    static let invalidMobile = "Please enter a valid 10-digit Indian mobile number."
    static let genericFailure = "Something went wrong. Please try again."
    static let otpSendFailure = "Failed to send OTP. Please try again."
    static let networkError = "Network error. Please check your connection and try again."
    /// Shown in the red error slot even though it is a success path — matching the web.
    static let googleRedirect = "You signed up with Google. Redirecting..."

    /// Not a web string. Google sign-in returns to the app via
    /// `jewelindia://auth/callback`, which must be listed under Supabase →
    /// Authentication → URL Configuration → Redirect URLs. Without it Supabase
    /// redirects to the website instead and the app never receives a session.
    static let googleRedirectNotConfigured = "Couldn't complete Google sign-in. The app's redirect URL isn't allow-listed in Supabase yet — use your email or phone number for now."

    // MARK: - Sign in · /entry_page/signin

    static let signInHeading = "Welcome"
    static let signInSubheading = "Sign in to explore Jewellery all over India"
    static let signInIdentityLabel = "Email or Phone number"
    static let signInChange = "Change"
    static let signInPasswordLabel = "Password"
    static let signInPasswordPlaceholder = "Enter your password"
    static let signInForgot = "Forgot Password?"
    static let signInRemember = "Remember me"
    static let signInSubmitIdle = "Continue"
    static let signInSubmitBusy = "Signing in..."
    static let employeeDeactivated = "Your account has been deactivated by the store administrator."

    // MARK: - OTP · /entry_page/signup/verify-otp

    static let otpHeadingLine1 = "Create a"
    /// Hard-coded on the web even when `?role=retailer`.
    static let otpHeadingLine2 = "Wholesaler Account"
    static let otpSentPrefix = "The 8-digit OTP has been sent to you at"
    static let otpEdit = "Edit"
    /// Hard-coded on the web — the "2" never reflects the real remaining count.
    static let otpWrong = "Invalid OTP! 2 attempts remaining"
    static let otpIncomplete = "Please enter the complete 8-digit code."
    static let otpGenericError = "Invalid OTP. Please try again or resend."
    static let otpLocked = "All 5 resend attempts used. Priority locked."
    static let otpValidPrefix = "OTP valid for "
    static let otpResendIdle = "Resend OTP"
    /// Note the single-character ellipsis (U+2026), unlike the other busy labels.
    static let otpResendBusy = "Sending…"
    static let otpInfoNote = "Only wholesalers accounts will be verified. Retailers will require an invite to sign in."
    static let otpSubmitIdle = "Continue"
    static let otpSubmitBusy = "Verifying..."

    static let otpValiditySeconds = 60
    static let otpResendCooldownSeconds = 30
    static let otpMaxResends = 5
    static let otpDigitCount = 8

    // MARK: - Set password · /entry_page/signup/set-password

    static let setPasswordHeading = "Set Password"
    static let setPasswordSubline = "Password must contain at least 8 characters and include a capital letter, a small letter, a number and a special character"
    static let setPasswordLabel = "Password"
    static let setPasswordConfirmLabel = "Confirm Password"
    /// 10 × U+2022
    static let setPasswordPlaceholder = "••••••••••"
    static let setPasswordMismatch = "Passwords do not match"
    static let setPasswordFallbackError = "Failed to set password. Please try again."
    static let setPasswordInfoNote = "Only wholesalers accounts will be verified. Retailers will require an invite to sign in."
    static let setPasswordSubmitIdle = "Continue"
    static let setPasswordSubmitBusy = "Verifying..."

    // MARK: - Forgot password · /forgot-password

    static let forgotHeading = "Reset your password"
    static let forgotSubheading = "Enter your email to receive a password reset link."
    static let forgotLabel = "Email address"
    static let forgotPlaceholder = "Enter your email"
    static let forgotSubmitIdle = "Send reset link"
    static let forgotSubmitBusy = "Sending reset link..."
    static let forgotBackToSignIn = "Back to sign in"
    static let forgotSuccessTitle = "Check your email"
    static let forgotSuccessBody = "We've sent a password reset link to your email address. Please check your inbox."
    static let forgotReturn = "Return to sign in"
    static let forgotEmailRequired = "Email is required"
    static let forgotServerError = "Server error while verifying email."
    static let forgotNoAccount = "No account found with this email address."

    // MARK: - Update password · /update-password

    static let updateHeading = "Set new password"
    static let updateSubheading = "Please enter your new password below."
    static let updateNewLabel = "New Password"
    static let updateNewPlaceholder = "Enter new password"
    static let updateConfirmLabel = "Confirm Password"
    static let updateConfirmPlaceholder = "Confirm new password"
    /// Trailing period — differs from `setPasswordMismatch`, deliberately.
    static let updateMismatch = "Passwords do not match."
    static let updateTooShort = "Password must be at least 6 characters long."
    static let updateSubmitIdle = "Update password"
    static let updateSubmitBusy = "Updating..."
    static let updateSuccessTitle = "Password updated!"
    static let updateSuccessBody = "Your password has been changed successfully."
    /// The web's label says "Dashboard" but links to sign-in. Kept verbatim.
    static let updateSuccessCTA = "Continue to Dashboard"

    // MARK: - Select role · /select-role

    static let selectRoleHeading = "How will you use Jewels India?"
    static let selectRoleSub = "Select your role so we can tailor your experience."
    static let selectRoleSub2 = "This cannot be changed later."
    static let selectRoleWholesalerTitle = "Wholesaler"
    static let selectRoleWholesalerBody = "Upload jewellery products, manage your catalogue, and connect with retailers."
    static let selectRoleRetailerTitle = "Retailer"
    static let selectRoleRetailerBody = "Browse the full jewellery catalogue, discover designs, and source from wholesalers."
    static let selectRoleEmpty = "Please choose a role to continue."
    static let selectRoleInvalid = "Invalid role."
    static let selectRoleNotAuthed = "Not authenticated."
    static let selectRoleButton = "Complete Selection"
    static func selectRoleSignedInAs(_ email: String) -> String { "Signed in as \(email)" }

    // MARK: - The three doors (not web strings: the web has no such screen)

    static let doorsHeading = "Welcome"
    static let doorsSignedInHeading = "One more thing"
    static let doorsSubheading = "How will you use Jewels India?"
    static let doorWholesalerTitle = "I'm a wholesaler"
    static let doorWholesalerBody = "Show your designs to retailers across India. Jewels India verifies every wholesaler."
    static let doorRetailerTitle = "I'm a retailer"
    static let doorRetailerBody = "Source designs from wholesalers. You'll need the invitation code a wholesaler shared with you."
    static let doorStaffTitle = "I work at a store"
    static let doorStaffBody = "Sign in with the username your store gave you, or with Google."
    static let doorsHaveAccount = "Already have an account?"
    static let doorsSignIn = "Sign in"
    static let roleAlreadySet = "This account is already set up as something else. Sign in with a different account."
    static let roleNotAllowed = "Staff accounts are created by the store — ask your store owner to add you."

    // MARK: - Invitation code

    static let inviteHeading = "Your invitation"
    static let inviteSubheading = "Retailers join Jewels India with an invitation from a wholesaler. Enter the code they shared with you."
    static let inviteFieldLabel = "Invitation code"
    static let inviteFieldPlaceholder = "PJ-A8K3X2"
    static let inviteChecking = "Checking…"
    static let inviteValid = "This invitation is good."
    static let inviteContinue = "Continue"
    static let inviteNoCode = "Don't have a code? Ask a wholesaler you work with."
    static let inviteCodeEmpty = "Enter your invitation code."
    static let invitationDetected = "Retailer invitation detected"
    static let invitationNext = "Continue with your mobile number, email or Google. You can enter the app after Jewels India verifies your store."
    static func invitedBy(_ name: String) -> String { "Invited by \(name)" }
    static func inviteCodeReason(_ reason: String?) -> String {
        switch reason {
        case "expired": "This invitation has expired. Ask the wholesaler for a new one."
        case "used": "This invitation has already been used."
        case "inactive": "This invitation isn't active any more. Ask the wholesaler for a new one."
        case "no_code": inviteCodeEmpty
        default: "We couldn't find that code. Check it with the wholesaler who invited you."
        }
    }

    // MARK: - Entry, per door

    static let entrySignInHeading = "Welcome back"
    static let entrySignInSubheading = "Sign in to explore Jewellery all over India"
    static let entryWholesalerHeading = "Create a wholesaler account"
    static let entryRetailerHeading = "Create a retailer account"
    static let entrySignupSubheading = "Continue with your mobile number, email or Google."
    static let entryNoAccount = "We couldn't find an account for that. New to Jewels India? Go back and choose how you'll use it."
    static let otpHeadingRetailer = "Retailer Account"
    static let otpInfoNoteWholesaler = "Jewels India reviews every wholesaler before they can start."
    static let otpInfoNoteRetailer = "Your store will be reviewed by Jewels India once you've sent your details."

    // MARK: - Staff sign-in

    static let staffSubheading = "Sign in with the username and password your store gave you."
    static let staffUsernameLabel = "Username"
    static let staffUsernamePlaceholder = "priya.pinejewels"
    static let staffForgotHint = "Forgot your password? Your store owner can reset it from their staff list."
    static let staffGoogle = "Continue with Google"
    static let staffWrongCredentials = "That username and password don't match. Check them with your store owner."
    static let staffNotInvited = "This Google account isn't on any store's staff list yet. Ask your store owner to add it."
    static let staffGoogleRequired = "Staff added by email sign in with Google."
    static let staffAccountHasAnotherRole = "This Google account already belongs to a wholesaler or retailer. Use a different one for staff."

    // MARK: - Unreachable

    static let unreachableTitle = "Couldn't reach Jewels India"
    static let unreachableBody = "Check your connection and try again."
    static let unreachableRetry = "Try again"
    static let unreachableRetrying = "Trying…"

    // MARK: - Employee login · /employee-login

    static let employeeHeadingLine1 = "The catalogue"
    static let employeeHeadingLine2 = "is waiting."
    static let employeeEmailLabel = "Email"
    static let employeeEmailPlaceholder = "Enter"
    static let employeePasswordLabel = "Password"
    /// 12 × U+2022
    static let employeePasswordPlaceholder = "••••••••••••"
    static let employeeSubmitIdle = "Get Started"
    static let employeeSubmitBusy = "Signing in..."

    // MARK: - Logout confirmation (wholesaler Sidebar)

    static let logoutTitle = "Confirm Logout"
    static let logoutBody = "Are you sure you want to logout?"
    static let logoutCancel = "Cancel"
    static let logoutConfirm = "Logout"

    // MARK: - Tab labels (from the mobile bottom nav)

    enum WholesalerTab {
        static let home = "Home"
        static let catalogue = "Catalogue"
        static let chamak = "Chamak"
        static let orders = "Orders"
        static let chat = "Chat"
        static let addRetailer = "Add Retailer"
        static let inviteRetailer = "Invite Retailer"
    }

    enum RetailerTab {
        static let dashboard = "Dashboard"
        static let catalogue = "Catalogue"
        static let employees = "Employees"
        static let yourTaste = "Discover"
        static let orders = "Orders"
    }

    enum EmployeeTab {
        static let home = "Home"
        static let catalogue = "Catalogue"
        static let queries = "Queries"
        static let orders = "Orders"
    }
}
