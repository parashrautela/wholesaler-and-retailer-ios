import Foundation

/// Extracts a Supabase session from the cookies that `@supabase/ssr` sets on a
/// Next.js response.
///
/// ## Why this exists
///
/// `POST /api/auth/verify-otp` verifies the OTP on a **cookie-bound** server
/// client, so its JSON body carries only `{success, userId, isNewUser, userRole}`
/// — the tokens live in `Set-Cookie` instead. The route also does referral
/// bookkeeping that needs the service-role key, so it cannot simply be replaced
/// by an on-device `auth.verifyOTP` call without losing that side effect.
///
/// Reading the tokens back out of the response cookies lets the app keep the
/// server's behaviour intact *and* hold a real `Session` in the Keychain, which
/// every subsequent RLS-scoped query needs.
///
/// ## Cookie format
///
/// `@supabase/ssr` writes `sb-<project-ref>-auth-token`. When the payload
/// exceeds the ~4 KB cookie limit it is split into `…auth-token.0`,
/// `…auth-token.1`, … which must be concatenated **in index order**. The
/// assembled value is either a bare JSON session or, more commonly, the string
/// `base64-` followed by base64url-encoded JSON.
enum SSRSessionBridge {

    struct Tokens: Sendable {
        let accessToken: String
        let refreshToken: String
    }

    /// Pulls the auth-token cookie set (chunked or not) out of an
    /// `HTTPURLResponse` and decodes it into tokens.
    static func tokens(from response: HTTPURLResponse, url: URL) -> Tokens? {
        guard let fields = response.allHeaderFields as? [String: String] else { return nil }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        return tokens(from: cookies)
    }

    static func tokens(from cookies: [HTTPCookie]) -> Tokens? {
        let base = "sb-\(SupabaseManager.projectRef)-auth-token"

        // Unchunked first.
        if let single = cookies.first(where: { $0.name == base }),
           let tokens = decode(single.value) {
            return tokens
        }

        // Chunked: `<base>.0`, `<base>.1`, … concatenated in numeric order.
        let chunks = cookies.compactMap { cookie -> (Int, String)? in
            guard cookie.name.hasPrefix(base + ".") else { return nil }
            guard let index = Int(cookie.name.dropFirst(base.count + 1)) else { return nil }
            return (index, cookie.value)
        }
        guard !chunks.isEmpty else { return nil }
        let joined = chunks.sorted { $0.0 < $1.0 }.map(\.1).joined()
        return decode(joined)
    }

    /// Decodes one assembled cookie value into tokens.
    static func decode(_ rawValue: String) -> Tokens? {
        // Cookie values arrive percent-encoded.
        var value = rawValue.removingPercentEncoding ?? rawValue

        if value.hasPrefix("base64-") {
            value = String(value.dropFirst("base64-".count))
            guard let data = base64URLDecode(value),
                  let decoded = String(data: data, encoding: .utf8)
            else { return nil }
            value = decoded
        }

        guard let data = value.data(using: .utf8) else { return nil }
        return parseJSON(data)
    }

    /// The payload is normally `{"access_token":…,"refresh_token":…,…}`, but
    /// older `@supabase/ssr` releases wrote a positional array whose first two
    /// entries are the tokens. Both are handled.
    private static func parseJSON(_ data: Data) -> Tokens? {
        let json = try? JSONSerialization.jsonObject(with: data)

        if let object = json as? [String: Any],
           let access = object["access_token"] as? String,
           let refresh = object["refresh_token"] as? String {
            return Tokens(accessToken: access, refreshToken: refresh)
        }

        if let array = json as? [Any], array.count >= 2,
           let access = array[0] as? String,
           let refresh = array[1] as? String {
            return Tokens(accessToken: access, refreshToken: refresh)
        }

        return nil
    }

    /// Base64url with tolerant padding — the cookie omits `=` padding and uses
    /// the URL-safe alphabet.
    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }
}
