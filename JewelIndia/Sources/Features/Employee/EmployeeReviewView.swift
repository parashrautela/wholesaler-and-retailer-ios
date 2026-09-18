import SwiftUI

/// `/dashboard/employee/playground/review` (`SelectionReviewClient.jsx`).
///
/// Opened with a product, it is that product's page: pictures, specs, and
/// "Send Request", with the rest of the long-pressed selection underneath.
/// Opened without one — or once a request from that page has gone — it is
/// the selection itself, which can be requested in one go.
struct EmployeeReviewView: View {
    @Environment(EmployeeStore.self) private var store
    let productID: String?

    private enum Sent: Equatable {
        case single(String)
        case bulk
    }

    @State private var loading = true
    @State private var didLoad = false
    /// The long-pressed pieces (never the opened product unless it was
    /// long-pressed too).
    @State private var products: [Product] = []
    @State private var viewing: Product?
    @State private var activeIndex = 0
    @State private var viewerOpen = false
    @State private var panelOpen = false
    /// Shared by every product on this page, as on the web.
    @State private var quantity = 1
    @State private var notes = ""
    @State private var submitting = false
    @State private var sent: Sent?
    @State private var errorMessage: String?
    @State private var width: CGFloat = 390

    #if DEBUG
    /// Peeks only: hold the confirmation instead of moving on.
    private var holdsSent = false
    #endif

    init(productID: String?) {
        self.productID = productID
    }

    #if DEBUG
    /// Peeks only.
    init(productID: String?, panelOpen: Bool, sent: Bool = false) {
        self.productID = productID
        _panelOpen = State(initialValue: panelOpen)
        _sent = State(initialValue: sent ? .bulk : nil)
        holdsSent = true
    }
    #endif

    private var sm: Bool { width >= 640 }
    private var md: Bool { width >= 768 }
    private var lg: Bool { width >= 1024 }

    var body: some View {
        ZStack {
            if sent != nil {
                RequestSentView { store.goHome() }
                    .transition(.opacity)
            } else if let product = viewing {
                detail(product)
            } else {
                selectionPage
            }

            if panelOpen, sent == nil, let product = viewing {
                requestPanel(product)
                    .zIndex(1)
            }
        }
        .animation(Motion.signature(0.35), value: panelOpen)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
        .task(id: sent) { await finishSending() }
        .alert(errorMessage ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $viewerOpen) {
            if let product = viewing {
                JewelFullImageViewer(urls: product.reviewImages(.full), startIndex: activeIndex,
                                     onIndexChange: { activeIndex = $0 }) { viewerOpen = false }
                    .presentationBackground(.clear)
            }
        }
    }

    // MARK: - Selection page (§4.7–4.9)

