import SwiftUI
import PhotosUI

/// Global, product-first catalogue for verified retailers. Supplier profile
/// information is intentionally absent from every browse card and detail view.
///
/// Two uses of the one grid. On its own, the heart keeps the store's
/// shortlist — what staff browse as their catalogue. Given a `board`, the
/// bookmark saves to that customer's board instead and the shortlist is left
/// alone.
struct YourTasteView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.employeeAppearance) private var appearance
    var board: CustomerBoard?

    #if DEBUG
    /// Deterministic catalogue data for native UI verification.
    var peekProducts: [Product]?
    #endif

    @State private var store = MarketplaceCatalogueStore.shared
    @State private var selectedProduct: Product?
    @State private var search = ""
    @State private var imageSearch = CatalogueImageSearchModel()
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var hydratedMatchProducts: [Product]?
    @State private var showManufacturingSheet = false
    @State private var handoffImage: UIImage?
    @State private var handoffCategory: String?

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    private var canSearchImages: Bool {
        return session.phase == .authenticated(.retailerDashboard)
    }

    private var categories: [String] {
        if !store.categories.isEmpty {
            return store.categories.map(\.name)
        }
        return Array(Set(store.products.compactMap { $0.jewelleryType?.trimmed.nilIfEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleProducts: [Product] {
        #if DEBUG
        if let peekProducts { return peekProducts }
        #endif
        if imageSearch.matchIDs != nil {
            return hydratedMatchProducts ?? []
        }
        return store.products
    }

    private var effectiveSelectedIDs: Set<String> {
        if let board {
            return Set(board.products.map(\.id))
        }
        return store.selectedProductIDs
    }

    @ViewBuilder
    private var catalogueContent: some View {
        if store.isInitialLoading && store.products.isEmpty {
            ProgressView("Loading catalogue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.error, store.products.isEmpty {
            errorState(error)
        } else if imageSearch.isSearching {
            ProgressView("Finding close matches…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if imageSearch.matchIDs?.isEmpty == true {
            noMatchView
        } else if visibleProducts.isEmpty {
            ContentUnavailableView(
                "No designs found",
                systemImage: "sparkles",
                description: Text("Try another category or search term.")
            )
        } else {
            productGridView
        }
    }

    private var mainVStack: some View {
        VStack(spacing: 0) {
            searchField
            if !categories.isEmpty { categoryTabs }
            if canSearchImages { imageSearchPanel }
            catalogueContent
        }
    }

    var body: some View {
        mainVStack
            .background(appearance.panel())
        .navigationTitle(board.map { "Add to \($0.title)" } ?? "Discover")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG
            if peekProducts != nil { return }
            #endif
            store.configure(for: session.user?.id.uuidString)
            await store.loadInitial()
            await LikeBook.shared.load()
        }
        .refreshTask {
            await store.refresh()
            await LikeBook.shared.load(force: true)
        }
        .onChange(of: pickedPhoto) { _, item in
            if let item {
                search = ""
                hydratedMatchProducts = nil
                imageSearch.read(item)
            }
        }
        .onChange(of: imageSearch.matchIDs) { _, ids in
            if let ids {
                Task {
                    hydratedMatchProducts = try? await store.hydrateMatches(ids: ids)
                }
            } else {
                hydratedMatchProducts = nil
            }
        }
        .onChange(of: store.selectedCategory) { _, _ in
            if !imageSearch.isReading {
                imageSearch.reset()
                hydratedMatchProducts = nil
            }
        }
        .onChange(of: search) { _, newSearch in
            if !imageSearch.isReading {
                imageSearch.reset()
                hydratedMatchProducts = nil
            }
            store.updateSearchQuery(newSearch)
        }
        .onChange(of: session.phase) { _, _ in
            imageSearch.reset(clearPhoto: true)
            pickedPhoto = nil
            hydratedMatchProducts = nil
        }
        .onDisappear {
            if !showManufacturingSheet {
                imageSearch.reset(clearPhoto: true)
                hydratedMatchProducts = nil
            }
        }
        .sheet(item: $selectedProduct) { product in
            MarketplaceProductDetail(product: product).employeePresentationChrome()
        }
        .sheet(isPresented: $showManufacturingSheet) {
            CreateManufacturingRequestSheet(
                initialImage: handoffImage,
                initialCategory: handoffCategory
            )
        }
    }

    @ViewBuilder
    private var noMatchView: some View {
        VStack(spacing: Spacing.lg) {
            ContentUnavailableView(
                "No close matches",
                systemImage: "photo.badge.magnifyingglass",
                description: Text("Try another photo or jewellery category.")
            )

            if canSearchImages {
                Button {
                    handoffImage = imageSearch.preview
                    handoffCategory = store.selectedCategory
                    showManufacturingSheet = true
                } label: {
                    Label("Request wholesalers to make this", systemImage: "sparkles")
                        .font(.manrope(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.dark)
                .foregroundStyle(Palette.light)
                .padding(.horizontal, Spacing.xl)
                .accessibilityIdentifier("retailer-request-manufacturing-button")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var productGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.xl) {
                ForEach(visibleProducts) { product in
                    MarketplaceProductCard(
                        product: product,
                        isSelected: effectiveSelectedIDs.contains(product.id),
                        isUpdating: store.isSelectionUpdating(for: product.id),
                        savesToBoard: board != nil,
                        onOpen: { selectedProduct = product },
                        onToggle: { Task { await toggle(product) } }
                    )
                    .onAppear {
                        if imageSearch.matchIDs == nil, product == visibleProducts.suffix(4).first {
                            Task { await store.loadMore() }
                        }
                    }
                }
            }
            .padding(Spacing.base)

            if imageSearch.matchIDs == nil {
                if store.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                } else if let loadMoreError = store.loadMoreError {
                    VStack(spacing: 8) {
                        Text(loadMoreError)
                            .font(.manrope(12))
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await store.loadMore() }
                        }
                        .font(.manrope(12, weight: .semibold))
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(appearance.secondaryInk(Palette.muted))
            TextField("Search all jewellery", text: $search)
                .font(.manrope(14))
                .textInputAutocapitalization(.never)
            if canSearchImages {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Image(systemName: "photo.badge.magnifyingglass")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Upload jewellery photo to search")
                .accessibilityIdentifier("retailer-image-search-picker")
            }
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(appearance.secondaryInk(Palette.muted))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(appearance.quiet(Palette.background), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var imageSearchPanel: some View {
        if imageSearch.preview != nil || imageSearch.isReading || imageSearch.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let preview = imageSearch.preview {
                        Image(uiImage: preview).resizable().scaledToFit()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(imageSearch.isReading ? "Reading photo…" : "Find similar jewellery")
                            .font(.manrope(14, weight: .semibold))
                        Text(store.selectedCategory == nil ? "Select a jewellery category to search." : "Search in \((store.selectedCategory ?? "").capitalized)")
                            .font(.manrope(12)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Button("Clear") {
                        imageSearch.reset(clearPhoto: true)
                        pickedPhoto = nil
                        hydratedMatchProducts = nil
                    }
                    .accessibilityIdentifier("retailer-image-search-clear")
                }
                if imageSearch.isSearching {
                    ProgressView().controlSize(.small)
                    HStack {
                        Text("Searching the catalogue…")
                        Spacer()
                        Button("Cancel") { imageSearch.reset() }
                            .accessibilityIdentifier("retailer-image-search-cancel")
                    }.font(.manrope(12))
                } else if imageSearch.preview != nil {
                    Button {
                        imageSearch.search(category: store.selectedCategory ?? "")
                    } label: {
                        Label("Search by photo", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.dark)
                    .disabled(store.selectedCategory == nil || store.isInitialLoading)
                    .accessibilityIdentifier("retailer-image-search-start")
                }
                if let ids = imageSearch.matchIDs {
                    Text("\(ids.count) close \(ids.count == 1 ? "match" : "matches")")
                        .font(.manrope(12, weight: .semibold))
                }
                if imageSearch.skipped > 0 {
                    Text("\(imageSearch.skipped) catalogue photos couldn’t be checked. You can retry.")
                        .font(.manrope(12)).foregroundStyle(Palette.muted)
                }
                if let error = imageSearch.error {
                    Text(error).font(.manrope(12)).foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, Spacing.base).padding(.bottom, Spacing.sm)
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                categoryButton("All", selected: store.selectedCategory == nil) {
                    store.selectCategory(nil)
                }
                ForEach(categories, id: \.self) { category in
                    categoryButton(category.capitalized, selected: store.selectedCategory?.caseInsensitiveCompare(category) == .orderedSame) {
                        store.selectCategory(category)
                    }
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.bottom, Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func categoryButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(selected ? appearance.onAccent : appearance.ink(Palette.dark))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? (appearance.inEmployeeView ? appearance.accent : Palette.dark) : appearance.quiet(Palette.background), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn’t load catalogue", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await store.loadInitial(forceRefresh: true) } }
        }
    }

    private func toggle(_ product: Product) async {
        do {
            try await store.toggleSelection(for: product, onBoard: board)
        } catch {
            // Error handling & rollback managed by store
        }
    }
}

struct MarketplaceProductCard: View {
    @Environment(\.employeeAppearance) private var appearance
    let product: Product
    let isSelected: Bool
    let isUpdating: Bool
    var savesToBoard = false
    let onOpen: () -> Void
    let onToggle: () -> Void

    /// Board mode saves to a customer's board; otherwise it adds the design
    /// to the store's shortlist, which staff browse as their catalogue. The
    /// heart beside it is a like, and is separate from both.
    private var toggleIcon: String {
        if savesToBoard { return isSelected ? "bookmark.fill" : "bookmark" }
        return isSelected ? "checkmark.circle.fill" : "plus.circle"
    }

    private var toggleTint: Color {
        isSelected ? appearance.ink(Palette.dark) : appearance.secondaryInk(Palette.muted)
    }

    private var imageOpener: some View {
        Button(action: onOpen) {
            ZStack {
                Color(hex: 0xF7F7F7)
                if let url = product.displayImageURL(.card) {
                    ProtectedImageView(url: url)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(appearance.secondaryInk(Palette.muted))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .clipped()
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if appearance.inEmployeeView {
                imageOpener.accessibilityLabel("View design, \(product.displayTitle)")
            } else {
                imageOpener
            }

            HStack(alignment: .top, spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Untitled")
                        .font(appearance.body(13, weight: .bold))
                        .foregroundStyle(appearance.ink(Palette.foreground))
                        .lineLimit(1)
                    Text(product.netWeight.map { String(format: "%.2fg", $0) } ?? "View details")
                        .font(appearance.body(11))
                        .foregroundStyle(appearance.secondaryInk(Palette.muted))
                }
                Spacer(minLength: 0)
                LikeButton(productID: product.id, size: appearance.inEmployeeView ? 22 : 17)
                    .frame(minWidth: appearance.inEmployeeView ? 44 : 0, minHeight: appearance.inEmployeeView ? 44 : 0)
                Button(action: onToggle) {
                    Image(systemName: toggleIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(toggleTint)
                        .frame(width: appearance.inEmployeeView ? 44 : 32, height: appearance.inEmployeeView ? 44 : 32)
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .opacity(isUpdating ? 0.45 : 1)
                .accessibilityLabel(
                    savesToBoard
                        ? (isSelected ? "Remove from board" : "Save to board")
                        : (isSelected ? "Remove from store catalogue" : "Add to store catalogue")
                )
            }
        }
    }
}

struct MarketplaceProductDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.employeeAppearance) private var appearance
    let product: Product
    @State private var showsOrderRequest = false
    @State private var viewerOpen = false
    @State private var chat: OpenedChat?
    @State private var isOpeningChat = false
    @State private var chatError: String?

    private struct OpenedChat: Identifiable {
        let id: String
        #if DEBUG
        var peekMessages: [ChatMessage]?
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if appearance.inEmployeeView { employeeDetail }
                else { standardDetail }
            }
            .task { StoreActivity.log(.designViewed, productID: product.id) }
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.bool(forKey: "JewelEmployeeRequest") { showsOrderRequest = true }
            }
            #endif
            .sheet(item: $chat) { opened in
                NavigationStack {
                    #if DEBUG
                    ChatThreadView(
                        conversationID: opened.id,
                        title: product.title?.trimmed.nilIfEmpty ?? "Design enquiry",
                        side: "employee",
                        peekMessages: opened.peekMessages
                    )
                    #else
                    ChatThreadView(
                        conversationID: opened.id,
                        title: product.title?.trimmed.nilIfEmpty ?? "Design enquiry",
                        side: "employee"
                    )
                    #endif
                }
                .employeePresentationChrome()
            }
            .alert(chatError ?? "", isPresented: Binding(
                get: { chatError != nil },
                set: { if !$0 { chatError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $viewerOpen) {
                JewelFullImageViewer(urls: product.thumbnailURLs(.full), startIndex: 0) { viewerOpen = false }
                    .employeePresentationChrome()
            }
            .navigationTitle("Design Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsOrderRequest) {
                RetailerOrderRequestSheet(product: product).employeePresentationChrome()
            }
        }
    }

    private var standardDetail: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ZStack {
                        Color(hex: 0xF7F7F7)
                        if let url = product.displayImageURL(.detail) {
                            ProtectedImageView(url: url, contentMode: .scaleAspectFit)
                        }
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Jewellery Design")
                                .font(.cirka(26))
                                .foregroundStyle(Palette.foreground)
                            Spacer(minLength: 8)
                            LikeButton(productID: product.id, size: 22)
                        }
                        detailRow("Category", product.jewelleryType ?? product.category)
                        detailRow("Style", product.style)
                        detailRow("Purity", product.metalPurity)
                        detailRow("Net weight", product.netWeight.map { String(format: "%.2f g", $0) })
                        detailRow("Availability", product.stockAvailable.map { $0 ? "In stock" : "Made to order" })
                        detailRow("Production", product.makeToOrderDays.map { "\($0) days" })
                    }

                    Text("Supplier details stay private while you browse and are shown during the order process.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .padding(12)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))

                    Button { showsOrderRequest = true } label: {
                        Label("Request this Design", systemImage: "bag.badge.plus")
                            .font(.manrope(15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button { Task { await openChat() } } label: {
                        HStack(spacing: 8) {
                            if isOpeningChat {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bubble.left")
                            }
                            Text("Ask About this Design")
                        }
                        .font(.manrope(15, weight: .bold))
                        .foregroundStyle(Palette.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.dark, lineWidth: 1.5) }
                    }
                    .buttonStyle(.plain)
                    .disabled(isOpeningChat)
                }
                .padding(Spacing.base)
            }
    }

    private var employeeDetail: some View {
        EmployeeDetailLayout(onClose: { dismiss() }) { _ in
            Button { if product.hasDisplayImage { viewerOpen = true } } label: {
                appearance.subtle
                    .overlay {
                        if let url = product.displayImageURL(.detail) {
                            ProtectedImageView(url: url, contentMode: .scaleAspectFit,
                                               watermark: true, multiply: !appearance.dark)
                        } else {
                            Text("No image").font(appearance.body(14)).foregroundStyle(appearance.muted)
                        }
                    }
                    .clipShape(.rect(cornerRadius: appearance.cardRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View image of \(product.displayTitle)")
            .overlay(alignment: .bottomTrailing) {
                GlassCircleButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Zoom image") { if product.hasDisplayImage { viewerOpen = true } }
                    .padding(12)
            }
            .padding(12)
        } details: { contentWidth in
            VStack(alignment: .leading, spacing: 20) {
                Text(product.displayTitle)
                    .font(appearance.display(26)).foregroundStyle(appearance.text)
                    .fixedSize(horizontal: false, vertical: true)
                GlassLikeButton(productID: product.id)
                DetailSpecRow(label: "Category", value: product.jewelleryType ?? product.category ?? "—", width: contentWidth)
                if let style = product.style { DetailSpecRow(label: "Style", value: style, width: contentWidth) }
                DetailSpecRow(label: "Purity", value: product.metalPurity ?? "—", width: contentWidth)
                DetailSpecRow(label: "Net weight", value: formatGrams(product.netWeight) ?? "—", width: contentWidth)
                DetailSpecRow(label: "Availability", value: product.stockAvailable.map { $0 ? "In stock" : "Made to order" } ?? "—", width: contentWidth)
                if let days = product.makeToOrderDays { DetailSpecRow(label: "Production", value: "\(days) days", width: contentWidth) }
                Text("Supplier details stay private while you browse and are shown during the order process.")
                    .font(appearance.body(12)).foregroundStyle(appearance.muted)
                Button { showsOrderRequest = true } label: {
                    Label("Request this Design", systemImage: "bag.badge.plus")
                        .font(appearance.body(15, weight: .bold))
                        .foregroundStyle(appearance.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(12)
                        .background(appearance.accent, in: .rect(cornerRadius: appearance.controlRadius))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("marketplace-detail-request-open")
                Button { Task { await openChat() } } label: {
                    HStack(spacing: 8) {
                        if isOpeningChat { ProgressView().controlSize(.small) }
                        else { Image(systemName: "bubble.left") }
                        Text("Ask About this Design")
                    }
                    .font(appearance.body(15, weight: .bold)).foregroundStyle(appearance.text)
                    .frame(maxWidth: .infinity, minHeight: 44).padding(12)
                    .overlay { RoundedRectangle(cornerRadius: appearance.controlRadius).stroke(appearance.border, lineWidth: 1) }
                }
                .buttonStyle(.plain).disabled(isOpeningChat)
            }
        }
        .background(appearance.background)
    }

    private func openChat() async {
        guard !isOpeningChat else { return }
        isOpeningChat = true
        defer { isOpeningChat = false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "JewelEmployeeLocalChat") {
            chat = OpenedChat(id: "employee-loop-local-chat", peekMessages: [])
            return
        }
        #endif
        do {
            chat = OpenedChat(id: try await ChatAPI.open(productID: product.id))
        } catch {
            chatError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value = value?.trimmed.nilIfEmpty {
            HStack {
                Text(label).foregroundStyle(Palette.muted)
                Spacer()
                Text(value).foregroundStyle(Palette.foreground)
            }
            .font(.manrope(13))
        }
    }
}

private struct RetailerOrderRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.employeeAppearance) private var appearance
    let product: Product

    @State private var quantity = 1
    @State private var notes = ""
    @FocusState private var notesFocused: Bool
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var supplier: JewelAPI.SupplierSummary?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Group {
                if didSubmit {
                    successView
                } else {
                    VStack(spacing: 0) {
                        if appearance.inEmployeeView && notesFocused {
                            Button { Task { await submit() } } label: {
                                Text(isSubmitting ? "Sending…" : "Send Request")
                                    .font(appearance.body(14, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("marketplace-request-keyboard-submit")
                            .disabled(isSubmitting)
                            .padding(.horizontal, Spacing.base)
                            .padding(.vertical, Spacing.sm)
                            .background(appearance.panel())
                        }
                        Form {
                        Section("Design") {
                            Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Jewellery Design")
                        }

                        Section("Order request") {
                            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                            TextField("Customization notes (optional)", text: $notes, axis: .vertical)
                                .lineLimit(3...7)
                                .focused($notesFocused)
                                .accessibilityIdentifier("marketplace-request-notes")
                        }

                        if let error {
                            Section {
                                Text(error)
                                    .foregroundStyle(Color.red)
                            }
                        }

                        Section {
                            Button {
                                Task { await submit() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isSubmitting { ProgressView().tint(.white) }
                                    Text(isSubmitting ? "Sending…" : "Send Request")
                                        .font(.manrope(14, weight: .bold))
                                    Spacer()
                                }
                                .foregroundStyle(Color.white)
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Palette.dark)
                            .disabled(isSubmitting)
                            .accessibilityIdentifier("marketplace-request-submit")
                        }
                        }
                        .accessibilityIdentifier("marketplace-request-body")
                    }
                }
            }
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.bool(forKey: "JewelEmployeeRequestSent") { didSubmit = true }
            }
            #endif
            .navigationTitle(didSubmit ? "Request Sent" : "Place Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? "Done" : "Cancel") { dismiss() }
                }
                if appearance.inEmployeeView && !didSubmit {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button { notesFocused = false } label: {
                            Text("Done")
                                .font(appearance.body(14, weight: .semibold))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityIdentifier("marketplace-request-keyboard-done")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var successView: some View {
        if appearance.inEmployeeView {
            ScrollView { successContent }
                .background(appearance.background)
        } else { successContent }
    }

    private var successContent: some View {
        VStack(spacing: Spacing.lg) {
            if !appearance.inEmployeeView { Spacer() }
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.green)
            Text("Request sent")
                .font(appearance.inEmployeeView ? appearance.display(28) : .cirka(28))
                .foregroundStyle(appearance.ink(Palette.foreground))

            if let supplier {
                VStack(spacing: 4) {
                    Text("Supplied by")
                        .font(.manrope(12))
                        .foregroundStyle(appearance.secondaryInk(Palette.muted))
                    Text(supplier.displayName)
                        .font(.manrope(18, weight: .bold))
                        .foregroundStyle(appearance.ink(Palette.foreground))
                    let location = [supplier.city, supplier.state]
                        .compactMap { $0?.trimmed.nilIfEmpty }
                        .joined(separator: ", ")
                    if !location.isEmpty {
                        Text(location)
                            .font(.manrope(13))
                            .foregroundStyle(appearance.secondaryInk(Palette.muted))
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(appearance.quiet(Palette.background), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("The wholesaler has received your request.")
                    .font(.manrope(14))
                    .foregroundStyle(appearance.secondaryInk(Palette.muted))
            }

            Text("You can track progress from Orders.")
                .font(.manrope(13))
                .foregroundStyle(appearance.secondaryInk(Palette.muted))
            if !appearance.inEmployeeView { Spacer() }
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.xl)
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        do {
            let response = try await JewelAPI.createRetailerOrder(
                productID: product.id,
                quantity: quantity,
                notes: notes.trimmed
            )
            if let wholesalerID = response.data.first?.wholesalerId {
                supplier = response.suppliers[wholesalerID]
            }
            didSubmit = true
            StoreActivity.log(.orderRequested, productID: product.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
