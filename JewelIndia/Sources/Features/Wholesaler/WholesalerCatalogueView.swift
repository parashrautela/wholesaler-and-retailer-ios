import SwiftUI

/// The Wholesaler Catalogue view (`/dashboard/wholesaler/catalogue`).
/// Displays products for the signed-in wholesaler, category filter chips,
/// search bar, stock status tags, and product context actions.
struct WholesalerCatalogueView: View {
    @Environment(SessionStore.self) private var session
    
    let initialCategory: String?
    
    @State private var products: [Product] = []
    @State private var totalCount: Int = 0
    @State private var selectedCategory: String?
    @State private var searchQuery: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    // Product Actions
    @State private var productToEdit: Product? = nil
    @State private var productToDelete: Product? = nil
    @State private var isDeleting = false

    init(initialCategory: String? = nil) {
        self.initialCategory = initialCategory
        _selectedCategory = State(initialValue: initialCategory)
    }

    var filteredProducts: [Product] {
        if searchQuery.trimmed.isEmpty {
            return products
        }
        let q = searchQuery.lowercased()
        return products.filter { p in
            (p.title?.lowercased().contains(q) ?? false) ||
            (p.category?.lowercased().contains(q) ?? false) ||
            (p.jewelleryType?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Search & Filter Bar
            filterHeader

            if isLoading && products.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.dark)
                Spacer()
            } else if let errorMessage {
                Spacer()
                VStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.red)
                    Text(errorMessage)
                        .font(.manrope(14, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await loadProducts() }
                    }
                    .buttonStyle(.plain)
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Palette.cream, in: Capsule())
                }
                .padding(Spacing.xl)
                Spacer()
            } else if filteredProducts.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)], spacing: Spacing.md) {
                        ForEach(filteredProducts) { product in
                            CatalogueProductCard(
                                product: product,
                                onEdit: { productToEdit = product },
                                onDelete: { productToDelete = product }
                            )
                        }
                    }
                    .padding(Spacing.screenGutter)
                }
                .refreshable {
                    await loadProducts()
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("My Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProducts()
        }
        .sheet(item: $productToEdit) { product in
            NavigationStack {
                EditProductView(product: product) { updated in
                    if let index = products.firstIndex(where: { $0.id == updated.id }) {
                        products[index] = updated
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Product",
            isPresented: Binding(
                get: { productToDelete != nil },
                set: { if !$0 { productToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Product", role: .destructive) {
                if let product = productToDelete {
                    Task { await deleteProduct(product) }
                }
            }
            Button("Cancel", role: .cancel) {
                productToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete '\(productToDelete?.title ?? "this product")'? This action cannot be undone.")
        }
    }

    private var filterHeader: some View {
        VStack(spacing: Spacing.sm) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.muted)
                TextField("Search products by title or category...", text: $searchQuery)
                    .font(.manrope(14))
                    .autocorrectionDisabled()
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
            .padding(.horizontal, Spacing.screenGutter)
            .padding(.top, Spacing.sm)

            // Category Horizontal Scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    CategoryChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        action: { selectCategory(nil) }
                    )

                    ForEach(CatalogueCategory.all) { cat in
                        CategoryChip(
                            title: cat.name,
                            isSelected: selectedCategory == cat.slug,
                            action: { selectCategory(cat.slug) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.screenGutter)
                .padding(.vertical, 6)
            }
        }
        .background(Palette.background)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No Products Found")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text(selectedCategory != nil ? "There are no products in this category yet." : "You haven't added any products to your catalogue.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Spacing.xl)
    }

    private func selectCategory(_ slug: String?) {
        selectedCategory = slug
        Task { await loadProducts() }
    }

    private func loadProducts() async {
        guard let userId = session.user?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            let page = try await WholesalerAPI.fetchCatalogue(wholesalerID: userId, category: selectedCategory)
            products = page.products
            totalCount = page.total
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func deleteProduct(_ product: Product) async {
        isDeleting = true
        do {
            try await WholesalerAPI.deleteProduct(id: product.id)
            products.removeAll { $0.id == product.id }
            productToDelete = nil
        } catch {
            errorMessage = "Failed to delete product: \(error.localizedDescription)"
        }
        isDeleting = false
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.white : Palette.foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Palette.dark : Color.white, in: Capsule())
                .overlay {
                    if !isSelected {
                        Capsule().stroke(Palette.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalogue Product Card

struct CatalogueProductCard: View {
    let product: Product
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Box
            ZStack(alignment: .topTrailing) {
                if let url = product.displayImageURL {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Palette.cream)
                            .overlay { ProgressView() }
                    }
                    .frame(height: 160)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(Palette.cream)
                        .frame(height: 160)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(Palette.muted)
                        }
                }

                // Options Menu
                Menu {
                    Button(action: onEdit) {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Product", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.dark)
                        .padding(8)
                        .background(Color.white.opacity(0.9), in: Circle())
                        .shadow(radius: 2)
                }
                .padding(8)
            }

            // Info Details
            VStack(alignment: .leading, spacing: 6) {
                Text(product.title ?? "Untitled Product")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(1)

                HStack {
                    if let category = product.category {
                        Text(category.capitalized)
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }

                    Spacer()

                    if let purity = product.metalPurity {
                        Text(purity.uppercased())
                            .font(.manrope(10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.orange)
                    }
                }

                if let netWeight = product.netWeight {
                    Text("Net Wt: \(String(format: "%.2fg", netWeight))")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Palette.dark)
                }

                // Stock Badge
                HStack {
                    if product.stockAvailable == true {
                        Label("In Stock", systemImage: "checkmark.circle.fill")
                            .font(.manrope(10, weight: .semibold))
                            .foregroundStyle(Color.green)
                    } else if let days = product.makeToOrderDays {
                        Text("\(days) days lead")
                            .font(.manrope(10, weight: .medium))
                            .foregroundStyle(Color.orange)
                    }
                }
                .padding(.top, 2)
            }
            .padding(12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
