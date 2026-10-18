import SwiftUI
import UIKit

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
    @Environment(CreditStore.self) private var credits
    @State private var productToDelete: Product? = nil
    @State private var productToView: Product? = nil
    @State private var isDeleting = false
    @State private var isAddingProduct = false
    @State private var exportedProductFolder: URL?
    @State private var productAwaitingExport: Product?
    @State private var isSelecting = false
    @State private var selection = CatalogueSelection()
    @State private var isSharing = false
    @State private var hasCreatedShare = false
    @State private var showSharedLinks = false
    @State private var actionNotice: String?

    init(initialCategory: String? = nil) {
        self.initialCategory = initialCategory
        _selectedCategory = State(initialValue: initialCategory)
    }

    #if DEBUG
    private var isPreview = false

    init(previewProducts: [Product]) {
        initialCategory = nil
        isPreview = true
        _products = State(initialValue: previewProducts)
        _isLoading = State(initialValue: false)
        _isSelecting = State(initialValue: true)
        var selected = CatalogueSelection()
        for product in previewProducts.prefix(3) { _ = selected.toggle(product) }
        _selection = State(initialValue: selected)
    }
    #endif

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
            } else if let errorMessage, products.isEmpty {
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
                                onDelete: { productToDelete = product },
                                isSelecting: isSelecting,
                                isSelected: selection.ids.contains(product.id)
                            )
                            .onTapGesture { openOrSelect(product) }
                            .accessibilityElement(children: isSelecting ? .ignore : .contain)
                            .accessibilityLabel(product.title ?? "Untitled Product")
                            .accessibilityAddTraits(isSelecting ? .isButton : [])
                            .accessibilityAddTraits(selection.ids.contains(product.id) ? .isSelected : [])
                            .accessibilityAction { openOrSelect(product) }
                        }
                    }
                    .padding(Spacing.screenGutter)
                }
                .refreshTask {
                    await loadProducts()
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .disabled(isDeleting)
        .sensoryFeedback(.selection, trigger: selection.ids)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                Button(Copy.CatalogueShare.shareBarButton(selection.ids.count)) {
                    hasCreatedShare = false
                    isSharing = true
                }
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Palette.dark, in: Capsule())
                .opacity(selection.ids.isEmpty ? 0.45 : 1)
                .disabled(selection.ids.isEmpty)
                .padding(Spacing.screenGutter)
                .background(Palette.background)
            }
        }
        .navigationTitle(isSelecting ? Copy.CatalogueShare.selectCount(selection.ids.count) : "My Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(Copy.CatalogueShare.sharedLinksMenu) { showSharedLinks = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Catalogue actions")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(isSelecting ? Copy.CatalogueShare.selectCancel : Copy.CatalogueShare.selectButton) {
                    isSelecting.toggle()
                    if !isSelecting { selection = CatalogueSelection() }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isAddingProduct = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add product")
            }
        }
        .navigationDestination(isPresented: $showSharedLinks) { SharedLinksView() }
        .task {
            await loadProducts()
        }
        .sheet(isPresented: $isSharing, onDismiss: {
            if hasCreatedShare {
                selection = CatalogueSelection()
                isSelecting = false
            }
        }) {
            CatalogueShareSheet(products: selection.products) { hasCreatedShare = true }
        }
        .sheet(isPresented: $isAddingProduct, onDismiss: {
            Task { await loadProducts() }
        }) {
            AddProductSheet()
                .environment(credits)
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
            Button("Delete from account and save to device") {
                if let product = productToDelete { Task { await exportAndDelete(product) } }
            }
            Button("Delete permanently", role: .destructive) {
                if let product = productToDelete { Task { await deleteProduct(product) } }
            }
            Button("Cancel", role: .cancel) {
                productToDelete = nil
            }
        } message: {
            Text("Choose how to remove '\(productToDelete?.title ?? "this product")'.")
        }
        .sheet(item: Binding(
            get: { exportedProductFolder.map(ExportedFolder.init(url:)) },
            set: { exportedProductFolder = $0?.url }
        )) { folder in
            FolderExportPicker(folderURL: folder.url) { succeeded in
                guard let product = productAwaitingExport else { return }
                productAwaitingExport = nil
                if succeeded {
                    Task {
                        await deleteProduct(product)
                        if errorMessage == nil {
                            actionNotice = "The product folder was saved to Files and the product was removed from your account."
                        }
                    }
                } else {
                    isDeleting = false
                    actionNotice = "Export cancelled. The product is still in your catalogue and its cloud images were kept."
                }
            }
        }
        .alert("Catalogue", isPresented: Binding(
            get: { actionNotice != nil },
            set: { if !$0 { actionNotice = nil } }
        )) {
            Button("OK", role: .cancel) { actionNotice = nil }
        } message: {
            Text(actionNotice ?? "Please try again.")
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

    private func openOrSelect(_ product: Product) {
        if isSelecting {
            actionNotice = selection.toggle(product)
        } else {
            productToView = product
        }
    }

    private func selectCategory(_ slug: String?) {
        selectedCategory = slug
        Task { await loadProducts() }
    }

    private func loadProducts() async {
        #if DEBUG
        if isPreview { return }
        #endif
        guard let userId = session.user?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            let page = try await WholesalerAPI.fetchCatalogue(wholesalerID: userId, category: selectedCategory)
            products = page.products
            totalCount = page.total
            isLoading = false
        } catch {
            isLoading = false
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    private func exportAndDelete(_ product: Product) async {
        isDeleting = true
        productToDelete = nil
        errorMessage = nil
        do {
            let folder = try await makeProductExport(product)
            productAwaitingExport = product
            exportedProductFolder = folder
        } catch {
            errorMessage = "Couldn't save and remove product: \(error.localizedDescription). The product remains in your catalogue unless its deletion already completed."
            actionNotice = errorMessage
            isDeleting = false
        }
    }

    private func deleteProduct(_ product: Product) async {
        isDeleting = true
        productToDelete = nil
        errorMessage = nil
        do {
            try await WholesalerAPI.deleteProduct(id: product.id)
            do {
                try await WholesalerAPI.deleteProductImages(product)
            } catch {
                // The row is already gone; make the partial cloud cleanup clear.
                errorMessage = "Product removed, but some cloud images could not be deleted: \(error.localizedDescription)"
                actionNotice = errorMessage
            }
            products.removeAll { $0.id == product.id }
            productToDelete = nil
        } catch {
            errorMessage = "Failed to delete product: \(error.localizedDescription)"
            actionNotice = errorMessage
        }
        isDeleting = false
    }

    private func makeProductExport(_ product: Product) async throws -> URL {
        let manager = FileManager.default
        let root = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Product Exports", directoryHint: .isDirectory)
        let safeName = (product.title ?? "Product").replacingOccurrences(of: "/", with: "-")
        let folder = root.appending(path: "\(safeName)-\(product.id.prefix(8))", directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        var imageURLs: [String] = []
        imageURLs.append(contentsOf: product.showcaseImageURLs)
        imageURLs.append(contentsOf: product.customImageURLs)
        imageURLs.append(contentsOf: product.generatedImageURLs)
        imageURLs.append(contentsOf: [product.processedImageURL, product.imageURL, product.rawImageURL].compactMap { $0 })
        var uniqueImageURLs: [String] = []
        for raw in imageURLs {
            guard !uniqueImageURLs.contains(raw), URL(string: raw) != nil else { continue }
            uniqueImageURLs.append(raw)
        }
        for (index, raw) in uniqueImageURLs.enumerated() {
            guard let url = URL(string: raw) else { continue }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  !data.isEmpty else { throw ExportError.imageDownloadFailed }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            try data.write(to: folder.appending(path: String(format: "image-%02d.%@", index + 1, ext)), options: .atomic)
        }
        var detailLines: [String] = []
        detailLines.append("Product: \(product.title ?? "Untitled")")
        detailLines.append("ID: \(product.id)")
        detailLines.append("Jewellery type: \(product.jewelleryType ?? "")")
        detailLines.append("Category/material: \(product.category ?? "")")
        detailLines.append("Style: \(product.style ?? "")")
        detailLines.append("Size: \(product.size ?? "")")
        detailLines.append("Purity: \(product.metalPurity ?? "")")
        detailLines.append("Net weight (g): \(product.netWeight.map { String($0) } ?? "")")
        detailLines.append("Gross weight (g): \(product.grossWeight.map { String($0) } ?? "")")
        detailLines.append("Stone weight (g): \(product.stoneWeight.map { String($0) } ?? "")")
        detailLines.append("In stock: \(product.stockAvailable.map { String($0) } ?? "")")
        detailLines.append("Images: The first images follow the selected showcase order; remaining images include attached originals and generated versions.")
        let details = detailLines.joined(separator: "\n")
        try Data(details.utf8).write(to: folder.appending(path: "product-details.txt"), options: .atomic)
        return folder
    }

    private enum ExportError: LocalizedError {
        case imageDownloadFailed
        var errorDescription: String? { "An image could not be downloaded. The product was not removed." }
    }
}

private struct ExportedFolder: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(url: URL) { self.url = url }
}

/// The My Catalogue tab's first page: every category as a tile, then
/// "View All". Tapping one opens `WholesalerCatalogueView` filtered to it.
/// This grid used to sit at the bottom of Home, a second way into the same
/// tab; Home now shows the latest Chamak creations there instead.
struct CatalogueCategoriesView: View {
    @Environment(CreditStore.self) private var credits
    @State private var isAddingProduct = false

    let onSelectCategory: (String?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("See and manage all your catalogue categories from one place.")
                    .font(.gilroy(14, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, Spacing.lg)

                // Two across on a phone, four or more on an iPad, where two
                // columns stretched each tile into a wide, cropped banner.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: Spacing.lg)],
                    spacing: Spacing.lg
                ) {
                    ForEach(CatalogueCategory.all) { category in
                        CategoryCard(category: category) {
                            onSelectCategory(category.slug)
                        }
                    }
                    ViewAllCard { onSelectCategory(nil) }
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
        .navigationTitle("My Catalogue")
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(isPresented: $isAddingProduct) {
            AddProductSheet()
                .environment(credits)
        }
    }
}

private struct FolderExportPicker: UIViewControllerRepresentable {
    let folderURL: URL
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [folderURL], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Bool) -> Void
        private var hasCompleted = false

        init(onComplete: @escaping (Bool) -> Void) { self.onComplete = onComplete }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            complete(!urls.isEmpty)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            complete(false)
        }

        private func complete(_ succeeded: Bool) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onComplete(succeeded)
        }
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
    var isSelecting = false
    var isSelected = false

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
                        if let url = product.displayImageURL(.card) {
                            ProtectedImageView(url: url)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .clipped()

                if !isSelecting {
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
                .stroke(isSelected ? Palette.dark : Color(hex: 0xF0F0F0), lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .topLeading) {
            if isSelecting {
                ZStack {
                    Circle().fill(isSelected ? Palette.dark : .clear)
                    Circle().stroke(.white, lineWidth: 2)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .padding(10)
                .accessibilityHidden(true)
            }
        }
        .opacity(isSelecting && product.isPublished != true ? 0.45 : 1)
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

// Selection stores snapshots because category changes replace the loaded products.
struct CatalogueSelection {
    private(set) var ids: [String] = []
    private var snapshots: [String: Product] = [:]
    var products: [Product] { ids.compactMap { snapshots[$0] } }

    mutating func toggle(_ product: Product) -> String? {
        if let index = ids.firstIndex(of: product.id) {
            ids.remove(at: index)
            snapshots[product.id] = nil
            return nil
        }
        guard product.isPublished == true else { return Copy.CatalogueShare.selectUnpublished }
        guard ids.count < 50 else { return Copy.CatalogueShare.selectLimit }
        ids.append(product.id)
        snapshots[product.id] = product
        return nil
    }
}

struct CatalogueShareSheet: View {
    let products: [Product]
    var onCreated: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var title = ""
    @State private var viewers = 1
    @State private var duration = 1440
    @State private var customMinutes = "30"
    @State private var created: CatalogueShare?
    @State private var createdTitle: String?
    @State private var links = CatalogueShareLinks()
    @State private var creationNotice: String?

    init(products: [Product], onCreated: @escaping () -> Void = {}) {
        self.products = products
        self.onCreated = onCreated
    }

    #if DEBUG
    private var isPreview = false

    init(previewProducts: [Product], ready: Bool) {
        products = previewProducts
        isPreview = true
        _viewers = State(initialValue: 2)
        _duration = State(initialValue: 60)
        let formatter = ISO8601DateFormatter()
        let expiry = formatter.string(from: Date.now.addingTimeInterval(3600))
        let samples = (0..<4).map { index in
            CatalogueShare(id: "preview-\(index)", title: Copy.CatalogueShare.titlePlaceholder,
                itemCount: 2, maxViewers: 2, viewsUsed: index == 3 ? 2 : 1,
                createdAt: nil, expiresAt: index == 2 ? "2000-01-01T00:00:00Z" : expiry,
                revokedAt: index == 1 ? formatter.string(from: .now) : nil,
                linkPath: index == 0 ? "/share/catalogue#" + String(repeating: "a", count: 64) : nil)
        }
        let previewLinks = CatalogueShareLinks()
        previewLinks.shares = samples
        _links = State(initialValue: previewLinks)
        _created = State(initialValue: ready ? samples[0] : nil)
    }
    #endif

    private var minutes: Int { duration == 0 ? (Int(customMinutes) ?? 0) : duration }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(products.prefix(6)) { product in
                                ProtectedImageView(url: product.displayImageURL(.card), maxPixels: 270)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipped()
                                    .accessibilityLabel(product.title ?? "Untitled Product")
                            }
                        }
                    }
                    .frame(height: 56)
                    Text(Copy.CatalogueShare.sheetIntro)
                    TextField(Copy.CatalogueShare.titleField, text: $title, prompt: Text(Copy.CatalogueShare.titlePlaceholder))
                        .onChange(of: title) { _, value in title = String(value.prefix(80)) }
                    Stepper(Copy.CatalogueShare.viewersLabel(viewers), value: $viewers, in: 1...100)
                    Picker(Copy.CatalogueShare.validityLabel, selection: $duration) {
                        Text(Copy.CatalogueShare.validity1h).tag(60)
                        Text(Copy.CatalogueShare.validity24h).tag(1440)
                        Text(Copy.CatalogueShare.validity7d).tag(10080)
                        Text(Copy.CatalogueShare.validityCustom).tag(0)
                    }
                    if duration == 0 {
                        TextField(Copy.CatalogueShare.customField, text: $customMinutes)
                            .keyboardType(.numberPad)
                    }
                    Text(Copy.CatalogueShare.privacyNote).font(.footnote).foregroundStyle(.secondary)
                    Button(links.busy ? Copy.CatalogueShare.createBusy : Copy.CatalogueShare.createButton) {
                        Task { await create() }
                    }
                    .disabled(links.busy || products.isEmpty || products.count > 50 || !(5...10080).contains(minutes))
                    if let creationNotice { Text(creationNotice).font(.footnote) }
                }
                .disabled(links.busy)

                if let created, let url = created.url {
                    Section(Copy.CatalogueShare.readyHeader) {
                        ShareLink(item: Copy.CatalogueShare.shareText(title: createdTitle, url: url)) {
                            Label(Copy.CatalogueShare.readyShare, systemImage: "square.and.arrow.up")
                        }
                        Button(Copy.CatalogueShare.readyCopy) {
                            UIPasteboard.general.url = url
                            links.message = Copy.CatalogueShare.readyCopied
                        }
                        if let expiry = created.expiry { Text(Copy.CatalogueShare.readyExpires(expiry)) }
                        Text(Copy.CatalogueShare.readyWarning).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let message = links.message { Section { Text(message).font(.footnote) } }
                CatalogueRecentLinksSection(links: links) { share in
                    if await links.revoke(share), created?.id == share.id { created = nil }
                }
            }
            .navigationTitle(Copy.CatalogueShare.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(links.busy) }
            }
            .interactiveDismissDisabled(links.busy)
            .task {
                #if DEBUG
                if isPreview { return }
                #endif
                await links.load()
            }
            .onChange(of: scenePhase) { _, phase in
                #if DEBUG
                if isPreview { return }
                #endif
                if phase == .active { Task { await links.load() } }
            }
        }
    }

    private func create() async {
        guard !links.busy else { return }
        links.busy = true
        links.message = nil
        creationNotice = nil
        defer { links.busy = false }
        do {
            let requestTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let share = try await CatalogueShareAPI.createShare(productIDs: products.map(\.id),
                viewers: viewers, minutes: minutes, title: requestTitle)
            created = share
            createdTitle = requestTitle.isEmpty ? nil : requestTitle
            onCreated()
            await links.load()
        } catch { creationNotice = error.localizedDescription }
    }
}

