import SwiftUI

/// `/entry_page/signin` — `components/auth/SignInForm.jsx`.
///
/// The identity is fixed by this point (it arrives from the entry screen), so
/// it renders as a read-only chip with a `Change` action rather than an input.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    let identity: String

    @State private var password = ""
    @State private var rememberMe = false
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        AuthLayout(title: Copy.signInHeading, subtitle: Copy.signInSubheading) {
            identityRow
                .padding(.bottom, 20)

            AuthFieldLabel(text: Copy.signInPasswordLabel)
            AuthSecureField(
                text: $password,
                placeholder: Copy.signInPasswordPlaceholder,
                contentType: .password
            )
            .onChange(of: password) { _, _ in if error != nil { error = nil } }

            HStack {
                rememberToggle
                Spacer()
                Button(Copy.signInForgot) { path.append(.forgotPassword) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AuthColor.focusBorder)
            }
            .padding(.top, 14)

            if let error {
                AuthErrorRow(message: error, dotSize: 4, dotTopPadding: 6)
                    .padding(.top, 12)
            }

            AuthPrimaryButton(
                title: loading ? Copy.signInSubmitBusy : Copy.signInSubmitIdle,
                height: 48,
                cornerRadius: 12,
                fontSize: 14,
                fontWeight: .bold,
                tracking: 0,
                enabledFill: AuthColor.slate,
                usesOpacityWhenDisabled: true,
                isEnabled: !loading
            ) {
                Task { await submit() }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            AuthLegalText(
                fontSize: 13,
                emphasisColor: AuthColor.focusBorder,
                trailingPeriod: true
            )
            .padding(.bottom, 32)
        }
        .animation(Motion.fadeIn, value: error)
    }

    // MARK: - Identity chip

    private var identityRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AuthFieldLabel(text: Copy.signInIdentityLabel)
                Spacer()
                Button(Copy.signInChange) {
                    flow.clearIdentity()
                    path.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AuthColor.focusBorder)
                .padding(.bottom, 8)
            }

            HStack(spacing: 0) {
                // The web prefixes a bare digit string with +91; identities
                // arriving from the entry screen are already in E.164, so this
                // only shows for a legacy stored value.
                if identity.allSatisfy(\.isNumber), !identity.isEmpty {
                    Text("+91")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AuthColor.text2)
                }
                Text(identity)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AuthColor.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(AuthColor.fill2, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AuthColor.border2, lineWidth: 1.5)
            }
        }
    }

    /// The web's checkbox is inert — `rememberMe` is never read or sent.
    /// Reproduced as-is so the surface matches; flagged in the Phase 1 notes.
    private var rememberToggle: some View {
        Button {
            rememberMe.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(AuthColor.border2, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(rememberMe ? AuthColor.slate : .clear)
                    )
                    .frame(width: 14, height: 14)
                    .overlay {
                        if rememberMe {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(Copy.signInRemember)
                    .font(.system(size: 14))
                    .foregroundStyle(AuthColor.muted2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit

    private func submit() async {
        guard !password.isEmpty else { return }  // the web relies on `required`
        loading = true
        error = nil
        let message = await session.signIn(identity: identity, password: password)
        error = message
        loading = false
    }
}
