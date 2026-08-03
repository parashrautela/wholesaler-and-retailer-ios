import AuthenticationServices
import SwiftUI
import Supabase

/// `/entry_page/signup` — `components/auth/EntryForm.jsx`.
///
/// This is the app's real front door: it captures an identity, asks the server
/// whether that identity already exists, and forks into password sign-in,
/// Google, or OTP signup.
struct EntryView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    /// Seeded from `?error=` on the web; here it carries a bounce reason
    /// (banned, deactivated) forwarded by the router.
    var initialError: String?

    @State private var identity = ""
    @State private var error: String?
    @State private var loading = false
    @State private var googleLoading = false

    /// `disabled = loading || !identity.trim()`
    private var canSubmit: Bool {
        !loading && !googleLoading && !identity.trimmed.isEmpty
    }

    var body: some View {
        AuthLayout(title: Copy.entryHeading, subtitle: Copy.entrySubheading) {
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
        .onAppear { if error == nil { error = initialError } }
    }

    // MARK: - Submit

    private func submit() async {
        let raw = identity.trimmed
        // 1. Silent no-op on an empty field, exactly as the web does.
        guard !raw.isEmpty else { return }

        loading = true
        error = nil

        // 2/3. Email passes through; anything else must be a valid Indian mobile.
        let normalized: String
        if Credentials.isEmail(raw) {
            normalized = raw
        } else {
            let check = Credentials.validateIndianMobile(raw)
            guard check.valid, let e164 = check.normalized else {
                error = Copy.invalidMobile
                loading = false
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
                loading = false
                path.append(.signIn(identity: normalized))
                return
            }

            // New identity → send the OTP.
            let otp = try await JewelAPI.sendOTP(identity: normalized)
            flow.identity = normalized
            flow.otpSentAt = Date()
            if let remaining = otp.remainingResends { flow.remainingResends = remaining }
            loading = false
            path.append(.verifyOTP)

        } catch let apiError as JewelAPI.APIError {
            error = apiError.message
            loading = false
        } catch {
            self.error = Copy.networkError
            loading = false
        }
    }

    // MARK: - Google

    /// `lib/actions/oauth.js` → `signInWithOAuth(provider:"google", queryParams:
    /// {access_type:"offline", prompt:"consent"})`. On iOS the redirect target
    /// is the app's own URL scheme rather than the web callback route.
    private func startGoogle() async {
        googleLoading = true
        defer { googleLoading = false }
        do {
            _ = try await SupabaseManager.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "\(AppConfig.authCallbackScheme)://auth/callback"),
                queryParams: [
                    (name: "access_type", value: "offline"),
                    (name: "prompt", value: "consent"),
                ]
            )
            await session.refreshDestination()
        } catch {
            // A user-cancelled sheet should not shout at them.
            let nsError = error as NSError
            let cancelled = nsError.domain == ASWebAuthenticationSessionErrorDomain
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            if !cancelled {
                self.error = error.localizedDescription
            }
        }
    }
}

/// The inline Google "G" the web draws as four SVG paths, with the same fills.
struct GoogleButton: View {
    var isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleGlyph().frame(width: 18, height: 18)
                Text(isBusy ? Copy.entryGoogleBusy : Copy.entryGoogleIdle)
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
