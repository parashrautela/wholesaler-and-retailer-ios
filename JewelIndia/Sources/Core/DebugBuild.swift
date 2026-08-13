#if DEBUG
/// A hand-bumped marker so a screenshot can settle "is this today's build?"
/// without walking through `git log` + a clean rebuild each time. Bump the
/// string whenever a fix needs to be told apart from the previous one while
/// actively re-testing it on a real device — e.g. the native Google Sign-In
/// nonce fix in `EntryView.startGoogleNatively`.
///
/// DEBUG-only: this file and everything referencing it compile out of every
/// Release build, so it never reaches TestFlight or the App Store.
enum DebugBuild {
    static let tag = "google-nonce-fix-2"
}
#endif
