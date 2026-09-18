import SwiftUI

/// The retailer door's first step: the invitation code, checked as it is
/// typed. Nothing else happens until the code is good.
struct InviteCodeView: View {
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    /// Signed-in use (a role-less account adding a code): called with the
    /// valid code instead of moving on to signup.
    var onValid: ((String) -> Void)?

    @State private var code = ""
    @State private var check: InviteCodeCheck = .idle

    var body: some View {
        AuthLayout(title: Copy.inviteHeading, subtitle: Copy.inviteSubheading) {
            InviteCodeField(code: $code, check: $check)
                .padding(.bottom, 20)

            Spacer(minLength: 40)

            AuthPrimaryButton(
                title: Copy.inviteContinue,
                isEnabled: check.isValid
            ) {
                proceed()
            }
            .padding(.bottom, 16)

            Button(Copy.inviteNoCode) { path.removeAll() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AuthColor.muted2)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

            AuthLegalText()
        }
        .onAppear {
            if code.isEmpty, let saved = flow.referralCode { code = saved }
        }
    }

    private func proceed() {
        guard case .valid(let validCode, let wholesaler) = check else { return }
        flow.referralCode = validCode
        flow.referralRole = .retailer
        flow.invitedBy = wholesaler
        if let onValid {
            onValid(validCode)
        } else {
            flow.chosenRole = .retailer
            path.append(.entry(.signup(.retailer)))
        }
    }
}

enum InviteCodeCheck: Equatable {
    case idle
    case checking
    case valid(code: String, wholesaler: String?)
    case invalid(String)
    case failed

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

/// The code box with its live verdict, shared by the retailer door, the last
/// onboarding step and the waiting screen.
struct InviteCodeField: View {
    @Binding var code: String
    @Binding var check: InviteCodeCheck
    var label: String = Copy.inviteFieldLabel

    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthFieldLabel(text: label)
            AuthTextField(
                text: $code,
                placeholder: Copy.inviteFieldPlaceholder,
                keyboard: .asciiCapable,
                contentType: .oneTimeCode,
                autocapitalization: .characters
            )
            .onChange(of: code) { _, value in schedule(value) }
            .onAppear { if !code.isEmpty { schedule(code) } }

            Group {
                switch check {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(Copy.inviteChecking)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(AuthColor.muted2)
                case .valid(_, let wholesaler):
                    Label(wholesaler.map { Copy.invitedBy($0) } ?? Copy.inviteValid, systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x15803D))
                case .invalid(let message):
                    AuthErrorRow(message: message)
                case .failed:
                    AuthErrorRow(message: Copy.networkError)
                }
            }
            .padding(.top, 10)
            .animation(Motion.fadeIn, value: check)
        }
    }

    /// A short pause after typing, then one check for the whole value.
    private func schedule(_ value: String) {
        checkTask?.cancel()
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else {
            check = .idle
            return
        }
        check = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let result = try await InviteAPI.validate(trimmed)
                guard !Task.isCancelled else { return }
                switch result {
                case .valid(let code, let wholesaler): check = .valid(code: code, wholesaler: wholesaler)
                case .invalid(_, let message): check = .invalid(message)
                }
            } catch {
                guard !Task.isCancelled else { return }
                check = .failed
            }
        }
    }
}
