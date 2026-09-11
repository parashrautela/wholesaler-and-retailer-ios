import SwiftUI

/// What the app-switcher thumbnail shows instead of whatever screen the
/// wholesaler happened to be on.
///
/// This is the one capture an app can get *ahead* of. iOS takes the snapshot
/// while the scene is moving out of `.active`, and the scene-phase change is
/// delivered first — so a cover put up on that signal is already in the
/// hierarchy when the snapshot is taken. That is also why it must never be
/// animated in: a fade means the snapshot catches a half-transparent cover and
/// the catalogue behind it.
struct AppSwitcherCover: View {
    var body: some View {
        ZStack {
            Palette.background
            VStack(spacing: Spacing.sm) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(hex: 0xBB8651))
                Text("Jewel India")
                    .font(.cirka(22, weight: .bold))
                    .foregroundStyle(Palette.dark)
            }
        }
        .ignoresSafeArea()
    }
}
