import SwiftUI
import Supabase
import AuthenticationServices
import CryptoKit

/// Which door the person came through, which decides the copy, what a new
/// identity means, and which role a new account is given.
enum EntryMode: Hashable {
    /// "Already have an account?" — an unknown identity is a dead end.
    case signIn
    /// A new wholesaler or (invited) retailer; a known identity just signs in.
    case signup(UserRole)
}

/// `/entry_page/signup` — `components/auth/EntryForm.jsx`.
///
/// Captures an identity, asks the server whether it already exists, and forks
/// into password sign-in, Google, or OTP signup.
struct EntryView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    let mode: EntryMode

    @State private var identity = ""
    @State private var error: String?
    @State private var loading = false
    @State private var googleLoading = false
    @State private var appleLoading = false
    @State private var appleNonce: String?

    /// `disabled = loading || !identity.trim()`
    private var canSubmit: Bool {
        !loading && !googleLoading && !appleLoading && !identity.trimmed.isEmpty
    }

    private var heading: String {
        switch mode {
        case .signIn: Copy.entrySignInHeading
        case .signup(.retailer): Copy.entryRetailerHeading
        case .signup: Copy.entryWholesalerHeading
        }
    }

    private var subheading: String {
        switch mode {
        case .signIn: Copy.entrySignInSubheading
        case .signup: Copy.entrySignupSubheading
        }
    }

    var body: some View {
        AuthLayout(
            title: heading,
            subtitle: subheading,
            onBack: { if !path.isEmpty { path.removeLast() } }
        ) {
            if case .signup(.retailer) = mode {
                InvitationBanner(wholesaler: flow.invitedBy)
                    .padding(.bottom, 16)
            }

            AuthFieldLabel(text: identityLabel)

            AuthTextField(
                text: $identity,
                placeholder: identityPlaceholder,
                keyboard: .emailAddress,
                contentType: .username
            )
            // The input carries a fixed 20 pt bottom margin on the web.
            .padding(.bottom, 20)
            .onChange(of: identity) { _, _ in
                // The web clears the error on every keystroke.
                if error != nil { error = nil }
            }

            if let error {
                AuthErrorRow(message: error)
                    .padding(.bottom, 12)
            }

            AuthOrDivider()
            GoogleButton(isBusy: loading || googleLoading || appleLoading) { Task { await startGoogle() } }
            AppleAuthButton(isBusy: loading || googleLoading || appleLoading, nonce: $appleNonce,
                            onRequest: { appleLoading = true; error = nil; SignupFlow.isCompletingSignup = true },
                            onCompletion: { result in Task { await completeApple(result) } })
                .padding(.top, 10)

            // `<div style={{flex:1}}/>` — pushes the CTA toward the bottom.
            Spacer(minLength: 40)

            AuthPrimaryButton(
                title: loading ? Copy.entrySubmitBusy : Copy.entrySubmitIdle,
                isEnabled: canSubmit
            ) {
                Task { await submit() }
            }
            .padding(.bottom, 16)

            AuthLegalText()
        }
        .animation(Motion.fadeIn, value: error)
        .onAppear {
            if case .signup(let role) = mode { flow.chosenRole = role }
        }
    }

    // MARK: - Submit

    private func submit() async {
        let raw = identity.trimmed
        // 1. Silent no-op on an empty field, exactly as the web does.
        guard !raw.isEmpty else { return }

        if case .signIn = mode, !Credentials.isEmail(raw) {
            error = "Sign in with your email and password. Phone number sign-in isn't available."
            return
        }

        loading = true
        error = nil
        defer { loading = false }

        // 2/3. Email passes through; anything else must be a valid Indian mobile.
        let normalized: String
        if Credentials.isEmail(raw) {
            normalized = raw
        } else {
            let check = Credentials.validateIndianMobile(raw)
            guard check.valid, let e164 = check.normalized else {
                error = Copy.invalidMobile
                return
            }
            normalized = e164
        }

        do {
            let result = try await JewelAPI.checkUser(identity: normalized)

            if result.exists {
                if result.provider == "google" {
                    await startGoogle()
                    return
                }
                flow.identity = normalized
                path.append(.signIn(identity: normalized))
                return
            }

            // Sign-in only knows existing accounts; a new one has to pick a
            // door first, or it would silently become a wholesaler again.
            guard case .signup = mode else {
                error = Copy.entryNoAccount
                return
            }

            // New identity → send the OTP.
            let otp = try await JewelAPI.sendOTP(identity: normalized)
            flow.identity = normalized
            flow.otpSentAt = Date()
            if let remaining = otp.remainingResends { flow.remainingResends = remaining }
            path.append(.verifyOTP)

        } catch let apiError as JewelAPI.APIError {
            error = apiError.message
        } catch {
            self.error = Copy.networkError
        }
    }

    // MARK: - Google

    private var identityLabel: String {
        if case .signIn = mode { return Copy.signInIdentityLabel }
        return Copy.entryFieldLabel
    }

    private var identityPlaceholder: String {
        if case .signIn = mode { return Copy.signInEmailPlaceholder }
        return Copy.entryFieldPlaceholder
    }

    private func startGoogle() async {
        guard !googleLoading else { return }
        googleLoading = true
        defer { googleLoading = false }
        // The session lands before this screen knows the account's role, and
        // the auth stream would route on it at once — to the role question
        // for a new account. Hold routing until the door chosen here has
        // been recorded.
        SignupFlow.isCompletingSignup = true
        switch await GoogleSignIn.signIn() {
        case .cancelled:
            SignupFlow.isCompletingSignup = false
        case .failed(let message):
            SignupFlow.isCompletingSignup = false
            error = message
        case .signedIn:
            await routeAfterSocialSignIn()
        }
    }

    /// An existing account keeps its role. A new one takes the door it came
    /// through; through "Sign in" there is no door, so the role question
    /// follows.
    private func routeAfterSocialSignIn() async {
        guard let user = SupabaseManager.client.auth.currentSession?.user else {
            SignupFlow.isCompletingSignup = false
            return
        }
        let existingRole = await AuthRouter.resolveRole(for: user)
        SignupFlow.isCompletingSignup = false
        if existingRole == nil, case .signup(let role) = mode {
            if let message = await session.setUserRole(role) {
                error = message
            }
        } else {
            await session.refreshDestination()
        }
    }

    private func completeApple(_ result: Result<ASAuthorization, Error>) async {
        defer { appleLoading = false }
        switch await AppleAuth.exchange(result, nonce: appleNonce) {
        case .signedIn:
            await routeAfterSocialSignIn()
        case .cancelled:
            SignupFlow.isCompletingSignup = false
        case .failed(let message):
            SignupFlow.isCompletingSignup = false
            error = message
        }
        appleNonce = nil
    }
}

