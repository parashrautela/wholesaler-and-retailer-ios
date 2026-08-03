import Foundation

/// Build-time configuration, read from `Info.plist` keys that are populated
/// from `Config.xcconfig`. The values mirror the web app's `.env` exactly:
///
///   NEXT_PUBLIC_SUPABASE_URL       → SUPABASE_URL
///   NEXT_PUBLIC_SUPABASE_ANON_KEY  → SUPABASE_ANON_KEY
///   NEXT_PUBLIC_API_URL            → AI_PIPELINE_URL
///   NEXT_PUBLIC_SITE_URL           → SITE_URL
enum AppConfig {

    static let supabaseURL: URL = url(for: "SUPABASE_URL")
    static let supabaseAnonKey: String = string(for: "SUPABASE_ANON_KEY")

    /// The AI pipeline service the wholesaler upload flow posts to.
    static let aiPipelineURL: URL = url(for: "AI_PIPELINE_URL")

    /// The deployed Next host. Used for OAuth / email redirect callbacks and
    /// for the handful of endpoints that require server-side privileges.
    static let siteURL: URL = url(for: "SITE_URL")

    /// Deep-link scheme registered for Supabase auth callbacks.
    static let authCallbackScheme = "jewelindia"

    // MARK: - Plist access

    private static func string(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            fatalError("AppConfig: missing Info.plist key '\(key)'. Check Config.xcconfig.")
        }
        return value
    }

    private static func url(for key: String) -> URL {
        let raw = string(for: key)
        guard let url = URL(string: raw) else {
            fatalError("AppConfig: value for '\(key)' is not a valid URL: \(raw)")
        }
        return url
    }
}
