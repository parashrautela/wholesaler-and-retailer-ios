import SwiftUI

/// The root scene switch — the native equivalent of the Next proxy deciding,
/// on every navigation, which part of the app a user is allowed into.
struct RootView: View {
    @State private var session = SessionStore()
    @State private var flow = SignupFlow()

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                LaunchView()

            case .unauthenticated(let destination):
                AuthFlowView(destination: destination)
                    .transition(.opacity)

            case .authenticated(let destination):
                scene(for: destination)
                    .transition(.opacity)
            }
        }
        .environment(session)
        .environment(flow)
        .animation(Motion.fadeIn, value: session.phase)
        .task { session.start() }
        .onOpenURL { url in
            // Google OAuth and the emailed reset link both return through the
            // app's custom scheme; the SDK exchanges the code for a session and
            // the auth-state stream re-routes.
            Task { try? await SupabaseManager.client.auth.session(from: url) }
        }
    }

    @ViewBuilder
    private func scene(for destination: AppDestination) -> some View {
        switch destination {
        case .selectRole:
            SelectRoleView()

        case .wholesalerOnboarding:
            OnboardCoordinator()
        case .wholesalerSubmitted:
            OnboardSubmittedView()
        case .wholesalerDashboard:
            WholesalerShell()

        case .retailerOnboarding:
            RetailerOnboardCoordinator()
        case .retailerSubmitted:
            RetailerOnboardSubmittedView()
        case .retailerDashboard:
            RetailerShell()

        case .employeeDashboard:
            EmployeeShell()

        // Auth-flow destinations never reach here — `SessionStore` classifies
        // them as unauthenticated — but the switch must stay total.
        case .entry, .signIn, .employeeLogin, .updatePassword:
            AuthFlowView(destination: destination)
        }
    }
}

/// Launch state while the persisted session is resolved. The web has no
/// equivalent (the server resolves the route before first paint), so this is
/// deliberately quiet — brand mark only, no spinner flash.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            Text("Jewel India")
                .font(.cirka(32))
                .foregroundStyle(Palette.foreground)
        }
    }
}

/// A gated screen that is not yet ported but that a real account can legitimately
/// land on, so it carries a sign-out escape hatch.
struct PhaseGatePlaceholder: View {
    @Environment(SessionStore.self) private var session
    let title: String
    let note: String

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.base) {
                Text(title)
                    .font(.cirka(30))
                    .foregroundStyle(Palette.foreground)
                    .multilineTextAlignment(.center)
                Text(note)
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                Button(Copy.logoutConfirm) {
                    Task { await session.signOut() }
                }
                .buttonStyle(.plain)
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.dark)
                .padding(.top, Spacing.lg)
            }
            .padding(Spacing.xxl)
        }
    }
}

#Preview { RootView() }
