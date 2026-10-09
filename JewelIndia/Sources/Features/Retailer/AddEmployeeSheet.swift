import SwiftUI

/// Add someone to the store's staff: a username-and-password login the
/// store hands over, or an invitation to a Google address they already use.
struct AddEmployeeSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Method: String, CaseIterable, Identifiable {
        case login, google
        var id: String { rawValue }
        var title: String {
            switch self {
            case .login: "Create a login"
            case .google: "Invite by Google"
            }
        }
    }

    @State private var method: Method = .login
    @State private var fullName = ""
    @State private var designation = ""
    @State private var phone = ""
    @State private var username = ""
    @State private var usernameEdited = false
    @State private var suggesting = false
    @State private var googleEmail = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var created: StaffCredentials?
    @State private var invited: StaffMember?
    @State private var suggestTask: Task<Void, Never>?

    private var canSubmit: Bool {
        guard !isSubmitting, fullName.trimmed.count >= 2 else { return false }
        switch method {
        case .login: return username.trimmed.count >= 3
        case .google: return Credentials.isEmail(googleEmail.trimmed)
        }
    }

    var body: some View {
        if let created {
            StaffCredentialsView(member: created.member, password: created.password) { dismiss() }
        } else if let invited {
            invitedView(invited)
        } else {
            form
        }
    }

    // MARK: - Form

    private var form: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Picker("How they sign in", selection: $method) {
                        ForEach(Method.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(method == .login
                         ? "You'll get a username and a one-time password to pass on."
                         : "They sign in with Google using this address. No password to share.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.manrope(13))
                            .foregroundStyle(Color.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    field("FULL NAME*", text: $fullName, placeholder: "Priya Sharma", contentType: .name)
                        .onChange(of: fullName) { _, value in suggestIfUntouched(value) }

                    if method == .login {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("USERNAME*")
                                .font(.manrope(11, weight: .bold))
                                .foregroundStyle(Palette.muted)
                            HStack(spacing: 4) {
                                TextField("priya.pinejewels", text: $username)
                                    .font(.manrope(14))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.asciiCapable)
                                    .onChange(of: username) { _, value in
                                        let cleaned = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." }
                                        if cleaned != value { username = cleaned }
                                        usernameEdited = true
                                    }
                                if suggesting {
                                    ProgressView().controlSize(.small)
                                }
                                Text("@\(StaffAccountsAPI.usernameDomain)")
                                    .font(.manrope(13))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(12)
                            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
                            Text("It's only a username — nothing is sent to it.")
                                .font(.manrope(11))
                                .foregroundStyle(Palette.muted)
                        }
                    } else {
                        field("GOOGLE EMAIL*", text: $googleEmail, placeholder: "priya@gmail.com",
                              contentType: .emailAddress, keyboard: .emailAddress)
                    }

                    field("ROLE", text: $designation, placeholder: "Sales Associate")
                    field("PHONE", text: $phone, placeholder: "9876543210", contentType: .telephoneNumber, keyboard: .phonePad)

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(method == .login ? "Create login" : "Send invitation")
                                    .font(.manrope(15, weight: .bold))
                            }
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                        .opacity(canSubmit ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .padding(.top, Spacing.sm)
                }
                .padding(Spacing.screenGutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Add staff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String,
                       contentType: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Palette.muted)
            TextField(placeholder, text: text)
                .font(.manrope(14))
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(12)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func invitedView(_ member: StaffMember) -> some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Palette.dark)
                Text("\(member.fullName) is invited")
                    .font(.cirka(24))
                    .foregroundStyle(Palette.foreground)
                    .multilineTextAlignment(.center)
                Text("Ask them to open the Jewels India app, choose “I work at a store” and continue with Google as \(member.signInLabel). They'll be in straight away.")
                    .font(.manrope(14))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.manrope(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(Spacing.screenGutter)
            .background(Palette.background.ignoresSafeArea())
        }
    }

    // MARK: - Behaviour

    /// A username from the name, until the owner types their own.
    private func suggestIfUntouched(_ name: String) {
        guard method == .login, !usernameEdited || username.isEmpty else { return }
        suggestTask?.cancel()
        guard name.trimmed.count >= 2 else { return }
        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            suggesting = true
            defer { suggesting = false }
            if let suggested = try? await StaffAccountsAPI.suggestUsername(fullName: name.trimmed), !Task.isCancelled {
                username = suggested
                usernameEdited = false
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        let role = designation.trimmed.nilIfEmpty
        let phoneNumber = phone.trimmed.nilIfEmpty
        do {
            switch method {
            case .login:
                let result = try await StaffAccountsAPI.createLogin(
                    fullName: fullName.trimmed, username: username.trimmed, designation: role, phone: phoneNumber
                )
                created = StaffCredentials(member: result.member, password: result.password)
            case .google:
                invited = try await StaffAccountsAPI.inviteGoogle(
                    fullName: fullName.trimmed, email: googleEmail.trimmed, designation: role, phone: phoneNumber
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
