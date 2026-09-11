import SwiftUI

extension View {

    /// Renders this view into a surface iOS omits from screenshots, screen
    /// recordings and the app-switcher snapshot, and replaces it outright while
    /// the screen is being recorded or mirrored.
    ///
    /// Two mechanisms, because they cover different holes:
    ///
    /// - `SecureLayerHost` redacts the pixels *at capture time*, which is the
    ///   only thing that works against a screenshot.
    /// - The recording cover is what the wholesaler sees when `isCaptured` goes
    ///   true. Strictly it is belt-and-braces — the secure canvas already omits
    ///   itself from a recording — but it is the only path that still protects
    ///   anything if the canvas lookup has failed open, and unlike a silently
    ///   black rectangle it tells the user *why* the design vanished.
    ///
    /// Neither stops someone photographing the screen with a second phone. That
    /// hole has no technical fix and is why watermarking, not blocking, is the
    /// part of this that actually deters design theft.
    ///
    /// - Parameter enabled: pass `false` to opt a call site out without
    ///   unpicking the modifier — e.g. to measure scrolling cost in a grid.
    func captureProtected(_ enabled: Bool = true) -> some View {
        modifier(CaptureProtectedModifier(enabled: enabled))
    }
}

private struct CaptureProtectedModifier: ViewModifier {

    let enabled: Bool
    private var monitor: CaptureMonitor { .shared }

    func body(content: Content) -> some View {
        if enabled {
            SecureLayerHost {
                content
            }
            .overlay {
                if monitor.isCaptured {
                    recordingCover
                }
            }
        } else {
            content
        }
    }

    private var recordingCover: some View {
        ZStack {
            Rectangle().fill(Palette.dark)
            VStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Hidden while recording")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(8)
        }
        .transition(.opacity)
    }
}
