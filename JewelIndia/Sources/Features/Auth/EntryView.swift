import SwiftUI
import Supabase

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

    /// `disabled = loading || !identity.trim()`
    private var canSubmit: Bool {
        !loading && !googleLoading && !identity.trimmed.isEmpty
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
        AuthLayout(title: heading, subtitle: subheading) {
            if case .signup(.retailer) = mode {
                InvitationBanner(wholesaler: flow.invitedBy)
                    .padding(.bottom, 16)
            }

            AuthFieldLabel(text: Copy.entryFieldLabel)

            AuthTextField(
                text: $identity,
                placeholder: Copy.entryFieldPlaceholder,
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

            // Source order is input → error → OR divider → Google.
            AuthOrDivider()

            GoogleButton(isBusy: googleLoading) { Task { await startGoogle() } }

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
                    // The web shows this in the red error slot — kept verbatim.
                    error = Copy.googleRedirect
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

    private func startGoogle() async {
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
            await routeAfterGoogleSignIn()
        }
    }

    /// An existing account keeps its role. A new one takes the door it came
    /// through; through "Sign in" there is no door, so the role question
    /// follows.
    private func routeAfterGoogleSignIn() async {
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
}

/// The inline Google "G" the web draws as four SVG paths, with the same fills.
struct GoogleButton: View {
    var isBusy: Bool
    var title: String = Copy.entryGoogleIdle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleGlyph().frame(width: 18, height: 18)
                Text(isBusy ? Copy.entryGoogleBusy : title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AuthColor.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AuthColor.hairline, lineWidth: 1)
            }
            .opacity(isBusy ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

/// Google's four-colour mark, reproduced from the SVG paths in `EntryForm.jsx`
/// with the same fills: #4285F4, #34A853, #FBBC05, #EA4335.
struct GoogleGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 18
            func path(_ build: (inout Path) -> Void) -> Path {
                var p = Path()
                build(&p)
                return p.applying(CGAffineTransform(scaleX: s, y: s))
            }

            // Blue — right arm of the G.
            context.fill(
                path { p in
                    p.move(to: CGPoint(x: 17.64, y: 9.2))
                    p.addLine(to: CGPoint(x: 17.64, y: 7.36))
                    p.addLine(to: CGPoint(x: 9, y: 7.36))
                    p.addLine(to: CGPoint(x: 9, y: 10.85))
                    p.addLine(to: CGPoint(x: 13.84, y: 10.85))
                    p.addCurve(
                        to: CGPoint(x: 12.05, y: 13.56),
                        control1: CGPoint(x: 13.64, y: 11.97),
                        control2: CGPoint(x: 13.0, y: 12.92)
                    )
                    p.addLine(to: CGPoint(x: 14.96, y: 15.8))
                    p.addCurve(
                        to: CGPoint(x: 17.64, y: 9.2),
                        control1: CGPoint(x: 16.66, y: 14.25),
                        control2: CGPoint(x: 17.64, y: 11.95)
                    )
                    p.closeSubpath()
                },
                with: .color(Color(hex: 0x4285F4))
            )

            // Green — lower-left sweep.
            context.fill(
                path { p in
                    p.move(to: CGPoint(x: 9, y: 18))
                    p.addCurve(
                        to: CGPoint(x: 14.96, y: 15.8),
                        control1: CGPoint(x: 11.43, y: 18),
                        control2: CGPoint(x: 13.47, y: 17.19)
                    )
                    p.addLine(to: CGPoint(x: 12.05, y: 13.56))
                    p.addCurve(
                        to: CGPoint(x: 4.96, y: 10.71),
                        control1: CGPoint(x: 10.24, y: 14.78),
                        control2: CGPoint(x: 6.63, y: 13.28)
                    )
                    p.addLine(to: CGPoint(x: 1.96, y: 13.02))
                    p.addCurve(
                        to: CGPoint(x: 9, y: 18),
                        control1: CGPoint(x: 3.44, y: 15.98),
                        control2: CGPoint(x: 6.48, y: 18)
                    )
                    p.closeSubpath()
                },
                with: .color(Color(hex: 0x34A853))
            )

            // Yellow — left edge.
            context.fill(
                path { p in
                    p.move(to: CGPoint(x: 4.96, y: 10.71))
                    p.addCurve(
                        to: CGPoint(x: 4.96, y: 7.29),
                        control1: CGPoint(x: 4.44, y: 9.59),
                        control2: CGPoint(x: 4.44, y: 8.41)
                    )
                    p.addLine(to: CGPoint(x: 1.96, y: 4.98))
                    p.addCurve(
                        to: CGPoint(x: 1.96, y: 13.02),
                        control1: CGPoint(x: 0.68, y: 7.55),
                        control2: CGPoint(x: 0.68, y: 10.45)
                    )
                    p.addLine(to: CGPoint(x: 4.96, y: 10.71))
                    p.closeSubpath()
                },
                with: .color(Color(hex: 0xFBBC05))
            )

            // Red — top sweep.
            context.fill(
                path { p in
                    p.move(to: CGPoint(x: 9, y: 3.58))
                    p.addCurve(
                        to: CGPoint(x: 14.96, y: 2.18),
                        control1: CGPoint(x: 10.32, y: 3.58),
                        control2: CGPoint(x: 13.21, y: 0.89)
                    )
                    p.addLine(to: CGPoint(x: 12.44, y: 0.89))
                    p.addCurve(
                        to: CGPoint(x: 1.96, y: 4.98),
                        control1: CGPoint(x: 11.43, y: 0),
                        control2: CGPoint(x: 3.44, y: 2.02)
                    )
                    p.addLine(to: CGPoint(x: 4.96, y: 7.29))
                    p.addCurve(
                        to: CGPoint(x: 9, y: 3.58),
                        control1: CGPoint(x: 5.66, y: 5.17),
                        control2: CGPoint(x: 7.19, y: 3.58)
                    )
                    p.closeSubpath()
                },
                with: .color(Color(hex: 0xEA4335))
            )
        }
        .accessibilityHidden(true)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
