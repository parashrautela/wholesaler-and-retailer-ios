import AuthenticationServices
import Supabase
import UIKit

extension AccountAPI {
    /// Accounts made with Sign in with Apple have their Apple tokens revoked
    /// before deletion (App Review 5.1.1(v)). Apple hands out a fresh
    /// authorization code for this; the `apple-revoke` function exchanges and
    /// revokes it. Best effort: a cancelled prompt or a failed revoke never
    /// stops someone deleting their account.
    static func revokeAppleSignInIfNeeded() async {
        let usesApple = SupabaseManager.client.auth.currentUser?.identities?
            .contains { $0.provider == "apple" } ?? false
        guard usesApple, let code = await AppleAuthorizationCode.request() else { return }
        do {
            _ = try await SupabaseManager.client.functions.invoke(
                "apple-revoke",
                options: FunctionInvokeOptions(body: ["code": code])
            )
        } catch {
            // Logged server-side; deletion goes ahead regardless.
        }
    }
}

/// Runs the system Sign in with Apple sheet just to obtain an authorization code.
@MainActor
private final class AppleAuthorizationCode: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String?, Never>?
    private static var inFlight: AppleAuthorizationCode?

    static func request() async -> String? {
        let runner = AppleAuthorizationCode()
        inFlight = runner
        defer { inFlight = nil }
        return await withCheckedContinuation { continuation in
            runner.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = runner
            controller.presentationContextProvider = runner
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(code)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(nil)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func finish(_ code: String?) {
        continuation?.resume(returning: code)
        continuation = nil
    }
}