struct AppleAuthButton: View {
    var isBusy: Bool
    @Binding var nonce: String?
    let onRequest: () -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(.continue, onRequest: { request in
            let raw = AppleAuth.randomNonce()
            nonce = raw
            request.requestedScopes = [.email, .fullName]
            request.nonce = AppleAuth.sha256Hex(raw)
            onRequest()
        }, onCompletion: onCompletion)
        .signInWithAppleButtonStyle(.whiteOutline)
        .frame(height: 52)
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
        .accessibilityLabel("Continue with Apple")
    }
}

enum AppleAuth {
    enum Outcome { case signedIn, cancelled, failed(String) }

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    static func exchange(_ result: Result<ASAuthorization, Error>, nonce: String?) async -> Outcome {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue { return .cancelled }
            return .failed(error.localizedDescription)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce else { return .failed("Apple did not provide a valid sign-in token. Please try again.") }
            do {
                _ = try await SupabaseManager.client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
                )
                // Apple provides the name only on first authorization.
                if let fullName = credential.fullName {
                    let name = [fullName.givenName, fullName.familyName].compactMap { $0 }.joined(separator: " ")
                    if !name.isEmpty {
                        try? await SupabaseManager.client.auth.update(user: UserAttributes(data: ["full_name": .string(name)]))
                    }
                }
                return .signedIn
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }
}

/// The inline Google "G" the web draws as four SVG paths, with the same fills.
struct GoogleButton: View {
    var isBusy: Bool
    var title: String = Copy.entryGoogleIdle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(isBusy ? Copy.entryGoogleBusy : title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AuthColor.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: 0x747775), lineWidth: 1)
            }
            .opacity(isBusy ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