    private var selectionPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageHeader
                if loading {
                    Spinner().padding(.vertical, 128)
                } else if products.isEmpty {
                    VStack(spacing: 16) {
                        Text("No products selected.")
                            .font(.cirka(18))
                            .foregroundStyle(Color(hex: 0x6A7282))
                        Button { store.pop() } label: {
                            Text("Return to selection")
                                .font(.manrope(14))
                                .foregroundStyle(Color(hex: 0x155DFC))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 128)
                } else {
                    selectionGrid
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
    }

    private var pageHeader: some View {
        Text("Selected Items")
            .font(.gilda(md ? 38 : 30))
            .kerning(md ? 0.95 : 0.75)
            .foregroundStyle(Color(hex: 0x1A1A1A))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 56)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button { if viewing != nil { show(nil) } else { store.pop() } } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color(hex: 0x6A7282))
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [Color(hex: 0xF9FAFB), Color(hex: 0xE5E7EB)],
                                           startPoint: .top, endPoint: .bottom),
                            in: Circle()
                        )
                        .overlay { Circle().stroke(Color(hex: 0xD1D5DC), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Go back")
            }
            .padding(.horizontal, md ? 48 : 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
    }

    private var selectionGrid: some View {
        let columns = lg ? 3 : md ? 2 : 1
        return VStack(spacing: 0) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: columns),
                spacing: 48
            ) {
                ForEach(products) { product in
                    SelectionCard(product: product, imagePadding: 32, captionSize: 16, captionPadding: 20) {
                        show(product)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { remove(product.id) } label: {
                            Text("✕")
                                .font(.manrope(13))
                                .foregroundStyle(Color(hex: 0x6A7282))
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.8), in: Circle())
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(16)
                        .accessibilityLabel("Remove \(product.displayTitle)")
                    }
                }
            }

            Button(action: { Task { await submitSelection() } }) {
                HStack(spacing: 16) {
                    Text(submitting ? "SENDING REQUEST..." : "CONFIRM REQUEST")
                        .font(.manrope(14, weight: .semibold))
                        .kerning(2.8)
                    if !submitting {
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 64)
                .padding(.vertical, 20)
                .background(Color.black)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 16)
            }
            .buttonStyle(PressScaleStyle(scale: 0.99))
            .disabled(submitting)
            .opacity(submitting ? 0.7 : 1)
            .padding(.top, 80)
        }
        .frame(maxWidth: 1200)
        .padding(.horizontal, md ? 32 : 24)
        .padding(.top, 16)
        .padding(.bottom, 128)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Product page (§4.3)

    private func detail(_ product: Product) -> some View {
        let column: CGFloat = lg ? 700 : md ? 600 : sm ? 500 : 400
        let edge = cssClamp(20, 0.05, 40, width: width)

        return ZStack(alignment: .top) {
            ThemedDetailBackground(theme: store.session?.theme ?? .indian)

            ScrollView {
                VStack(spacing: 0) {
                    detailHeader(product)
                        .padding(.bottom, 40)
                    images(product)
                        .padding(.bottom, 48)
                    specs(product)
                        .padding(.top, 16)
                    moreYouMightLike(excluding: product)
                }
                .frame(maxWidth: column)
                .padding(.top, cssClamp(90, 0.10, 115, width: width))
                .padding(.horizontal, edge)
                .padding(.bottom, edge)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    GlassCircleButton(systemImage: "chevron.left", iconSize: 20, weight: .bold,
                                      label: "Go back", action: backFromDetail)
                        .padding(.leading, 40)
                        .padding(.top, 40)
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func detailHeader(_ product: Product) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let category = product.displayCategory {
                    let size = cssClamp(12, 0.018, 16, width: width)
                    Text(category.uppercased())
                        .font(.manrope(size, weight: .bold))
                        .kerning(size * 0.2)
                        .foregroundStyle(Color(hex: 0x6E6E6E))
                }
                if let style = product.style?.trimmed.nilIfEmpty {
                    let chip = cssClamp(10, 0.015, 12, width: width)
                    Text(style)
                        .font(.manrope(chip, weight: .medium))
                        .kerning(chip * 0.02)
                        .foregroundStyle(Color(hex: 0x515151))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xA8A8A8), lineWidth: 1)
                        }
                }
            }
            let titleSize = cssClamp(24, 0.04, 38, width: width)
            Text(product.displayTitle)
                .font(.gilda(titleSize))
                .kerning(titleSize * 0.025)
                .lineSpacing(titleSize * 0.2)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func images(_ product: Product) -> some View {
        let urls = product.reviewImages(.detail)
        let thumbs = product.reviewImages(.card)
        let active = urls.indices.contains(activeIndex) ? urls[activeIndex] : urls.first
        let boxWidth: CGFloat = md ? 320 : sm ? 280 : 240
        let zoomSize: CGFloat = sm ? 48 : 40
        let thumbSize: CGFloat = sm ? 55 : 45

        return HStack(alignment: .top, spacing: sm ? 24 : 16) {
            Button { if active != nil { viewerOpen = true } } label: {
                Color(hex: 0xF5F5F5)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        if let active {
                            ProtectedImageView(url: active, contentMode: .scaleAspectFit,
                                               watermark: true, multiply: true)
                        } else {
                            Text("No image")
                                .font(.manrope(14, weight: .light))
                                .foregroundStyle(Color(hex: 0xD1D5DC))
                        }
                    }
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xF3F4F6).opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: boxWidth)
            .overlay(alignment: .bottomTrailing) {
                GlassCircleButton(systemImage: "arrow.up.left.and.arrow.down.right",
                                  size: zoomSize, iconSize: 18, weight: .semibold,
                                  label: "Zoom image") { if active != nil { viewerOpen = true } }
                    .padding(12)
            }

            VStack(spacing: 8) {
                ForEach(Array(thumbs.enumerated()), id: \.offset) { offset, url in
                    let isActive = offset == activeIndex
                    Button { activeIndex = offset } label: {
                        ProtectedImageView(url: url, contentMode: .scaleAspectFit, watermark: true, multiply: true)
                            .frame(width: thumbSize, height: thumbSize)
                            .background(Color.white)
                            .clipShape(.rect(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isActive ? Color.white : Color(hex: 0xE5E7EB).opacity(0.8),
                                            lineWidth: isActive ? 2 : 1)
                            }
                            .overlay {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.black.opacity(0.1), lineWidth: 1)
                                        .padding(-1)
                                }
                            }
                            .shadow(color: .black.opacity(isActive ? 0.1 : 0), radius: 3, y: 4)
                            .scaleEffect(isActive ? 1.02 : 1)
                            .opacity(isActive ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                    .zIndex(isActive ? 1 : 0)
                    .accessibilityLabel("Picture \(offset + 1)")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func specs(_ product: Product) -> some View {
        let columnSize: CGFloat = lg ? 290 : md ? 250 : 210

        let left = VStack(alignment: .leading, spacing: 24) {
            DetailSpecSection(title: "Material", width: width) {
                DetailSpecRow(label: "Gold", value: product.metalPurity?.trimmed.nilIfEmpty ?? "—", width: width)
            }
            DetailSpecSection(title: "Weight", width: width) {
                VStack(spacing: 8) {
                    DetailSpecRow(label: "Net weight", value: rawGrams(product.netWeight), width: width)
                    DetailSpecRow(label: "Gross weight", value: rawGrams(product.grossWeight), width: width)
                    DetailSpecRow(label: "Stone weight", value: rawGrams(product.stoneWeight), width: width)
                }
            }
        }

        let right = VStack(alignment: .leading, spacing: 24) {
            DetailSpecSection(title: "Availability", width: width) {
                if product.stockAvailable == true {
                    DetailSpecRow(label: "In stock", value: "", width: width)
                } else {
                    DetailSpecRow(label: "Made to order",
                                  value: product.makeToOrderDays.map { "\($0) days" } ?? "—", width: width)
                }
            }
            VStack(spacing: 16) {
                Button { panelOpen = true } label: {
                    Text("SEND REQUEST")
                        .font(.manrope(16, weight: .bold))
                        .kerning(1.6)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [Color(hex: 0x3C3C3C), .black], startPoint: .top, endPoint: .bottom),
                            in: .rect(cornerRadius: 4)
                        )
                        .overlay { RoundedRectangle(cornerRadius: 4).stroke(.black, lineWidth: 1) }
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                }
                .buttonStyle(PressScaleStyle(scale: 0.99))

                Button { store.openChat(productID: product.id) } label: {
                    Text("Chat with us")
                        .font(.manrope(16, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(.black)
                        .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }

        if sm {
            HStack(alignment: .top) {
                left.frame(width: columnSize, alignment: .leading)
                Spacer(minLength: 0)
                right.frame(width: columnSize, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 32) {
                left
                right
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func moreYouMightLike(excluding current: Product) -> some View {
        let others = products.filter { $0.id != current.id }
        if !others.isEmpty {
            VStack(spacing: 32) {
                Text("More, you might like from us")
                    .font(.gilda(28))
                    .foregroundStyle(Color(hex: 0x1E2939))
                    .multilineTextAlignment(.center)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: md ? 3 : 1),
                    spacing: 32
                ) {
                    ForEach(others.prefix(6)) { product in
                        SelectionCard(product: product, imagePadding: 24, captionSize: 15, captionPadding: 12,
                                      bordered: true) {
                            show(product)
                        }
                    }
                }
            }
            .padding(.top, 48)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(hex: 0xE5E7EB).opacity(0.5)).frame(height: 1)
            }
            .padding(.top, 96)
        }
    }

    // MARK: - Request panel (§4.4)

    private func requestPanel(_ product: Product) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { panelOpen = false }
                .transition(.opacity)

            VStack(spacing: 0) {
                HStack {
                    Text("Request this Design")
                        .font(.gilda(14))
                        .foregroundStyle(Color(hex: 0x1E2939))
                    Spacer()
                    Button { panelOpen = false } label: {
                        Text("✕")
                            .font(.manrope(16))
                            .foregroundStyle(Color(hex: 0x99A1AF))
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF3F4F6)).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        panelSnippet(product)
                        panelQuantity
                        panelNotes
                    }
                    .padding(32)
                }
                .scrollDismissesKeyboard(.interactively)

                Button { Task { await submit(product) } } label: {
                    Text(submitting ? "SENDING..." : "SEND REQUEST")
                        .font(.manrope(12, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            LinearGradient(colors: [Color(hex: 0x2A2A2A), .black], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 16)
                }
                .buttonStyle(PressScaleStyle(scale: 0.99))
                .disabled(submitting)
                .opacity(submitting ? 0.7 : 1)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 420, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
            .shadow(color: .black.opacity(0.25), radius: 25, y: 25)
            .transition(.move(edge: .trailing))
        }
    }

    private func panelSnippet(_ product: Product) -> some View {
        let urls = product.reviewImages(.card)
        let active = urls.indices.contains(activeIndex) ? urls[activeIndex] : urls.first

        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                panelLabel("Product", size: 9)
                    .padding(.bottom, 6)
                HStack(spacing: 8) {
                    if let category = product.displayCategory {
                        Text(category.uppercased())
                            .font(.manrope(9))
                            .foregroundStyle(Color(hex: 0x6A7282))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xE5E7EB), lineWidth: 1) }
                    }
                    if let style = product.style?.trimmed.nilIfEmpty {
                        Text(style.uppercased())
                            .font(.manrope(9))
                            .foregroundStyle(Color(hex: 0x99A1AF))
                            .padding(.vertical, 2)
                    }
                }
                .padding(.bottom, 12)
                Text(product.displayTitle)
                    .font(.gilda(20))
                    .lineSpacing(4)
                    .foregroundStyle(Color(hex: 0x101828))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color(hex: 0x343E4B)
                .frame(width: 96, height: 96)
                .overlay {
                    if let active {
                        ProtectedImageView(url: active, contentMode: .scaleAspectFit, watermark: true)
                    }
                }
                .clipped()
        }
    }

    private var panelQuantity: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelLabel("Quantity", size: 10)
            HStack(spacing: 20) {
                stepButton("-", label: "Fewer") { quantity = max(1, quantity - 1) }
                Text("\(quantity)")
                    .font(.cirka(20))
                    .foregroundStyle(Color(hex: 0x1E2939))
                    .frame(minWidth: 16)
                    .contentTransition(.numericText())
                stepButton("+", label: "More") { quantity = min(999, quantity + 1) }
            }
        }
    }

    private var panelNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelLabel("Customization needs", size: 10)
            TextEditor(text: $notes)
                .font(.manrope(14))
                .foregroundStyle(Color(hex: 0x364153))
                .scrollContentBackground(.hidden)
                .padding(15)
                .frame(height: 128)
                .background(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Describe your customization requirements...")
                            .font(.manrope(14))
                            .foregroundStyle(Color(hex: 0x99A1AF))
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xF3F4F6), lineWidth: 1) }
        }
    }

    private func panelLabel(_ text: String, size: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.manrope(size, weight: .bold))
            .kerning(size * 0.1)
            .foregroundStyle(Color(hex: 0x99A1AF))
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.manrope(18))
                .foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(Color(hex: 0xF9FAFB), in: Circle())
                .overlay { Circle().stroke(Color(hex: 0xE5E7EB), lineWidth: 1) }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func show(_ product: Product?) {
        viewing = product
        activeIndex = 0
    }

    /// Back to the Catalogue when this page was opened for a product;
    /// otherwise back to the selection.
    private func backFromDetail() {
        if productID != nil {
            store.pop()
        } else {
            show(nil)
        }
    }

    private func remove(_ id: String) {
        products.removeAll { $0.id == id }
        store.removeSelection(id)
    }

    private func load() async {
        let selected = store.selectedProductIDs
        var ids = selected
        if let productID, !ids.contains(productID) { ids.append(productID) }
        guard !ids.isEmpty else {
            loading = false
            return
        }

        var found = ids.compactMap { store.productCache[$0] }
        if found.count != ids.count {
            if let fetched = try? await EmployeeAPI.fetchProducts(ids: ids) {
                found = fetched
                store.cache(fetched)
            }
        }
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        products = selected.compactMap { byID[$0] }
        if let productID, let product = byID[productID] {
            show(product)
        }
        loading = false
    }

    private func submit(_ product: Product) async {
        guard !submitting else { return }
        submitting = true
        defer { submitting = false }
        do {
            _ = try await JewelAPI.createRetailerOrder(productID: product.id, quantity: quantity, notes: notes)
            store.removeSelection(product.id)
            sent = .single(product.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitSelection() async {
        guard !submitting, !products.isEmpty else { return }
        submitting = true
        defer { submitting = false }
        do {
            _ = try await JewelAPI.createOrders(productIDs: products.map(\.id))
            store.clearSelection()
            sent = .bulk
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Two seconds after a single request the page shows what is left of the
    /// selection; four seconds after the whole selection, Home.
    private func finishSending() async {
        guard let sent else { return }
        #if DEBUG
        if holdsSent { return }
        #endif
        switch sent {
        case .single(let id):
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.sent = nil
            panelOpen = false
            show(nil)
            products.removeAll { $0.id == id }
        case .bulk:
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            store.goHome()
        }
    }

    private func rawGrams(_ value: Double?) -> String {
        guard let value, value != 0, value.isFinite else { return "—" }
        if value.rounded() == value, abs(value) < 1e15 { return "\(Int(value))g" }
        return "\(value)g"
    }
}

// MARK: - Pieces

/// A product on a pale panel with its name on a bar beneath.
private struct SelectionCard: View {
    let product: Product
    let imagePadding: CGFloat
    let captionSize: CGFloat
    let captionPadding: CGFloat
    var bordered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Color(hex: 0xF5F6F8)
                    .aspectRatio(4.0 / 3.5, contentMode: .fit)
                    .overlay {
                        if let url = product.reviewCardImageURL {
                            ProtectedImageView(url: url, contentMode: .scaleAspectFit, watermark: true, multiply: true)
                                .padding(imagePadding)
                        } else {
                            Text("No Image")
                                .font(.cirka(14))
                                .foregroundStyle(Color(hex: 0x99A1AF))
                        }
                    }
                    .clipped()

                Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.trimmed.nilIfEmpty ?? "Jewellery")
                    .font(.cirka(captionSize))
                    .kerning(captionSize * 0.025)
                    .foregroundStyle(Color(hex: 0x1E2939))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, captionPadding)
                    .background(Color(hex: 0xFAFAFA))
                    .overlay(alignment: .top) { Rectangle().fill(.white).frame(height: 1) }
            }
            .background(Color.white)
            .overlay {
                if bordered { Rectangle().stroke(Color(hex: 0xF3F4F6), lineWidth: 1) }
            }
            .shadow(color: .black.opacity(bordered ? 0.1 : 0), radius: 1.5, y: 1)
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
    }
}

