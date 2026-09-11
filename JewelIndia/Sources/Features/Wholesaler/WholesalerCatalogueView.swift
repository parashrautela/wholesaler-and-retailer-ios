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
    @State private var productToView: Product? = nil
    @State private var isDeleting = false
    @State private var isAddingProduct = false

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
                    LazyVGrid(columns: CatalogueProductCard.gridColumns, spacing: Spacing.md) {
                        ForEach(filteredProducts) { product in
                            CatalogueProductCard(
                                product: product,
                                onEdit: { productToEdit = product },
                                onDelete: { productToDelete = product }
                            )
                            // "Whole card opens the detail modal" (§8.2) — the
                            // card previously had no tap target at all beyond
                            // the ellipsis menu, so there was no way to see a
                            // product's enhanced renders or trigger AI
                            // re-upload from the catalogue.
                            .onTapGesture { productToView = product }
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isAddingProduct = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add product")
            }
        }
        .task {
            await loadProducts()
        }
        .sheet(isPresented: $isAddingProduct, onDismiss: {
            Task { await loadProducts() }
        }) {
            AddProductSheet()
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
        .sheet(item: $productToView) { product in
            ProductDetailSheet(product: product) { updated in
                if let index = products.firstIndex(where: { $0.id == updated.id }) {
                    products[index] = updated
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
            if searchQuery.trimmed.isEmpty {
                Button {
                    isAddingProduct = true
                } label: {
                    Label("Add Product", systemImage: "plus")
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Palette.dark, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, Spacing.xs)
            }
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

    /// Two columns on a phone, four to six on an iPad. A fixed two-column grid
    /// made each iPad card ~590pt wide over a 160pt-tall image, so every piece
    /// was cropped to a thin strip.
    static let gridColumns = [
        GridItem(.adaptive(minimum: 165, maximum: 250), spacing: Spacing.md)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Square image: it scales with the card, so the whole piece stays
            // in frame at any column width.
            ZStack(alignment: .topTrailing) {
                Palette.cream
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let url = product.displayImageURL {
                            ProtectedImageView(url: url)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .clipped()

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

            // Details: title, one metadata line, availability. Same facts as
            // before in three rows instead of four, so the photo dominates.
            VStack(alignment: .leading, spacing: 5) {
                Text(product.title ?? "Untitled Product")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !metadataLine.isEmpty {
                        Text(metadataLine)
                            .font(.manrope(12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 4)

                    if let purity = product.metalPurity, !purity.isEmpty {
                        Text(purity.uppercased())
                            .font(.manrope(10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x9A6B2F))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: 0xFFFBF4), in: .rect(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
                            }
                    }
                }

                availability
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xF0F0F0), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    /// "Gold · Net 12.00 g" — whichever parts the product has.
    private var metadataLine: String {
        var parts: [String] = []
        if let category = product.category, !category.isEmpty {
            parts.append(category.capitalized)
        }
        if let netWeight = product.netWeight {
            parts.append(String(format: "Net %.2f g", netWeight))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var availability: some View {
        if product.stockAvailable == true {
            Label("In Stock", systemImage: "checkmark.circle.fill")
                .font(.manrope(11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x16A34A))
        } else if let days = product.makeToOrderDays {
            Label("Made to order · \(days) days", systemImage: "clock")
                .font(.manrope(11, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB45309))
        }
    }
}
