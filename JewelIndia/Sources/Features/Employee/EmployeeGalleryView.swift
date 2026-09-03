import SwiftUI

/// `/dashboard/employee/wholesaler-gallery` — the retailer's curated
/// selection from the wholesaler marketplace. Mirrors
/// `WholesalerGalleryClient.jsx`'s card grid (full-bleed square image, serif
/// caption) with a lightweight category filter row built from whatever
/// categories are actually present, matching the web's "no sort control"
/// rule (`_spec/06-retailer-screens.md` §0).
struct EmployeeGalleryView: View {
    @Environment(SessionStore.self) private var session

    @State private var model = EmployeeGalleryModel()
    @State private var selectedCategory: String?

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !model.categories.isEmpty {
                categoryTabs
            }

            if model.isLoading && model.products.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.dark)
                Spacer()
            } else if let errorMessage = model.errorMessage, model.products.isEmpty {
                errorState(errorMessage)
            } else if model.products.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.xl) {
                        ForEach(filteredProducts) { product in
                            GalleryProductCard(product: product)
                        }
                    }
                    .padding(Spacing.base)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.white)
        .navigationTitle("Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(session: session)
        }
        .refreshable {
            await model.load(session: session)
        }
    }

    private var filteredProducts: [Product] {
        guard let selectedCategory else { return model.products }
        return model.products.filter { ($0.jewelleryType ?? $0.category) == selectedCategory }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                categoryPill(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(model.categories, id: \.self) { category in
                    categoryPill(title: category.capitalized, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func categoryPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Palette.dark)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Palette.dark : Color.white, in: Capsule())
                .overlay {
                    Capsule().stroke(Palette.border, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No Selections Yet")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("Products your store curates from the marketplace will show up here.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
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
                Task { await model.load(session: session) }
            }
            .buttonStyle(.plain)
            .font(.manrope(14, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.cream, in: Capsule())
            Spacer()
        }
    }
}

private struct GalleryProductCard: View {
    let product: Product

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Color(hex: 0xF4F4F4)
                if let url = product.displayImageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(hex: 0xF4F4F4)
                    }
                } else {
                    Text("No image")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .clipped()

            Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Untitled")
                .font(.cirka(14))
                .foregroundStyle(Color(hex: 0x374151))
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class EmployeeGalleryModel {
    var products: [Product] = []
    var isLoading = true
    var errorMessage: String?

    var categories: [String] {
        let values = products.compactMap { $0.jewelleryType ?? $0.category }
        return Array(Set(values)).sorted()
    }

    func load(session: SessionStore) async {
        guard let user = session.user else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            products = try await EmployeeAPI.fetchSelectedProducts(userID: user.id)
        } catch {
            errorMessage = "Couldn't load the catalogue. Check your connection and try again."
        }
    }
}