/// `animate-spin` on a ring with its top edge missing.
private struct Spinner: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(.black, lineWidth: 2)
            .rotationEffect(.degrees((spinning ? 360 : 0) - 45))
            .frame(width: 32, height: 32)
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
            }
            .accessibilityLabel("Loading")
    }
}

/// "Request Sent Successfully!" (§4.5).
struct RequestSentView: View {
    let onReturn: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color(hex: 0xD0FAE5).shadow(.inner(color: .black.opacity(0.05), radius: 2, y: 2)))
                .frame(width: 96, height: 96)
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: 40, y: 12))
                        path.addLine(to: CGPoint(x: 18, y: 34))
                        path.addLine(to: CGPoint(x: 8, y: 24))
                    }
                    .stroke(Color(hex: 0x10B981), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .frame(width: 48, height: 48)
                }
                .padding(.bottom, 24)

            // Gilda has one weight; the web's heavy title is a drawn-on bold.
            ZStack {
                title
                title.offset(x: 0.7).accessibilityHidden(true)
            }
            .padding(.bottom, 8)

            Text("Your production requests have been forwarded to the respective wholesalers. You can track them in your Orders tab.")
                .font(.manrope(15))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 448)
                .padding(.bottom, 32)

            Button(action: onReturn) {
                Text("Return to Dashboard")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(.black, in: .rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 10)
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : Motion.fadeInUpOffset)
        .onAppear {
            withAnimation(Motion.fadeInUp) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var title: some View {
        Text("Request Sent Successfully!")
            .font(.gilda(32))
            .kerning(-0.8)
            .foregroundStyle(Color(hex: 0x111827))
            .multilineTextAlignment(.center)
    }
}

extension Product {
    var displayTitle: String {
        title?.trimmed.nilIfEmpty ?? jewelleryType?.trimmed.nilIfEmpty?.capitalized ?? "Untitled"
    }

    var displayCategory: String? {
        category?.trimmed.nilIfEmpty ?? jewelleryType?.trimmed.nilIfEmpty
    }
}
