#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only check for whether the secure canvas is actually redacting.
///
/// The question "does this protect a screenshot?" cannot be answered by taking
/// a simulator screenshot — `simctl` reads the framebuffer by a route the
/// redaction does not necessarily cover — and answering it on hardware costs a
/// TestFlight cycle each time. `drawHierarchy(in:afterScreenUpdates:)` is the
/// snapshot path that *does* honour secure-entry redaction, which makes it a
/// faithful local stand-in: content that survives a `drawHierarchy` snapshot
/// would survive a screenshot too.
///
/// Writes the snapshot into the app container so it can be pulled out and
/// looked at. Compiled out of Release entirely.
enum CaptureSelfTest {

    @MainActor
    static func snapshotWindow(named name: String) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else {
            print("[CaptureSelfTest] no key window")
            return
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            // `afterScreenUpdates: true` is the part that matters — it forces a
            // fresh render pass, which is where the redaction is applied.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else { return }
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[CaptureSelfTest] wrote \(url.path)")
    }
}

extension View {
    /// Snapshots the window shortly after this view appears.
    func captureSelfTest(_ name: String) -> some View {
        task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            CaptureSelfTest.snapshotWindow(named: name)
        }
    }
}
#endif
