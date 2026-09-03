import SwiftUI

/// A calm "not built yet" state for employee-view destinations that don't
/// have a native screen yet (Queries, Orders) — deliberately not
/// `PhasePlaceholder`, which reads as leaked internal sprint notes rather
/// than an intentional product state.
struct ComingSoonView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Palette.muted)
            Text("Coming Soon")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text(message)
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
