import SwiftUI

/// The Catalogue tab (`/dashboard/employee/wholesaler-gallery`): the pieces
/// the store shortlisted from wholesalers. A header that folds away as you
/// scroll, nine category tiles, four filters, nine pieces a page.
///
/// Tap a piece to open it (`EmployeeReviewView`); hold it for half a second
/// to add it to, or take it out of, the selection.
struct EmployeeCatalogueView: View {
    @Environment(EmployeeStore.self) private var store

    @State private var products: [Product] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var category = "all"
    @State private var filters = EmployeeFilterState()
    @State private var page = 1
    @State private var header: SmartHeaderState = .top
    @State private var lastOffset: CGFloat = 0
    @State private var width: CGFloat = 390
    @State private var notice: String?

    private static let perPage = 9

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: 0).id("top")
                    Section {
                        content(proxy: proxy)
                    } header: {
                        headerContent
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
                let next = SmartHeaderState.next(offset: offset, previous: lastOffset)
                if next != header {
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.7)) { header = next }
                }
                lastOffset = offset
            }
            .refreshable { await load() }
        }
        .background(Color.white)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .task { if !loaded { await load() } }
        .onChange(of: category) { page = 1 }
        .onChange(of: filters) { page = 1 }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var medium: Bool { width >= 768 }
    private var collapsed: Bool { header != .top }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The web's back row: its button is clipped away, leaving 64pt.
            Color.clear.frame(height: collapsed ? 0 : 64)

            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Curated Collection")
                        .font(.gilda(medium ? 28 : 24))
                        .foregroundStyle(Color(hex: 0x111827))
                    Text("From everyday elegance to statement pieces")
                        .font(.manrope(medium ? 16 : 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x99A1AF))
                }
                .frame(maxWidth: .infinity, maxHeight: collapsed ? 0 : 100, alignment: .topLeading)
                .opacity(collapsed ? 0 : 1)
                .clipped()

                VStack(alignment: .leading, spacing: collapsed ? 0 : 48) {
                    categoryRow
                        .frame(maxHeight: collapsed ? 0 : 400, alignment: .top)
                        .opacity(collapsed ? 0 : 1)
                        .clipped()
                        .allowsHitTesting(!collapsed)
                    EmployeeFilterRow(state: $filters)
                }
            }
        }
        .frame(maxWidth: 1280, alignment: .leading)
        .padding(.horizontal, medium ? 32 : 16)
        .padding(.top, collapsed ? 12 : 32)
        .padding(.bottom, collapsed ? 12 : 24)
        .frame(maxWidth: .infinity)
        .background {
            Color.white.opacity(0.95)
                .background(.ultraThinMaterial)
                .shadow(color: .black.opacity(collapsed ? 0.1 : 0), radius: 1.5, y: 1)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF3F4F6)).frame(height: 1) }
        // Scrolling back up slides the whole bar out of sight.
        .visualEffect { [hidden = header == .up] content, geo in
            content.offset(y: hidden ? -geo.size.height : 0)
        }
    }

    private var categoryRow: some View {
        HStack(alignment: .center, spacing: 0) {
            FlowRow(spacing: medium ? 32 : 16, lineSpacing: 24) {
                ForEach(EmployeeCategoryArt.catalogueNames, id: \.self) { name in
                    let key = name.lowercased()
                    EmployeeCatalogueTile(
                        name: name,
                        imageURL: EmployeeCategoryArt.catalogueURL(for: key),
                        isActive: category == key,
                        medium: medium
                    ) { category = key }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { category = "all" } label: {
                Text("View all")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .underline(color: Color(hex: 0xE5E7EB))
            }
            .buttonStyle(.plain)
            .fixedSize()
            // `margin-bottom: 40px` lifts it 20pt above centre.
            .padding(.bottom, 40)
        }
    }

    // MARK: - Content

    private func content(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if !loaded {
                ProgressView().padding(.top, 64)
            } else if failed && products.isEmpty {
                VStack(spacing: 12) {
                    Text("Couldn't load the catalogue.")
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6A7282))
                    Button("Try again") { Task { await load() } }
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                }
                .padding(.top, 64)
            } else if filtered.isEmpty {
                emptyState
            } else {
                let columns = width >= 768 ? 3 : width >= 640 ? 2 : 1
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 48, alignment: .top), count: columns),
                    spacing: 96
                ) {
                    ForEach(pageItems) { product in
                        EmployeeProductCard(
                            product: product,
                            onTap: { store.push(.review(productID: product.id)) },
                            onLongPress: { toggle(product) }
                        )
                    }
                }

                if totalPages > 1 {
                    EmployeePager(page: page, totalPages: totalPages) { next in
                        page = next
                        withAnimation(.smooth) { proxy.scrollTo("top", anchor: .top) }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: 1280)
        .padding(.horizontal, medium ? 32 : 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No products found.")
                .font(.manrope(14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6A7282))
            Text("Try adjusting your category or feature filters.")
                .font(.manrope(12))
                .foregroundStyle(Color(hex: 0x99A1AF))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 64)
        .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xE5E7EB), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    // MARK: - Selection

    private func toggle(_ product: Product) {
        let name = product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.trimmed.nilIfEmpty ?? "Product"
        let added = store.toggleSelection(product.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        notice = added ? "\(name) added to selection." : "\(name) removed from selection."
    }

    // MARK: - Filtering

    /// The web's two passes: the server keeps pieces whose category, type or
    /// title contains the tile's name, then the page keeps those whose
    /// category or type contains it without its final "s". So "Rings" also
    /// lists earrings, as it does on the web.
    private var filtered: [Product] {
        products.filter { product in
            let fields = [product.category, product.jewelleryType].map { $0?.lowercased() ?? "" }
            if category != "all" {
                let title = product.title?.lowercased() ?? ""
                guard (fields + [title]).contains(where: { $0.contains(category) }) else { return false }
                let base = category.hasSuffix("s") ? String(category.dropLast()) : category
                guard fields.contains(where: { $0.contains(base) }) else { return false }
            }
            return filters.matches(size: product.size, purity: product.metalPurity,
                                   netWeight: product.netWeight, inStock: product.stockAvailable,
                                   productionDays: product.makeToOrderDays, tags: [])
        }
    }

    private var totalPages: Int {
        (filtered.count + Self.perPage - 1) / Self.perPage
    }

    private var pageItems: [Product] {
        let all = filtered
        let start = (page - 1) * Self.perPage
        guard start < all.count else { return [] }
        return Array(all[start..<min(start + Self.perPage, all.count)])
    }

    private func load() async {
        #if DEBUG
        if let peek = store.peekProducts {
            products = peek
            loaded = true
            return
        }
        #endif
        guard let session = store.session else { return }
        do {
            let fetched = try await EmployeeAPI.fetchSelectedProducts(retailerID: session.retailerID)
            products = fetched
            store.cache(fetched)
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }
}

// MARK: - Tile

/// A soft grey tile with the category's artwork; the chosen one grows and
/// gets a pale ring.
private struct EmployeeCatalogueTile: View {
    let name: String
    let imageURL: URL?
    let isActive: Bool
    let medium: Bool
    let action: () -> Void

    var body: some View {
        let side: CGFloat = medium ? 72 : 48
        let radius: CGFloat = medium ? 20 : 16
        let labelSize: CGFloat = medium ? 12 : 11

        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Color(hex: 0xF9FAFB)
                    if EmployeeCategoryArt.isHaram(name.lowercased()) {
                        Image("CatHaram").resizable().scaledToFill()
                    } else {
                        CachedImage(url: imageURL)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(.rect(cornerRadius: radius))
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: radius + 4)
                            .fill(Color(hex: 0xF3F4F6))
                            .padding(-4)
                    }
                }

                Text(name)
                    .font(.manrope(labelSize, weight: isActive ? .bold : .medium))
                    .kerning(labelSize * 0.025)
                    .foregroundStyle(isActive ? Color(hex: 0x111827) : Color(hex: 0x99A1AF))
                    .opacity(isActive ? 1 : 0.8)
                    .lineLimit(1)
                    .fixedSize()
            }
            .scaleEffect(isActive ? 1.1 : 1)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Card

