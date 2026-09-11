import SwiftUI
import UIKit
import Observation

/// Tracks the two capture events iOS *does* tell an app about.
///
/// The two differ in a way that decides what can be done with each:
///
/// - **Recording / mirroring / AirPlay** is reported *while it is happening*
///   (`UIScreen.isCaptured`), so content hidden in response is genuinely absent
///   from the rest of the recording.
/// - **Screenshots** are reported *after the fact*. By the time
///   `userDidTakeScreenshotNotification` arrives the image is already in the
///   user's library, so `screenshotCount` is an audit signal — never a defence.
///   Redacting the pixels of a screenshot is `SecureLayerHost`'s job, and it has
///   to happen at capture time to work at all.
///
/// A singleton rather than an injected dependency because it mirrors process-
/// wide state: there is one screen, and its capture status is the same fact no
/// matter who asks. Passing it through the environment bought nothing and cost
/// an isolation dance — plus a screen every caller could forget to wire up.
@MainActor
@Observable
final class CaptureMonitor {

    static let shared = CaptureMonitor()

    /// True while the screen is being recorded, mirrored or AirPlayed.
    private(set) var isCaptured: Bool = false

    /// Screenshots taken during this app session. Increments *after* each one.
    private(set) var screenshotCount: Int = 0

    /// The most recent screenshot, for showing a one-shot notice.
    private(set) var lastScreenshotAt: Date?

    /// No `deinit` unregisters these, and that is deliberate rather than an
    /// oversight: the single instance lives for the process, so there is no
    /// moment at which removing them would run. Adding a `deinit` here would
    /// mean reaching main-actor state from a nonisolated context to do work
    /// that never happens.
    private var observers: [NSObjectProtocol] = []

    private init() {
        isCaptured = Self.activeScreen?.isCaptured ?? false

        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isCaptured = Self.activeScreen?.isCaptured ?? false
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: UIApplication.userDidTakeScreenshotNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screenshotCount += 1
                    self?.lastScreenshotAt = Date()
                }
            }
        )
    }

    /// `UIScreen.main` is deprecated and, on iPad, wrong the moment the app is
    /// on an external display or in a second window — read the screen from the
    /// scene that is actually foregrounded instead.
    private static var activeScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
}
