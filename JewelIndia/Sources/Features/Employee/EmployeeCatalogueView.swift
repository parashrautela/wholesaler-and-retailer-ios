import SwiftUI

/// The Catalogue tab (`/dashboard/employee/wholesaler-gallery`): the pieces
/// the store shortlisted from wholesalers, as a two-column feed of cards at
/// varied heights — the way Pinterest lays out a board.
///
/// Categories scroll sideways in one row; the filter chips stay pinned while
/// the feed scrolls. Tap a piece to open it (`EmployeeReviewView`); hold it
/// for half a second to add it to, or take it out of, the selection.
struct EmployeeCatalogueView: View {
    @Environment(EmployeeStore.self) private var store

    @State private var products: [Product] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var category = "all"
    @State private var filters = EmployeeFilterState()
    @State private var width: CGFloat = 390
    @State private var toast: String?

    private var medium: Bool { width >= 768 }
    private var ownerView: Bool { store.session?.isRetailer == true }
    private var gutter: CGFloat { medium ? 32 : 16 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                Section {
                    feed
                } header: {
                    filterBar
                }
            }
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshTask { await load() }
        .background(Color.white)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .task {
            if !loaded { await load() }
            await LikeBook.shared.load()
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x111827), in: Capsule())
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Curated Collection")
                    .font(.gilda(medium ? 30 : 26))
                    .foregroundStyle(Color(hex: 0x111827))
                Text(loaded ? "\(products.count) \(products.count == 1 ? "piece" : "pieces") from your wholesalers"
                            : "From everyday elegance to statement pieces")
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x99A1AF))
            }
            // The profile button floats top-right, and the title sits beside
            // it. A store owner also has the wide Employee View badge there,
            // so for them the title starts below it.
            .padding(.trailing, ownerView ? 0 : 64)
            .padding(.horizontal, gutter)
            .padding(.top, ownerView ? 72 : 20)

            categoryStrip
        }
        .padding(.bottom, 6)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: medium ? 20 : 14) {
                CategoryBubble(name: "All", imageURL: nil, isHaram: false, isActive: category == "all") {
                    category = "all"
                }
                ForEach(EmployeeCategoryArt.catalogueNames, id: \.self) { name in
                    let key = name.lowercased()
                    CategoryBubble(
                        name: name,
                        imageURL: EmployeeCategoryArt.catalogueURL(for: key),
                        isHaram: EmployeeCategoryArt.isHaram(key),
                        isActive: category == key
                    ) { category = category == key ? "all" : key }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(label: "Size", options: EmployeeFilterState.sizeOptions, selected: $filters.size)
                FilterChip(label: "Weight", options: EmployeeFilterState.weightOptions, selected: $filters.weight)
                FilterChip(label: "Availability", options: EmployeeFilterState.availabilityOptions,
                           selected: $filters.availability)
                FilterChip(label: "Purity", options: EmployeeFilterState.purityOptions, selected: $filters.purity)
                if !filters.isEmpty {
                    Button { filters = EmployeeFilterState() } label: {
                        Text("Clear")
                            .font(.manrope(13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xDC2626))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(.white.opacity(0.96))
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF3F4F6)).frame(height: 1) }
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        Group {
            if !loaded {
                MasonryGrid(items: (0..<6).map(Placeholder.init), columns: columnCount, spacing: 12) { slot in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: 0xF3F4F6))
                        .aspectRatio(PinShape.ratio(for: "\(slot.id)"), contentMode: .fit)
                }
            } else if failed && products.isEmpty {
                message("Couldn't load the catalogue.", detail: "Pull down to try again.")
            } else if filtered.isEmpty {
                VStack(spacing: 12) {
                    message(products.isEmpty ? "Nothing here yet." : "No pieces match.",
                            detail: products.isEmpty ? "Designs your store shortlists will appear here."
                                                     : "Try another category or clear the filters.")
                    if !filters.isEmpty || category != "all" {
                        Button("Show everything") {
                            filters = EmployeeFilterState()
                            category = "all"
                        }
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x111827))
                    }
                }
            } else {
                MasonryGrid(items: filtered, columns: columnCount, spacing: 12) { product in
                    PinCard(product: product,
                            onTap: { store.push(.review(productID: product.id)) },
                            onLongPress: { toggle(product) })
                }
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, 14)
    }

    private var columnCount: Int { width >= 1024 ? 4 : width >= 700 ? 3 : 2 }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.manrope(15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x374151))
            Text(detail)
                .font(.manrope(13))
                .foregroundStyle(Color(hex: 0x99A1AF))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    // MARK: - Selection

    private func toggle(_ product: Product) {
        let name = product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.trimmed.nilIfEmpty ?? "Piece"
        let added = store.toggleSelection(product.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let text = added ? "\(name) added to selection" : "\(name) removed from selection"
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
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

// MARK: - Category bubble

/// A round thumbnail and its name; the chosen one gets a dark ring.
private struct CategoryBubble: View {
    let name: String
    let imageURL: URL?
    let isHaram: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Color(hex: 0xF3F4F6)
                    if name == "All" {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(hex: 0x374151))
                    } else if isHaram {
                        Image("CatHaram").resizable().scaledToFill()
                    } else {
                        CachedImage(url: imageURL)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(Circle())
                .padding(3)
                .overlay {
                    Circle().stroke(isActive ? Color(hex: 0x111827) : Color.clear, lineWidth: 2)
                }

                Text(name)
                    .font(.manrope(11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
                    .lineLimit(1)
                    .fixedSize()
            }
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Filter chip

/// A compact pill that opens a checklist; it shows how many options are on.
private struct FilterChip: View {
    let label: String
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        let active = !selected.isEmpty
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
                } label: {
                    if selected.contains(option) {
                        Label(option.capitalized, systemImage: "checkmark")
                    } else {
                        Text(option.capitalized)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(active ? "\(label) · \(selected.count)" : label)
                    .font(.manrope(13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(active ? Color.white : Color(hex: 0x111827))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(active ? Color(hex: 0x111827) : Color(hex: 0xF3F4F6), in: Capsule())
        }
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel(active ? "\(label), \(selected.count) selected" : label)
    }
}

// MARK: - Masonry

/// Pinterest-style columns: each card goes to whichever column is shortest
/// so far, judged by the card's shape, so the columns stay level.
private struct MasonryGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(split[column]) { item in cell(item) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var split: [[Item]] {
        var lanes = Array(repeating: [Item](), count: columns)
        var heights = Array(repeating: CGFloat(0), count: columns)
        for item in items {
            let lane = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            lanes[lane].append(item)
            // Height per unit width, plus room for the caption.
            heights[lane] += 1 / PinShape.ratio(for: "\(item.id)") + 0.28
        }
        return lanes
    }
}

/// A grey card shown while the feed loads.
private struct Placeholder: Identifiable {
    let id: Int
}

/// Each piece gets a stable shape of its own, so the feed has rhythm without
/// cards jumping around between loads.
private enum PinShape {
    private static let ratios: [CGFloat] = [0.78, 1.0, 0.72, 0.86, 0.66]

    /// Width ÷ height.
    static func ratio(for id: String) -> CGFloat {
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return ratios[sum % ratios.count]
    }
}

// MARK: - Card

/// A photo at the card's own shape, a heart on it, and the name and key
/// details underneath. Tap opens it; holding it for half a second toggles it
/// in the selection.
private struct PinCard: View {
    let product: Product
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressing = false

    private var title: String {
        product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Untitled"
    }

    private var details: String? {
        let weight = product.netWeight.flatMap { $0 > 0 ? String(format: "%.1fg", $0) : nil }
        let purity = product.metalPurity?.trimmed.nilIfEmpty?.uppercased()
        return [purity, weight].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(hex: 0xF4F4F4)
                .aspectRatio(PinShape.ratio(for: product.id), contentMode: .fit)
                .overlay {
                    if let url = product.catalogueImageURL {
                        ProtectedImageView(url: url, contentMode: .scaleAspectFill, multiply: true)
                    } else {
                        Image(systemName: "photo").foregroundStyle(Color(hex: 0xD1D5DC))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottomTrailing) {
                    LikeButton(productID: product.id, size: 15)
                        .background(.white.opacity(0.92), in: Circle())
                        .padding(8)
                }
                .overlay(alignment: .topLeading) {
                    if product.stockAvailable == true {
                        Text("In stock")
                            .font(.manrope(10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x065F46))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.92), in: Capsule())
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x111827))
                    .lineLimit(2)
                if let details {
                    Text(details)
                        .font(.manrope(11))
                        .foregroundStyle(Color(hex: 0x6B7280))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .scaleEffect(pressing ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) {
            pressing = false
            onLongPress()
        } onPressingChanged: { pressing = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, details].compactMap { $0 }.joined(separator: ", "))
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
