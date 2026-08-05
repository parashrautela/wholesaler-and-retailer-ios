import Foundation
import Observation
import Supabase

/// The app's auth state — the native counterpart of
/// `components/auth/AuthProvider.jsx`, which holds the user and re-renders on
/// `supabase.auth.onAuthStateChange`.
///
/// It also owns the launch/login routing decision, so the whole app can key off
/// a single `phase` value the way the web keys off its proxy's redirect.
@MainActor
@Observable
final class SessionStore {

    enum Phase: Equatable {
        /// Resolving the persisted session on launch.
        case loading
        /// Signed out (or bounced), showing the auth flow.
        case unauthenticated(AppDestination)
        /// Signed in and routed.
        case authenticated(AppDestination)
    }

    private(set) var phase: Phase = .loading
    private(set) var user: User?

    private var watchTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Starts mirroring Supabase auth state. `authStateChanges` always emits an
    /// `.initialSession` first, which is what resolves the launch route.
    func start() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            for await (event, session) in SupabaseManager.client.auth.authStateChanges {
                guard let self else { return }
                await self.handle(event: event, session: session)
            }
        }
    }

    private func handle(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let user = session?.user else {
                user = nil
                phase = .unauthenticated(.entry(error: nil))
                return
            }
            self.user = user
            // Mid-signup the auth stack owns navigation: `verify-otp` installs
            // the session before the set-password screen has been pushed, and
            // re-routing here would destroy the stack that is about to show it.
            if SignupFlow.isCompletingSignup { return }
            // Token refreshes must not re-route a user mid-session.
            if case .authenticated = phase, event == .tokenRefreshed { return }
            let destination = await AuthRouter.destination(for: user)
            phase = isAuthFlow(destination)
                ? .unauthenticated(destination)
                : .authenticated(destination)

        case .signedOut:
            SignupFlow.isCompletingSignup = false
            user = nil
            phase = .unauthenticated(.entry(error: nil))

        default:
            break
        }
    }

    /// Destinations that belong to the pre-auth stack even though a session may
    /// briefly have existed (banned / deactivated bounces sign the user out).
    private func isAuthFlow(_ destination: AppDestination) -> Bool {
        switch destination {
        case .entry, .signIn, .employeeLogin: true
        default: false
        }
    }

    // MARK: - Actions

    /// Port of the `signIn` Server Action (C1). Returns an error message on
    /// failure; on success the auth-state stream drives the navigation, exactly
    /// as the web's `redirect()` does.
    func signIn(identity: String, password: String) async -> String? {
        do {
            if Credentials.isEmail(identity) {
                _ = try await SupabaseManager.client.auth.signIn(email: identity, password: password)
            } else {
                _ = try await SupabaseManager.client.auth.signIn(phone: identity, password: password)
            }
        } catch {
            // GoTrue messages are surfaced verbatim on the web, e.g.
            // "Invalid login credentials".
            return error.localizedDescription
        }

        guard let user = SupabaseManager.client.auth.currentSession?.user else {
            return Copy.genericFailure
        }

        // The employee branch can reject after a successful password check.
        if await AuthRouter.resolveRole(for: user) == .employee {
            let row: EmployeeGate? = try? await SupabaseManager.client
                .from("employees")
                .select("status")
                .eq("auth_user_id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            if let row, row.status != "active" {
                try? await SupabaseManager.client.auth.signOut()
                return Copy.employeeDeactivated
            }
        }

        await handle(event: .signedIn, session: SupabaseManager.client.auth.currentSession)
        return nil
    }

    /// Port of `signOut()` (C2) — clears the session and returns to the entry
    /// screen. Unlike the web, the per-user view mode is cleared too, so it
    /// cannot leak into the next account on a shared device.
    func signOut() async {
        if let id = user?.id { ViewModeStore.clear(for: id) }
        try? await SupabaseManager.client.auth.signOut()
        user = nil
        phase = .unauthenticated(.entry(error: nil))
    }

    /// Re-resolves the destination — used after onboarding submits, after the
    /// view-mode toggle, and after `setUserRole`.
    func refreshDestination() async {
        guard let user = SupabaseManager.client.auth.currentSession?.user else {
            phase = .unauthenticated(.entry(error: nil))
            return
        }
        self.user = user
        let destination = await AuthRouter.destination(for: user)
        phase = isAuthFlow(destination)
            ? .unauthenticated(destination)
            : .authenticated(destination)
    }

    /// Port of `setUserRole` (C8).
    func setUserRole(_ role: UserRole) async -> String? {
        guard let user = SupabaseManager.client.auth.currentSession?.user else {
            return Copy.selectRoleNotAuthed
        }
        do {
            _ = try await SupabaseManager.client.auth.update(
                user: UserAttributes(data: ["role": .string(role.rawValue)])
            )
            struct ProfileRow: Encodable {
                let id: String
                let email: String?
                let role: String
            }
            _ = try? await SupabaseManager.client
                .from("profiles")
                .upsert(
                    ProfileRow(
                        id: user.id.uuidString,
                        email: user.email ?? user.phone,
                        role: role.rawValue
                    ),
                    onConflict: "id"
                )
                .execute()
            await refreshDestination()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Port of `updatePassword` (C7).
    func updatePassword(_ password: String) async -> String? {
        guard password.count >= 6 else { return Copy.updateTooShort }
        do {
            _ = try await SupabaseManager.client.auth.update(
                user: UserAttributes(password: password)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Port of `requestPasswordReset` (C6), minus the admin existence probe.
    ///
    /// The web calls `admin.listUsers({perPage:1000})` first purely to say
    /// "No account found with this email address." That needs the service-role
    /// key, which cannot ship on device — and the check is already wrong past
    /// 1000 users. Supabase's own reset call is used directly instead; it does
    /// not disclose whether the address exists, which is also the safer
    /// behaviour. Flagged for the user.
    func requestPasswordReset(email: String) async -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Copy.forgotEmailRequired }
        do {
            try await SupabaseManager.client.auth.resetPasswordForEmail(
                trimmed.lowercased(),
                redirectTo: URL(string: "\(AppConfig.authCallbackScheme)://auth/callback?next=/update-password")
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
