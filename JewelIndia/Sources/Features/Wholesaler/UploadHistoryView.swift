import SwiftUI

/// Upload history view for wholesalers (`/dashboard/wholesaler/upload-history`).
/// Shows all products uploaded today along with their AI processing status.
struct UploadHistoryView: View {
    @Environment(SessionStore.self) private var session

    @State private var products: [Product] = []
    @State private var usage: UploadUsage = .unknown
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Usage Progress Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Daily Upload Progress")
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Palette.foreground)

                    Spacer()

                    Text(usage.display + " Used")
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }

                if let limit = usage.limit, limit > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Palette.cream)
                                .frame(height: 6)

                            Capsule()
                                .fill(Palette.dark)
                                .frame(width: geo.size.width * CGFloat(min(1.0, Double(usage.used) / Double(limit))), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(Spacing.screenGutter)
            .background(Color.white)
            .overlay(alignment: .bottom) { Divider() }

            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.dark)
                Spacer()
            } else if products.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(products) { product in
                        HStack(spacing: Spacing.md) {
                            if let url = product.displayImageURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(Palette.cream)
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Rectangle()
                                    .fill(Palette.cream)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay { Image(systemName: "photo").foregroundStyle(Palette.muted) }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.title ?? "Untitled Upload")
                                    .font(.manrope(14, weight: .bold))
                                    .foregroundStyle(Palette.foreground)

                                Text(product.category?.capitalized ?? "Jewellery")
                                    .font(.manrope(12))
                                    .foregroundStyle(Palette.muted)
                            }

                            Spacer()

                            Text("Uploaded Today")
                                .font(.manrope(10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Uploads Today")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No Uploads Today")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("Products you upload today will show up here.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
            Spacer()
        }
    }

    private func loadData() async {
        guard let userId = session.user?.id else { return }
        isLoading = true
        usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: userId)
        if let page = try? await WholesalerAPI.fetchCatalogue(wholesalerID: userId) {
            products = page.products
        }
        isLoading = false
    }
}
