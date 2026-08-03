import SwiftUI

/// `/forgot-password` — `components/auth/ForgotPasswordForm.jsx`.
///
/// On success the whole form is replaced by a confirmation card.
struct ForgotPasswordView: View {
    @Environment(SessionStore.self) private var session
    @Binding var path: [AuthRoute]

    @State private var email = ""
    @State private var error: String?
    @State private var loading = false
    @State private var sent = false

    var body: some View {
        AuthLayout(
            title: sent ? nil : Copy.forgotHeading,
            subtitle: sent ? nil : Copy.forgotSubheading
        ) {
            if sent {
                successCard
            } else {
                form
            }
        }
        .animation(Motion.fadeIn, value: sent)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthFieldLabel(text: Copy.forgotLabel)
            AuthTextField(
                text: $email,
                placeholder: Copy.forgotPlaceholder,
                height: 48,
                fill: .white,
                idleBorder: AuthColor.border2,
                focusBorder: AuthColor.focusBorder,
                fontSize: 15,
                keyboard: .emailAddress,
                contentType: .emailAddress
            )
            .padding(.horizontal, -2)
            .onChange(of: email) { _, _ in if error != nil { error = nil } }

            if let error {
                AuthErrorRow(message: error, dotSize: 4, dotTopPadding: 6)
                    .padding(.top, 12)
            }

            AuthPrimaryButton(
                title: loading ? Copy.forgotSubmitBusy : Copy.forgotSubmitIdle,
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

            Button(Copy.forgotBackToSignIn) { path.removeLast() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AuthColor.focusBorder)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SuccessCheckCircle()
                .padding(.bottom, 20)

            Text(Copy.forgotSuccessTitle)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: 0x111827))
                .padding(.bottom, 8)

            Text(Copy.forgotSuccessBody)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6B7280))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            Button {
                path.removeLast()
            } label: {
                Text(Copy.forgotReturn)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AuthColor.slate)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AuthColor.border2, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() async {
        loading = true
        error = nil
        if let message = await session.requestPasswordReset(email: email) {
            error = message
        } else {
            sent = true
        }
        loading = false
    }
}

/// `/update-password` — `components/auth/UpdatePasswordForm.jsx`.
/// Reached from the emailed reset link.
struct UpdatePasswordView: View {
    @Environment(SessionStore.self) private var session
    @Binding var path: [AuthRoute]

    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var loading = false
    @State private var done = false

    var body: some View {
        AuthLayout(
            title: done ? nil : Copy.updateHeading,
            subtitle: done ? nil : Copy.updateSubheading
        ) {
            if done {
                successCard
            } else {
                form
            }
        }
        .animation(Motion.fadeIn, value: done)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthFieldLabel(text: Copy.updateNewLabel)
            AuthSecureField(
                text: $password,
                placeholder: Copy.updateNewPlaceholder,
                contentType: .newPassword
            )
            .padding(.bottom, 16)

            AuthFieldLabel(text: Copy.updateConfirmLabel)
            AuthSecureField(
                text: $confirm,
                placeholder: Copy.updateConfirmPlaceholder,
                contentType: .newPassword
            )

            if let error {
                AuthErrorRow(message: error, dotSize: 4, dotTopPadding: 6)
                    .padding(.top, 12)
            }

            AuthPrimaryButton(
                title: loading ? Copy.updateSubmitBusy : Copy.updateSubmitIdle,
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
        }
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SuccessCheckCircle()
                .padding(.bottom, 20)

            Text(Copy.updateSuccessTitle)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: 0x111827))
                .padding(.bottom, 8)

            Text(Copy.updateSuccessBody)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6B7280))
                .padding(.bottom, 24)

            // The web's label says "Dashboard" but the link goes to sign-in.
            // Copy is kept verbatim; the destination matches the link.
            AuthPrimaryButton(
                title: Copy.updateSuccessCTA,
                height: 48,
                cornerRadius: 12,
                fontSize: 14,
                fontWeight: .bold,
                tracking: 0,
                enabledFill: AuthColor.slate,
                isEnabled: true
            ) {
                path.removeAll()
            }
        }
    }

    private func submit() async {
        // Client-side mismatch check first — the server only enforces length.
        guard password == confirm else {
            error = Copy.updateMismatch
            return
        }
        loading = true
        error = nil
        if let message = await session.updatePassword(password) {
            error = message
        } else {
            done = true
        }
        loading = false
    }
}

/// The green tick both success states share: a `bg-green-100` circle with a
/// `text-green-600` check drawn from `M5 13l4 4L19 7`.
struct SuccessCheckCircle: View {
    var body: some View {
        Circle()
            .fill(Color(hex: 0xDCFCE7))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x16A34A))
            }
    }
}
