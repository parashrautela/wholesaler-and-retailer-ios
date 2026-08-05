import SwiftUI

/// Retailer Catalogue view (`/dashboard/retailer/catalogue`).
/// Displays private store designs and allows design uploads.
struct RetailerCatalogueView: View {
    @Environment(SessionStore.self) private var session
    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.muted)
                TextField("Search store designs...", text: $searchQuery)
                    .font(.manrope(14))
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
            .padding(.horizontal, Spacing.screenGutter)
            .padding(.top, Spacing.sm)

            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.muted)
                Text("Store Catalogue")
                    .font(.cirka(24))
                    .foregroundStyle(Palette.foreground)
                Text("Your store's custom designs and Wholesaler bookmarked items will be displayed here.")
                    .font(.manrope(14))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(Spacing.xl)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Catalogue")
        .navigationBarTitleDisplayMode(.inline)
    }
}
