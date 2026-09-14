import SwiftUI

/// Global, product-first catalogue for verified retailers. Supplier profile
/// information is intentionally absent from every browse card and detail view.
struct YourTasteView: View {
    @State private var products: [Product] = []
    @State private var selectedProductIDs = Set<String>()
    @State private var selectedCategory: String?
    @State private var selectedProduct: Product?
    @State private var search = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var updatingIDs = Set<String>()

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    private var categories: [String] {
        Array(Set(products.compactMap { ($0.jewelleryType ?? $0.category)?.trimmed.nilIfEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleProducts: [Product] {
        products.filter { product in
            let categoryMatches: Bool
            if let selectedCategory {
                categoryMatches = (product.jewelleryType ?? product.category)?
                    .caseInsensitiveCompare(selectedCategory) == .orderedSame
            } else {
                categoryMatches = true
            }

            let needle = search.trimmed.lowercased()
            let searchMatches = needle.isEmpty || [
                product.title, product.jewelleryType, product.category,
                product.style, product.metalPurity,
            ]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(needle) }
            return categoryMatches && searchMatches
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !categories.isEmpty { categoryTabs }

            Group {
                if isLoading && products.isEmpty {
                    ProgressView("Loading catalogue…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, products.isEmpty {
                    errorState(error)
                } else if visibleProducts.isEmpty {
                    ContentUnavailableView(
                        "No designs found",
                        systemImage: "sparkles",
                        description: Text("Try another category or search term.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Spacing.xl) {
                            ForEach(visibleProducts) { product in
                                MarketplaceProductCard(
                                    product: product,
                                    isSelected: selectedProductIDs.contains(product.id),
                                    isUpdating: updatingIDs.contains(product.id),
                                    onOpen: { selectedProduct = product },
                                    onToggle: { Task { await toggle(product) } }
                                )
                            }
                        }
                        .padding(Spacing.base)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .background(Color.white)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedProduct) { product in
            MarketplaceProductDetail(product: product)
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.muted)
            TextField("Search all jewellery", text: $search)
                .font(.manrope(14))
                .textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                categoryButton("All", selected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(categories, id: \.self) { category in
                    categoryButton(category.capitalized, selected: selectedCategory == category) {
                        selectedCategory = category
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
                .foregroundStyle(selected ? Color.white : Palette.dark)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Palette.dark : Palette.background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn’t load catalogue", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await JewelAPI.fetchRetailerMarketplace()
            products = response.products
            selectedProductIDs = Set(response.selectedProductIDs)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggle(_ product: Product) async {
        guard !updatingIDs.contains(product.id) else { return }
        let shouldSelect = !selectedProductIDs.contains(product.id)
        updatingIDs.insert(product.id)
        if shouldSelect { selectedProductIDs.insert(product.id) }
        else { selectedProductIDs.remove(product.id) }

        do {
            try await JewelAPI.setRetailerSelection(productID: product.id, selected: shouldSelect)
        } catch {
            if shouldSelect { selectedProductIDs.remove(product.id) }
            else { selectedProductIDs.insert(product.id) }
            self.error = error.localizedDescription
        }
        updatingIDs.remove(product.id)
    }
}

private struct MarketplaceProductCard: View {
    let product: Product
    let isSelected: Bool
    let isUpdating: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onOpen) {
                ZStack {
                    Color(hex: 0xF7F7F7)
                    if let url = product.displayImageURL(.card) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Palette.muted)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .clipped()
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Untitled")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(1)
                    Text(product.netWeight.map { String(format: "%.2fg", $0) } ?? "View details")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "heart.fill" : "heart")
                        .foregroundStyle(isSelected ? Color.pink : Palette.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .opacity(isUpdating ? 0.45 : 1)
                .accessibilityLabel(isSelected ? "Remove from selections" : "Save design")
            }
        }
    }
}

private struct MarketplaceProductDetail: View {
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var showsOrderRequest = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ZStack {
                        Color(hex: 0xF7F7F7)
                        if let url = product.displayImageURL(.detail) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { ProgressView() }
                        }
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Jewellery Design")
                            .font(.cirka(26))
                            .foregroundStyle(Palette.foreground)
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
                }
                .padding(Spacing.base)
            }
            .navigationTitle("Design Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsOrderRequest) {
                RetailerOrderRequestSheet(product: product)
            }
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
    let product: Product

    @State private var quantity = 1
    @State private var notes = ""
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
                    Form {
                        Section("Design") {
                            Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Jewellery Design")
                        }

                        Section("Order request") {
                            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                            TextField("Customization notes (optional)", text: $notes, axis: .vertical)
                                .lineLimit(3...7)
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
                        }
                    }
                }
            }
            .navigationTitle(didSubmit ? "Request Sent" : "Place Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.green)
            Text("Request sent")
                .font(.cirka(28))
                .foregroundStyle(Palette.foreground)

            if let supplier {
                VStack(spacing: 4) {
                    Text("Supplied by")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                    Text(supplier.displayName)
                        .font(.manrope(18, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                    let location = [supplier.city, supplier.state]
                        .compactMap { $0?.trimmed.nilIfEmpty }
                        .joined(separator: ", ")
                    if !location.isEmpty {
                        Text(location)
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("The wholesaler has received your request.")
                    .font(.manrope(14))
                    .foregroundStyle(Palette.muted)
            }

            Text("You can track progress from Orders.")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
            Spacer()
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}
