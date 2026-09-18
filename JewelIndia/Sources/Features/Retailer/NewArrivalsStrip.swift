import SwiftUI

/// The newest designs on the marketplace, across every wholesaler the store
/// can see. The free half of Featured Listings: what is new earns its place
/// by date alone. Hidden entirely when there is nothing to show, so a failed
/// or empty load never leaves a hole in the dashboard.
struct NewArrivalsStrip: View {
    @State private var products: [Product] = []
    @State private var selectedProduct: Product?

    #if DEBUG
    /// Peeks only: designs to show instead of fetching.
    var peekProducts: [Product]?
    #endif

    private static let limit = 10

    var body: some View {
        Group {
            if !products.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("New Arrivals")
                        .font(.cirka(22))
                        .foregroundStyle(Palette.foreground)

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: Spacing.md) {
                            ForEach(products) { product in
                                Button {
                                    selectedProduct = product
                                } label: {
                                    card(product)
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    // Let cards run to the screen edge while the title stays on the gutter.
                    .scrollClipDisabled()
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedProduct) { product in
            MarketplaceProductDetail(product: product)
        }
    }

    private func card(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color(hex: 0xF7F7F7)
                if let url = product.displayImageURL(.card) {
                    CachedImage(url: url)
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Untitled")
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(Palette.foreground)
                .lineLimit(1)
            Text(product.netWeight.map { String(format: "%.2fg", $0) } ?? " ")
                .font(.manrope(11))
                .foregroundStyle(Palette.muted)
        }
        .frame(width: 140, alignment: .leading)
    }

    private func load() async {
        #if DEBUG
        if let peekProducts {
            products = peekProducts
            return
        }
        #endif
        guard let response = try? await JewelAPI.fetchRetailerMarketplace() else { return }
        // ISO 8601 timestamps from one source sort correctly as strings.
        products = Array(
            response.products
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
                .prefix(Self.limit)
        )
    }
}