/// A full-bleed square photo and its name. Tap opens it; holding it for half
/// a second toggles it in the selection.
private struct EmployeeProductCard: View {
    let product: Product
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressing = false

    private var title: String {
        product.title?.nilIfEmpty ?? product.jewelleryType?.nilIfEmpty ?? "Untitled"
    }

    var body: some View {
        VStack(spacing: 0) {
            Color(hex: 0xF4F4F4)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url = product.catalogueImageURL {
                        ProtectedImageView(url: url, contentMode: .scaleAspectFill, multiply: true)
                    } else {
                        Text("No image")
                            .font(.manrope(12, weight: .light))
                            .foregroundStyle(Color(hex: 0xD1D5DC))
                    }
                }
                .clipped()

            Text(title)
                .font(.cirka(15))
                .kerning(0.375)
                .foregroundStyle(Color(hex: 0x1E2939))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.top, 16)
        }
        .background(Color.white)
        .scaleEffect(pressing ? 0.95 : 1)
        .opacity(pressing ? 0.8 : 1)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3), value: pressing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) {
            pressing = false
            onLongPress()
        } onPressingChanged: { pressing = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Add to or remove from selection", onLongPress)
    }
}

// MARK: - Product images, as the employee pages order them

extension Product {
    /// The Catalogue card: processed, then the first render, then the
    /// original upload.
    var catalogueImageURL: URL? {
        [processedImageURL, generatedImageURLs.first, rawImageURL]
            .compactMap { $0?.trimmed.nilIfEmpty }
            .first
            .flatMap { url(for: $0, size: .card) }
    }

    /// The detail page's pictures: the renders and the processed photo, at
    /// most four; the original only when there is nothing else.
    func reviewImages(_ size: ImageSize) -> [URL] {
        var seen = Set<String>()
        var list: [String] = []
        for raw in generatedImageURLs + [processedImageURL].compactMap({ $0 }) {
            guard let value = raw.trimmed.nilIfEmpty, seen.insert(value).inserted else { continue }
            list.append(value)
        }
        if list.isEmpty, let raw = rawImageURL?.trimmed.nilIfEmpty { list = [raw] }
        return list.prefix(4).compactMap { url(for: $0, size: size) }
    }

    /// Cards on the detail page: the first render, else processed, else the
    /// original.
    var reviewCardImageURL: URL? {
        [generatedImageURLs.first, processedImageURL, rawImageURL]
            .compactMap { $0?.trimmed.nilIfEmpty }
            .first
            .flatMap { url(for: $0, size: .card) }
    }
}
