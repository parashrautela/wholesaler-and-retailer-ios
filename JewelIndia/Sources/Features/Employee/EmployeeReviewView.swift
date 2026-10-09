import SwiftUI

/// `/dashboard/employee/playground/review` (`SelectionReviewClient.jsx`).
///
/// Opened with a product, it is that product's page: pictures, specs, and
/// "Send Request", with the rest of the long-pressed selection underneath.
/// Opened without one — or once a request from that page has gone — it is
/// the selection itself, which can be requested in one go.
struct EmployeeReviewView: View {
    @Environment(\.employeeAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @FocusState private var requestNotesFocused: Bool
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
                    .employeeAppearanceChrome()
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
                            .font(appearance.cirka(18))
                            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6A7282)))
                        Button { store.pop() } label: {
                            Text("Return to selection")
                                .font(appearance.body(14))
                                .foregroundStyle(appearance.enabled ? appearance.accent : Color(hex: 0x155DFC))
                                .underline()
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
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
        .background(appearance.panel())
    }

    private var pageHeader: some View {
        Text("Selected Items")
            .font(appearance.display(md ? 38 : 30))
            .kerning(md ? 0.95 : 0.75)
            .foregroundStyle(appearance.ink(Color(hex: 0x1A1A1A)))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 56)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button { if viewing != nil { show(nil) } else { store.pop() } } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6A7282)))
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [Color(hex: 0xF9FAFB), Color(hex: 0xE5E7EB)],
                                           startPoint: .top, endPoint: .bottom),
                            in: Circle()
                        )
                        .overlay { Circle().stroke(appearance.line(Color(hex: 0xD1D5DC)), lineWidth: 1) }
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
                                .font(appearance.body(13))
                                .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6A7282)))
                                .frame(width: 44, height: 44)
                                .background(appearance.panel().opacity(0.9), in: Circle())
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
                        .font(appearance.body(14, weight: .semibold))
                        .kerning(2.8)
                    if !submitting {
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .medium))
                    }
                }
                .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .background(appearance.enabled ? appearance.accent : .black)
                .clipShape(.rect(cornerRadius: appearance.enabled ? appearance.controlRadius : 0))
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
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Product page (§4.3)

    private func detail(_ product: Product) -> some View {
        EmployeeDetailLayout(onClose: backFromDetail) { _ in
            images(product).padding(12)
        } details: { contentWidth in
            VStack(alignment: .leading, spacing: 24) {
                detailHeader(product)
                specs(product, contentWidth: contentWidth)
                moreYouMightLike(excluding: product, contentWidth: contentWidth)
            }
        }
        .background { ThemedDetailBackground(theme: store.session?.theme ?? .indian) }
    }

    private func detailHeader(_ product: Product) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let category = product.displayCategory {
                    let size = cssClamp(12, 0.018, 16, width: width)
                    Text(category.uppercased())
                        .font(appearance.body(size, weight: .bold))
                        .kerning(size * 0.2)
                        .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6E6E6E)))
                }
                if let style = product.style?.trimmed.nilIfEmpty {
                    let chip = cssClamp(10, 0.015, 12, width: width)
                    Text(style)
                        .font(appearance.body(chip, weight: .medium))
                        .kerning(chip * 0.02)
                        .foregroundStyle(appearance.ink(Color(hex: 0x515151)))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(appearance.line(Color(hex: 0xA8A8A8)), lineWidth: 1)
                        }
                }
            }
            let titleSize = cssClamp(24, 0.04, 38, width: width)
            Text(product.displayTitle)
                .font(appearance.display(titleSize))
                .kerning(titleSize * 0.025)
                .lineSpacing(titleSize * 0.2)
                .foregroundStyle(appearance.ink(.black))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .task(id: product.id) {
            await LikeBook.shared.load()
            StoreActivity.log(.designViewed, productID: product.id)
        }
    }

    private func images(_ product: Product) -> some View {
        let urls = product.reviewImages(.detail)
        let thumbs = product.reviewImages(.card)
        let active = urls.indices.contains(activeIndex) ? urls[activeIndex] : urls.first

        return VStack(spacing: 12) {
            Button { if active != nil { viewerOpen = true } } label: {
                appearance.quiet(Color(hex: 0xF5F5F5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if let active {
                            ProtectedImageView(url: active, contentMode: .scaleAspectFit,
                                               watermark: true, multiply: !appearance.dark)
                        } else {
                            Text("No image")
                                .font(appearance.body(14))
                                .foregroundStyle(appearance.muted)
                        }
                    }
                    .clipShape(.rect(cornerRadius: appearance.enabled ? appearance.cardRadius : 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 4)
                            .stroke(appearance.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View image of \(product.displayTitle)")
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    GlassLikeButton(productID: product.id, size: 48)
                    GlassCircleButton(systemImage: "arrow.up.left.and.arrow.down.right",
                                      size: 48, iconSize: 18, weight: .semibold,
                                      label: "Zoom image") { if active != nil { viewerOpen = true } }
                }
                .padding(12)
            }

            if thumbs.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(thumbs.enumerated()), id: \.offset) { offset, url in
                            Button { activeIndex = offset } label: {
                                ProtectedImageView(url: url, contentMode: .scaleAspectFit,
                                                   watermark: true, multiply: !appearance.dark)
                                    .frame(width: 56, height: 56)
                                    .background(appearance.panel())
                                    .clipShape(.rect(cornerRadius: appearance.enabled ? appearance.cardRadius : 4))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 4)
                                            .stroke(offset == activeIndex ? appearance.accent : appearance.border,
                                                    lineWidth: offset == activeIndex ? 2 : 1)
                                    }
                                    .opacity(offset == activeIndex ? 1 : 0.6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Picture \(offset + 1)")
                            .accessibilityAddTraits(offset == activeIndex ? .isSelected : [])
                        }
                    }
                    .padding(2)
                }
                .scrollIndicators(.visible)
                .frame(height: 64)
                .accessibilityIdentifier("employee-detail-thumbnails")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func specs(_ product: Product, contentWidth: CGFloat) -> some View {
        let columnSize = (contentWidth - 24) / 2

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
                    Text(appearance.enabled ? "Send Request" : "SEND REQUEST")
                        .font(appearance.body(16, weight: .bold))
                        .kerning(appearance.enabled ? 0 : 1.6)
                        .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            appearance.primary,
                            in: .rect(cornerRadius: appearance.enabled ? appearance.controlRadius : 4)
                        )
                        .overlay { RoundedRectangle(cornerRadius: appearance.enabled ? appearance.controlRadius : 4).stroke(appearance.enabled ? Color.clear : .black, lineWidth: 1) }
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                }
                .buttonStyle(PressScaleStyle(scale: 0.99))

                Button { store.openChat(productID: product.id) } label: {
                    Text("Chat with us")
                        .font(appearance.body(16, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(appearance.ink(.black))
                        .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }

        if contentWidth >= 540 && !dynamicTypeSize.isAccessibilitySize {
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
    private func moreYouMightLike(excluding current: Product, contentWidth: CGFloat) -> some View {
        let others = products.filter { $0.id != current.id }
        if !others.isEmpty {
            VStack(spacing: 32) {
                Text("More, you might like from us")
                    .font(appearance.display(28))
                    .foregroundStyle(appearance.ink(Color(hex: 0x1E2939)))
                    .multilineTextAlignment(.center)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: contentWidth >= 540 ? 2 : 1),
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
            .padding(.top, 24)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(hex: 0xE5E7EB).opacity(0.5)).frame(height: 1)
            }
            .padding(.top, 24)
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
                        .font(appearance.display(14))
                        .foregroundStyle(appearance.ink(Color(hex: 0x1E2939)))
                    Spacer()
                    if requestNotesFocused {
                        Button { Task { await submit(product) } } label: {
                            Text(submitting ? "SENDING…" : "SEND")
                                .font(appearance.body(11, weight: .bold))
                                .kerning(0.8)
                                .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                                .frame(minWidth: 56, minHeight: 44)
                                .background(appearance.primary, in: RoundedRectangle(cornerRadius: appearance.controlRadius))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(submitting)
                        .accessibilityLabel("Send Request")
                        .accessibilityIdentifier("employee-review-keyboard-submit")
                    }
                    Button { panelOpen = false } label: {
                        Text("✕")
                            .font(appearance.body(16))
                            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x99A1AF)))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .overlay(alignment: .bottom) { Rectangle().fill(appearance.line(Color(hex: 0xF3F4F6))).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        panelSnippet(product)
                        panelQuantity
                        panelNotes
                    }
                    .padding(32)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("employee-review-request-body")

                Button { Task { await submit(product) } } label: {
                    Text(submitting ? "SENDING..." : "SEND REQUEST")
                        .font(appearance.body(12, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            appearance.primary
                        )
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 16)
                }
                .buttonStyle(PressScaleStyle(scale: 0.99))
                .disabled(submitting)
                .accessibilityIdentifier("employee-review-request-submit")
                .opacity(submitting ? 0.7 : 1)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 420, maxHeight: .infinity)
            .background(appearance.panel().ignoresSafeArea())
            .shadow(color: .black.opacity(0.25), radius: 25, y: 25)
            .transition(.move(edge: .trailing))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button { requestNotesFocused = false } label: {
                        Text("Done")
                            .font(appearance.body(14, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("employee-review-keyboard-done")
                    Spacer()
                }
            }
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
                            .font(appearance.body(9))
                            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6A7282)))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(appearance.line(Color(hex: 0xE5E7EB)), lineWidth: 1) }
                    }
                    if let style = product.style?.trimmed.nilIfEmpty {
                        Text(style.uppercased())
                            .font(appearance.body(9))
                            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x99A1AF)))
                            .padding(.vertical, 2)
                    }
                }
                .padding(.bottom, 12)
                Text(product.displayTitle)
                    .font(appearance.display(20))
                    .lineSpacing(4)
                    .foregroundStyle(appearance.ink(Color(hex: 0x101828)))
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
                    .font(appearance.cirka(20))
                    .foregroundStyle(appearance.ink(Color(hex: 0x1E2939)))
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
                .focused($requestNotesFocused)
                .font(appearance.body(14))
                .foregroundStyle(appearance.ink(Color(hex: 0x364153)))
                .scrollContentBackground(.hidden)
                .padding(15)
                .frame(height: 128)
                .background(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Describe your customization requirements...")
                            .font(appearance.body(14))
                            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x99A1AF)))
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }
                .background(appearance.quiet(Color(hex: 0xF9FAFB)), in: .rect(cornerRadius: appearance.enabled ? appearance.controlRadius : 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(appearance.line(Color(hex: 0xF3F4F6)), lineWidth: 1) }
        }
    }

    private func panelLabel(_ text: String, size: CGFloat) -> some View {
        Text(text.uppercased())
            .font(appearance.body(size, weight: .bold))
            .kerning(size * 0.1)
            .foregroundStyle(appearance.secondaryInk(Color(hex: 0x99A1AF)))
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(appearance.body(18))
                .foregroundStyle(appearance.ink(.black))
                .frame(width: 44, height: 44)
                .background(appearance.quiet(Color(hex: 0xF9FAFB)), in: Circle())
                .overlay { Circle().stroke(appearance.line(Color(hex: 0xE5E7EB)), lineWidth: 1) }
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
            await store.refreshOrders()
            store.removeSelection(product.id)
            sent = .single(product.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitSelection() async {
        guard !submitting, !products.isEmpty else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-JewelEmployeeSimulateBulkRequestError") {
            errorMessage = "Unable to send request. Please try again."
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-JewelEmployeeSimulateBulkRequestSuccess") {
            store.clearSelection()
            sent = .bulk
            return
        }
        #endif
        submitting = true
        defer { submitting = false }
        do {
            _ = try await JewelAPI.createOrders(productIDs: products.map(\.id))
            await store.refreshOrders()
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
    @Environment(\.employeeAppearance) private var appearance
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
                            ProtectedImageView(url: url, contentMode: .scaleAspectFit, watermark: true, multiply: !appearance.dark)
                                .padding(imagePadding)
                        } else {
                            Text("No Image")
                                .font(appearance.cirka(14))
                                .foregroundStyle(appearance.secondaryInk(Color(hex: 0x99A1AF)))
                        }
                    }
                    .clipped()

                Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.trimmed.nilIfEmpty ?? "Jewellery")
                    .font(appearance.cirka(captionSize))
                    .kerning(captionSize * 0.025)
                    .foregroundStyle(appearance.ink(Color(hex: 0x1E2939)))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, captionPadding)
                    .background(appearance.quiet(Color(hex: 0xFAFAFA)))
                    .overlay(alignment: .top) { Rectangle().fill(.white).frame(height: 1) }
            }
            .background(appearance.panel())
            .overlay {
                if bordered { Rectangle().stroke(appearance.line(Color(hex: 0xF3F4F6)), lineWidth: 1) }
            }
            .shadow(color: .black.opacity(bordered ? 0.1 : 0), radius: 1.5, y: 1)
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
    }
}

/// `animate-spin` on a ring with its top edge missing.
private struct Spinner: View {
    @Environment(\.employeeAppearance) private var appearance
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(appearance.ink(.black), lineWidth: 2)
            .rotationEffect(.degrees((spinning ? 360 : 0) - 45))
            .frame(width: 44, height: 44)
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
            }
            .accessibilityLabel("Loading")
    }
}

/// "Request Sent Successfully!" (§4.5).
struct RequestSentView: View {
    @Environment(\.employeeAppearance) private var appearance
    let onReturn: () -> Void
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                messageContent.frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(appearance.panel())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : Motion.fadeInUpOffset)
        .onAppear {
            withAnimation(Motion.fadeInUp) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var messageContent: some View {
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
                .font(appearance.body(15))
                .lineSpacing(4)
                .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6B7280)))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 448)
                .padding(.bottom, 32)

            Button(action: onReturn) {
                Text("Return to Dashboard")
                    .font(appearance.body(14, weight: .bold))
                    .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .background(appearance.enabled ? appearance.accent : .black, in: .rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 10)
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var title: some View {
        Text("Request Sent Successfully!")
            .font(appearance.display(32))
            .kerning(-0.8)
            .foregroundStyle(appearance.ink(Color(hex: 0x111827)))
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
