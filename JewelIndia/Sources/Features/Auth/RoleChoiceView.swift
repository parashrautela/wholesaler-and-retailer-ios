import SwiftUI

/// The front door: three ways in, chosen before anything else.
///
/// - **Wholesaler** applies, and Jewel India verifies them.
/// - **Retailer** needs a wholesaler's invitation code first.
/// - **Staff** sign in with what their store gave them.
///
/// The same screen serves a signed-in account that has no role yet (the web's
/// `/select-role`), where choosing a door records it straight away.
struct RoleChoiceView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    /// Signed in with no door chosen yet: choosing one records it, rather
    /// than starting a signup.
    var signedIn = false
    /// A bounce reason forwarded by the router (banned, deactivated).
    var initialError: String?

    @State private var error: String?
    @State private var busy: UserRole?
    @State private var showInviteCode = false

    var body: some View {
        AuthLayout(
            title: signedIn ? Copy.doorsSignedInHeading : Copy.doorsHeading,
            subtitle: Copy.doorsSubheading,
            topTrailing: signedIn ? nil : AnyView(topSignInButton)
        ) {
            if !signedIn, flow.referralRole == .retailer, flow.referralCode != nil {
                InvitationBanner(wholesaler: flow.invitedBy)
                    .padding(.bottom, 16)
            }

            if !signedIn {
                HStack(spacing: 4) {
                    Text(Copy.doorsHaveAccount)
                        .foregroundStyle(Color(hex: 0x4B5563))
                    Button {
                        path.append(.entry(.signIn))
                    } label: {
                        Text(Copy.doorsSignIn)
                            .foregroundStyle(AuthColor.ink)
                            .fontWeight(.semibold)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 14))
                .padding(.bottom, 20)
            }

            VStack(spacing: 14) {
                door(.wholesaler, symbol: "shippingbox", title: Copy.doorWholesalerTitle, body: Copy.doorWholesalerBody, isFeatured: false)
                door(.retailer, symbol: "storefront", title: Copy.doorRetailerTitle, body: Copy.doorRetailerBody, isFeatured: true)
                door(.employee, symbol: "person.text.rectangle", title: Copy.doorStaffTitle, body: Copy.doorStaffBody, isFeatured: false)
            }

            if let error {
                AuthErrorRow(message: error)
                    .padding(.top, 16)
            }

            Spacer(minLength: 28)

            if signedIn {
                Button(Copy.logoutConfirm) { Task { await session.signOut() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AuthColor.focusBorder)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }

            AuthLegalText()
        }
        .animation(Motion.fadeIn, value: error)
        .onAppear { if error == nil { error = initialError } }
        .sheet(isPresented: $showInviteCode) {
            NavigationStack {
                InviteCodeView(path: .constant([])) { code in
                    showInviteCode = false
                    Task { await choose(.retailer, code: code) }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private var topSignInButton: some View {
        Button {
            path.append(.entry(.signIn))
        } label: {
            HStack(spacing: 5) {
                Text(Copy.doorsSignIn)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AuthColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AuthColor.fill2, in: .capsule)
            .overlay(Capsule().stroke(AuthColor.border2, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityLabel(Copy.doorsSignIn)
    }

    private func door(_ role: UserRole, symbol: String, title: String, body: String, isFeatured: Bool = false) -> some View {
        Button { tapped(role) } label: {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isFeatured ? Color(hex: 0x854D0E) : AuthColor.ink)
                    .frame(width: 48, height: 48)
                    .background(
                        isFeatured ? Color(hex: 0xFEF3C7).opacity(0.55) : AuthColor.fill2,
                        in: .rect(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AuthColor.ink)
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x4B5563))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)

                if busy == role {
                    ProgressView().tint(AuthColor.ink)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6B7280))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(isFeatured ? Color(hex: 0xFFFDF7) : Color.white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFeatured ? Color(hex: 0xD4AF37).opacity(0.45) : AuthColor.hairline,
                        lineWidth: isFeatured ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .disabled(busy != nil)
        .accessibilityLabel("\(title). \(body)")
    }

    private func tapped(_ role: UserRole) {
        error = nil
        if signedIn {
            switch role {
            case .wholesaler: Task { await choose(.wholesaler, code: nil) }
            case .retailer: showInviteCode = true
            case .employee: Task { await claimStaff() }
            }
            return
        }
        switch role {
        case .wholesaler:
            flow.chosenRole = .wholesaler
            path.append(.entry(.signup(.wholesaler)))
        case .retailer:
            path.append(.inviteCode)
        case .employee:
            path.append(.employeeSignIn)
        }
    }

    // MARK: - Signed in

    private func choose(_ role: UserRole, code: String?) async {
        busy = role
        defer { busy = nil }
        if let code {
            flow.referralCode = code
            flow.referralRole = .retailer
        }
        if let message = await session.setUserRole(role) {
            error = message
        }
    }

    /// Staff who signed in with Google before their store added them, or who
    /// chose a door by mistake: the invitation is claimed here.
    private func claimStaff() async {
        busy = .employee
        defer { busy = nil }
        if let message = await session.claimStaffInvite() {
            error = message
        }
    }
}

/// "Invited by Pine Jewels" — shown wherever a captured invitation applies.
struct InvitationBanner: View {
    var wholesaler: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(wholesaler.map { Copy.invitedBy($0) } ?? Copy.invitationDetected)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                Text(Copy.invitationNext)
                    .font(.manrope(12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        }
    }
}

/// The route lookups failed (no network, an outage). The session is kept and
/// the route is resolved again on request — never guessed.
struct UnreachableView: View {
    @Environment(SessionStore.self) private var session
    @State private var retrying = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.base) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.muted)
                Text(Copy.unreachableTitle)
                    .font(.cirka(26))
                    .foregroundStyle(Palette.foreground)
                    .multilineTextAlignment(.center)
                Text(Copy.unreachableBody)
                    .font(.manrope(14))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        retrying = true
                        await session.refreshDestination()
                        retrying = false
                    }
                } label: {
                    Text(retrying ? Copy.unreachableRetrying : Copy.unreachableRetry)
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Palette.dark, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(retrying)
                .padding(.top, Spacing.sm)
                Button(Copy.logoutConfirm) { Task { await session.signOut() } }
                    .buttonStyle(.plain)
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(Spacing.xxl)
        }
    }
}
