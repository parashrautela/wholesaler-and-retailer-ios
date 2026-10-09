import AuthenticationServices
import CryptoKit
import GoogleSignIn
import Supabase
import UIKit

/// Google sign-in, shared by every door that offers it.
///
/// `lib/actions/oauth.js` → `signInWithOAuth(provider:"google", queryParams:
/// {access_type:"offline", prompt:"consent"})`. On iOS the preferred path is
/// the native Google SDK, which hands the app an ID token directly — no
/// browser sheet to get stranded on the website. The browser flow remains as
/// the fallback when no iOS client id is configured.
enum GoogleSignIn {

    enum Outcome: Equatable {
        /// A Supabase session now exists.
        case signedIn
        /// The person backed out of the Google sheet.
        case cancelled
        case failed(String)
    }

    @MainActor
    static func signIn() async -> Outcome {
        if AppConfig.supportsNativeGoogleSignIn {
            return await signInNatively()
        }
        return await signInInBrowser()
    }

    // MARK: - Native

    /// Native Google Sign-In → `signInWithIdToken`.
    @MainActor
    private static func signInNatively() async -> Outcome {
        guard let clientID = AppConfig.googleIOSClientID else { return .failed(Copy.genericFailure) }
        guard let presenter = presentingViewController() else { return .failed(Copy.genericFailure) }

        // No `serverClientID` — this app has no backend of its own to hand a
        // server-audienced token to; Supabase manages its own session.
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        // Below GoogleSignIn-iOS 9.0.0, `signIn` always minted its own nonce
        // internally and never exposed it, and Supabase's `signInWithIdToken`
        // requires the nonce it is given to match a hash embedded in the
        // token — so that combination could never succeed ("Passed nonce and
        // nonce in id_token should either both exist or not"). 9.0.0 added a
        // `nonce:` parameter; `project.yml` requires that version.
        //
        // Same shape as Sign in with Apple: Google gets the hash and puts it
        // in the token verbatim; Supabase gets the raw value and hashes it
        // itself. Swapping the two looks identical to the nonce being absent.
        let rawNonce = randomNonce()
        let hashedNonce = sha256Hex(rawNonce)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                return .failed(Copy.genericFailure)
            }
            _ = try await SupabaseManager.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString,
                    nonce: rawNonce
                )
            )
            return .signedIn
        } catch {
            let nsError = error as NSError
            let cancelled = nsError.domain == kGIDSignInErrorDomain
                && nsError.code == GIDSignInError.canceled.rawValue
            return cancelled ? .cancelled : .failed(error.localizedDescription)
        }
    }

    /// A fresh random nonce for one sign-in attempt — the same recipe as
    /// Apple's own "Sign in with Apple" sample (charset kept URL-safe since
    /// this travels as a query parameter). `UUID`'s generator is also
    /// CSPRNG-backed on iOS, so it is a legitimate fallback.
    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return (0..<3).map { _ in UUID().uuidString }.joined()
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The topmost view controller, which Google needs to present from.
    @MainActor
    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Browser fallback

    /// **Requires `jewelindia://auth/callback` in the Supabase project's
    /// Redirect URLs allow-list** (Authentication → URL Configuration).
    /// Otherwise Supabase substitutes the Site URL on the way back, the sheet
    /// loads the website and never returns a session — which reports itself
    /// as a cancel. A cancel therefore stays silent in the UI and is logged
    /// instead; a non-cancel failure with no session is still shown.
    @MainActor
    private static func signInInBrowser() async -> Outcome {
        do {
            _ = try await SupabaseManager.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "\(AppConfig.authCallbackScheme)://auth/callback"),
                queryParams: [
                    (name: "access_type", value: "offline"),
                    (name: "prompt", value: "consent"),
                ]
            )
            guard SupabaseManager.client.auth.currentSession != nil else {
                return .failed(Copy.googleRedirectNotConfigured)
            }
            return .signedIn
        } catch {
            let nsError = error as NSError
            let isWebAuthError = nsError.domain == ASWebAuthenticationSessionErrorDomain
            let cancelled = isWebAuthError
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue

            guard SupabaseManager.client.auth.currentSession == nil, isWebAuthError else {
                return cancelled ? .cancelled : .failed(error.localizedDescription)
            }
            guard !cancelled else {
                #if DEBUG
                print("""
                    [auth] Google sheet dismissed with no session. If it was \
                    showing \(AppConfig.siteURL.host() ?? "the website") rather \
                    than returning to the app, add \
                    "\(AppConfig.authCallbackScheme)://auth/callback" to the \
                    Supabase project's Redirect URLs allow-list.
                    """)
                #endif
                return .cancelled
            }
            return .failed(Copy.googleRedirectNotConfigured)
        }
    }
}
