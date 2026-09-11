import SwiftUI

/// Upload history view for wholesalers (`/dashboard/wholesaler/upload-history`).
/// Shows all products uploaded today along with their AI processing status.
struct UploadHistoryView: View {
    @Environment(SessionStore.self) private var session

    @State private var products: [Product] = []
    @State private var usage: UploadUsage = .unknown
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

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
            } else if let errorMessage {
                errorStateView(errorMessage)
            } else if products.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(products) { product in
                        HStack(spacing: Spacing.md) {
                            if let url = product.displayImageURL(.card) {
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

    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Button("Retry") {
                Task { await loadData() }
            }
            .buttonStyle(.plain)
            .font(.manrope(14, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.cream, in: Capsule())
            Spacer()
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
        errorMessage = nil
        usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: userId)
        do {
            let page = try await WholesalerAPI.fetchCatalogue(wholesalerID: userId)
            products = page.products
        } catch {
            errorMessage = "Couldn't load your uploads. Check your connection and try again."
        }
        isLoading = false
    }
}
