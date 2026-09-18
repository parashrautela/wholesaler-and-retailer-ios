import SwiftUI

/// The staff door (`/employee-login`): the username and password the store
/// gave them, or Google for staff their store added by address.
///
/// There is no "forgot password" here. A staff username is not a mailbox, so
/// a reset mail could reach nobody — the store resets it from its staff list.
struct EmployeeSignInView: View {
    @Environment(SessionStore.self) private var session
    @Binding var path: [AuthRoute]

    /// A bounce reason forwarded by the router (deactivated).
    var initialError: String?

    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var loading = false
    @State private var googleLoading = false

    private var canSubmit: Bool {
        !loading && !googleLoading && !username.trimmed.isEmpty && !password.isEmpty
    }

    var body: some View {
        AuthLayout(titleView: AnyView(heading)) {
            Text(Copy.staffSubheading)
                .font(.system(size: 15))
                .foregroundStyle(AuthColor.subheading)
                .lineSpacing(15 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 28)

            AuthFieldLabel(text: Copy.staffUsernameLabel)
            AuthTextField(
                text: $username,
                placeholder: Copy.staffUsernamePlaceholder,
                keyboard: .emailAddress,
                contentType: .username
            )
            .padding(.bottom, 16)
            .onChange(of: username) { _, _ in if error != nil { error = nil } }

            AuthFieldLabel(text: Copy.employeePasswordLabel)
            AuthSecureField(
                text: $password,
                placeholder: Copy.employeePasswordPlaceholder,
                contentType: .password
            )
            .padding(.bottom, 8)
            .onChange(of: password) { _, _ in if error != nil { error = nil } }

            Text(Copy.staffForgotHint)
                .font(.system(size: 12))
                .foregroundStyle(AuthColor.placeholder)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            if let error {
                AuthErrorRow(message: error)
                    .padding(.bottom, 12)
            }

            AuthOrDivider()

            GoogleButton(isBusy: googleLoading, title: Copy.staffGoogle) { Task { await signInWithGoogle() } }

            Spacer(minLength: 40)

            AuthPrimaryButton(
                title: loading ? Copy.employeeSubmitBusy : Copy.employeeSubmitIdle,
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.employeeHeadingLine1)
            Text(Copy.employeeHeadingLine2)
        }
        .font(.custom("Georgia", size: 34).weight(.bold))
        .foregroundStyle(AuthColor.ink)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func submit() async {
        loading = true
        error = nil
        let identity = StaffAccountsAPI.address(forUsername: username)
        if let message = await session.signIn(identity: identity, password: password) {
            error = message.localizedCaseInsensitiveContains("invalid login")
                ? Copy.staffWrongCredentials
                : message
        }
        loading = false
    }

    private func signInWithGoogle() async {
        googleLoading = true
        error = nil
        defer { googleLoading = false }
        switch await GoogleSignIn.signIn() {
        case .cancelled:
            return
        case .failed(let message):
            error = message
        case .signedIn:
            if let message = await session.claimStaffInvite() {
                error = message
            }
        }
    }
}
