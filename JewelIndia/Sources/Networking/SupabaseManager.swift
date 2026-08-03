import Foundation
import Supabase

/// The single Supabase client for the app — the native equivalent of
/// `lib/supabase/client.js` (`createBrowserClient(URL, ANON_KEY)`).
///
/// The service-role client (`lib/supabase/admin.js`) has deliberately **no**
/// counterpart here: that key must never ship in a mobile binary. The handful
/// of flows that genuinely need it go through the deployed Next endpoints —
/// see `JewelAPI`.
enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )

    /// The Supabase project ref, parsed from the URL host.
    /// Used to locate the `sb-<ref>-auth-token` cookies the Next server sets.
    static let projectRef: String = {
        AppConfig.supabaseURL.host()?.split(separator: ".").first.map(String.init) ?? ""
    }()
}