@MainActor @Observable
final class CatalogueShareLinks {
    var shares: [CatalogueShare] = []
    var isLoading = false
    var needsRefresh = false
    var busy = false
    var message: String?
    private var loadVersion = UUID()

    func load() async {
        let version = UUID()
        loadVersion = version
        isLoading = true
        defer { if loadVersion == version { isLoading = false } }
        do {
            let fetched = try await CatalogueShareAPI.fetchShares()
            guard loadVersion == version else { return }
            shares = fetched
            needsRefresh = false
        } catch {
            guard loadVersion == version, !Task.isCancelled else { return }
            needsRefresh = true
            message = error.localizedDescription
        }
    }

    func revoke(_ share: CatalogueShare) async -> Bool {
        guard !busy else { return false }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await CatalogueShareAPI.revokeShare(id: share.id)
            // Update immediately even if the subsequent refresh is offline.
            shares = shares.map { item in
                guard item.id == share.id else { return item }
                return CatalogueShare(id: item.id, title: item.title, itemCount: item.itemCount,
                    maxViewers: item.maxViewers, viewsUsed: item.viewsUsed, createdAt: item.createdAt,
                    expiresAt: item.expiresAt, revokedAt: ISO8601DateFormatter().string(from: .now), linkPath: nil)
            }
            await load()
            message = Copy.CatalogueShare.revokeDone
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

struct CatalogueRecentLinksSection: View {
    let links: CatalogueShareLinks
    let revoke: (CatalogueShare) async -> Void

    var body: some View {
        Section(Copy.CatalogueShare.listHeader) {
            if links.isLoading && links.shares.isEmpty { ProgressView(Copy.CatalogueShare.listLoading) }
            else if links.needsRefresh {
                Text(Copy.CatalogueShare.listOffline).font(.footnote).foregroundStyle(.secondary)
            } else if links.shares.isEmpty { Text(Copy.CatalogueShare.listEmpty).foregroundStyle(.secondary) }
            Button(Copy.CatalogueShare.listRefresh) { Task { await links.load() } }
                .disabled(links.isLoading || links.busy)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                ForEach(links.shares) { share in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(share.title ?? Copy.CatalogueShare.titlePlaceholder).font(.headline)
                        Text(Copy.CatalogueShare.listRow(itemCount: share.itemCount, viewsUsed: share.viewsUsed, maxViewers: share.maxViewers)).font(.subheadline)
                        Text(share.status).font(.footnote)
                        if let expiry = share.expiry {
                            Text(Copy.CatalogueShare.readyExpires(expiry)).font(.footnote).foregroundStyle(.secondary)
                        }
                        if share.canRevoke {
                            Button(Copy.CatalogueShare.revokeButton, role: .destructive) {
                                Task { await revoke(share) }
                            }.disabled(links.busy)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct SharedLinksView: View {
    @State private var links = CatalogueShareLinks()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            CatalogueRecentLinksSection(links: links) { share in _ = await links.revoke(share) }
            if let message = links.message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle(Copy.CatalogueShare.sharedLinksMenu)
        .navigationBarTitleDisplayMode(.inline)
        .task { await links.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await links.load() } }
        }
    }
}
