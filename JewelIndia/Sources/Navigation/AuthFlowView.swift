import SwiftUI

/// The pre-auth stack. Mirrors the web's `/entry_page/*` route group.
enum AuthRoute: Hashable {
    case signIn(identity: String)
    case verifyOTP
    case setPassword
    case forgotPassword
    case updatePassword
}

struct AuthFlowView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow

    /// The destination the router resolved — carries bounce reasons such as a
    /// ban or a deactivated employee account.
    let destination: AppDestination

    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            EntryView(path: $path, initialError: entryError)
                .navigationBarBackButtonHidden()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AuthRoute.self) { route in
                    view(for: route)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .task(id: destinationKey) { applyDestination() }
    }

    @ViewBuilder
    private func view(for route: AuthRoute) -> some View {
        switch route {
        case .signIn(let identity):
            SignInView(path: $path, identity: identity)
        case .verifyOTP:
            VerifyOTPView(path: $path)
        case .setPassword:
            SetPasswordView(path: $path)
        case .forgotPassword:
            ForgotPasswordView(path: $path)
        case .updatePassword:
            UpdatePasswordView(path: $path)
        }
    }

    private var entryError: String? {
        switch destination {
        case .entry(let error): error
        case .employeeLogin(let error): error
        default: nil
        }
    }

    /// A stable key so the task re-runs only when the destination changes.
    private var destinationKey: String { String(describing: destination) }

    private func applyDestination() {
        switch destination {
        case .signIn(let identity):
            path = [.signIn(identity: identity)]
        case .updatePassword:
            // Nothing else ever pushed this route. `UpdatePasswordView` and
            // `AuthRoute.updatePassword` both existed, but no code path put it
            // on the stack, so following a recovery link could not reach it.
            path = [.updatePassword]
        default:
            // A bounce (banned / deactivated) always returns to the front door.
            if !path.isEmpty { path.removeAll() }
        }
    }
}
