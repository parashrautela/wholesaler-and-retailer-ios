import SwiftUI

/// Retailer Taste Preferences view (`/dashboard/retailer/your-taste`).
struct YourTasteView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.pink)
            Text("Your Taste")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("Select your preferred aesthetics, categories, and gold purity to discover tailored wholesale recommendations.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Spacing.xl)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Your Taste")
        .navigationBarTitleDisplayMode(.inline)
    }
}
