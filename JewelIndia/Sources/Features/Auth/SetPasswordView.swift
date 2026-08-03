import SwiftUI

/// `/entry_page/signup/set-password` — `components/auth/SetPasswordForm.jsx`.
struct SetPasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var loading = false

    /// `canSubmit = allRulesPassed && password === confirm && password.length > 0`
    private var canSubmit: Bool {
        PasswordRule.allPass(password) && password == confirm && !password.isEmpty
    }

    /// The web shows the mismatch line only once `confirm` is non-empty.
    private var showsMismatch: Bool {
        !confirm.isEmpty && password != confirm
    }

    var body: some View {
        AuthLayout(titleView: AnyView(heading)) {
            Text(Copy.setPasswordSubline)
                .font(.system(size: 14))
                .foregroundStyle(AuthColor.placeholder)
                .lineSpacing(14 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            AuthFieldLabel(text: Copy.setPasswordLabel)
            AuthSecureField(
                text: $password,
                placeholder: Copy.setPasswordPlaceholder,
                height: 48,
                contentType: .newPassword
            )
            .padding(.bottom, 16)

            AuthFieldLabel(text: Copy.setPasswordConfirmLabel)
            AuthSecureField(
                text: $confirm,
                placeholder: Copy.setPasswordPlaceholder,
                height: 48,
                contentType: .newPassword
            )

            if showsMismatch {
                Text(Copy.setPasswordMismatch)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AuthColor.errorText)
                    .padding(.top, 8)
            }

            checklist
                .padding(.top, 20)

            if let error {
                AuthErrorRow(message: error, dotSize: 4, dotTopPadding: 6)
                    .padding(.top, 12)
            }

            Text(Copy.setPasswordInfoNote)
                .font(.system(size: 12))
                .foregroundStyle(AuthColor.placeholder)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 32)
                .padding(.bottom, 20)

            AuthPrimaryButton(
                title: loading ? Copy.setPasswordSubmitBusy : Copy.setPasswordSubmitIdle,
                height: 48,
                cornerRadius: 10,
                fontSize: 14,
                fontWeight: .semibold,
                tracking: 0,
                enabledFill: AuthColor.slate,
                usesOpacityWhenDisabled: true,
                isEnabled: canSubmit && !loading
            ) {
                Task { await submit() }
            }
            .padding(.bottom, 16)

            AuthLegalText(
                fontSize: 13,
                emphasisColor: AuthColor.focusBorder,
                trailingPeriod: true
            )
            .padding(.bottom, 32)
        }
        .animation(Motion.fadeIn, value: showsMismatch)
    }

    private var heading: some View {
        Text(Copy.setPasswordHeading)
            .font(.custom("Georgia", size: 28).weight(.bold))
            .foregroundStyle(AuthColor.ink)
            .padding(.bottom, 10)
    }

    /// The four-rule checklist. A passed rule is a filled `#16A34A` circle with
    /// a white tick; a failed one is a hollow `#D1D5DB` ring.
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PasswordRule.allCases) { rule in
                let passed = rule.passes(password)
                HStack(spacing: 8) {
                    ZStack {
                        if passed {
                            Circle().fill(AuthColor.rulePass)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().stroke(AuthColor.otpBorder, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 14, height: 14)

                    Text(rule.label)
                        .font(.system(size: 12))
                        .foregroundStyle(passed ? AuthColor.rulePass : AuthColor.muted2)
                }
                .animation(.easeInOut(duration: 0.3), value: passed)
            }
        }
    }

    private func submit() async {
        loading = true
        error = nil
        do {
            // role = ?role || sessionStorage.referral_role || "wholesaler"
            try await JewelAPI.setPassword(password, role: flow.signupRole)
            flow.clearOTPState()
            // The web pushes to /onboard or /onboard-retailer; the router
            // reaches the same place from the freshly written role.
            await session.refreshDestination()
        } catch let apiError as JewelAPI.APIError {
            error = apiError.message
        } catch {
            self.error = Copy.setPasswordFallbackError
        }
        loading = false
    }
}
