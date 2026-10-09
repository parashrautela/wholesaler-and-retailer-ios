import SwiftUI

/// The Infinite Canvas (`/dashboard/employee/playground`, `InfinityCanvas.jsx`):
/// the store's shortlist laid out as an endless board of cards, staggered like
/// a masonry wall, that can be dragged in any direction and never runs out —
/// cards leaving one edge come back on the other. It drifts slowly on its own,
/// and a flick carries on with momentum.
///
/// Tap a card to open it. Hold it for half a second to add it to the selection;
/// the tray at the bottom then offers Next, which opens the selection page.
struct EmployeeInfiniteCanvas: View {
    @Environment(\.employeeAppearance) private var appearance
    @Environment(EmployeeStore.self) private var store
    let onClose: () -> Void

    @State private var products: [Product] = []
    @State private var loaded = false

    /// Where the board has been moved to, and the live drag on top of it.
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero
    @State private var velocity: CGSize = .zero
    @State private var dragging = false
    @State private var lastTick: Date?

    // The web's 12 × 8 wall at 260 × 360, scaled to a phone.
    private let columns = 8
    private let rows = 8
    @State private var viewport: CGSize = .zero
    private var tileSize: CGSize { appearance.enabled && viewport.width >= 641 ? CGSize(width: 260, height: 360) : CGSize(width: 152, height: 212) }
    private let gap: CGFloat = 14
    private var cell: CGSize { CGSize(width: tileSize.width + gap, height: tileSize.height + gap) }
    private var board: CGSize { CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height) }

    #if DEBUG
    /// Peeks only: start already moved, so a screenshot shows the wrap.
    var peekOffset: CGSize?
    var peekDisableMotion = false
    var peekSwitchToCatalogue: (() -> Void)? = nil
    #endif

    var body: some View {
        ZStack {
            (appearance.enabled ? appearance.background : Color(hex: 0xFCFCFC)).ignoresSafeArea()

            if !loaded {
                ProgressView()
            } else if products.isEmpty {
                ContentUnavailableView(
                    "Nothing on the canvas yet",
                    systemImage: "square.grid.3x3",
                    description: Text("Designs your store shortlists will appear here.")
                )
            } else {
                canvas
            }

            // Softens cards sliding under the header and the tray.
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: (appearance.enabled ? appearance.background : Color(hex: 0xFCFCFC)), location: 0),
                                       .init(color: (appearance.enabled ? appearance.background : Color(hex: 0xFCFCFC)).opacity(0.85), location: 0.55),
                                       .init(color: (appearance.enabled ? appearance.background : Color(hex: 0xFCFCFC)).opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [(appearance.enabled ? appearance.background : Color(hex: 0xFCFCFC)).opacity(0), (appearance.enabled ? appearance.background : Color(hex: 0xFCFCFC)).opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            overlays
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { viewport = $0 }
        .task { await load() }
    }

    // MARK: - Board

    private var canvas: some View {
        TimelineView(.animation) { timeline in
            let current = CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
            ZStack(alignment: .topLeading) {
                ForEach(0..<(columns * rows), id: \.self) { index in
                    let product = products[index % products.count]
                    CanvasTile(
                        product: product,
                        size: tileSize,
                        isSelected: store.selectedProductIDs.contains(product.id),
                        onOpen: { open(product) },
                        onHold: { hold(product) }
                    )
                    .position(position(of: index, at: current))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .onChange(of: timeline.date) { _, now in tick(now) }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    dragging = true
                    velocity = .zero
                    drag = value.translation
                }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                    drag = .zero
                    dragging = false
                    // Carry on in the direction of the flick.
                    let predicted = value.predictedEndTranslation
                    velocity = CGSize(
                        width: (predicted.width - value.translation.width) * 2.2,
                        height: (predicted.height - value.translation.height) * 2.2
                    )
                }
        )
    }

    /// Each card's place on the endless board: its column and row, a masonry
    /// stagger by column, the board's movement, and a wrap so it reappears on
    /// the far side once it leaves.
    private func position(of index: Int, at offset: CGSize) -> CGPoint {
        let column = index % columns
        let row = index / columns
        let baseX = CGFloat(column) * cell.width
        let baseY = CGFloat(row) * cell.height + CGFloat(column % 4) * 40
        let x = wrap(baseX + offset.width, span: board.width, lead: cell.width)
        let y = wrap(baseY + offset.height, span: board.height, lead: cell.height)
        return CGPoint(x: x + tileSize.width / 2, y: y + tileSize.height / 2)
    }

    private func wrap(_ value: CGFloat, span: CGFloat, lead: CGFloat) -> CGFloat {
        let shifted = (value + lead).truncatingRemainder(dividingBy: span)
        return (shifted < 0 ? shifted + span : shifted) - lead
    }

    /// Once a frame: momentum that fades, and when nothing is happening, a
    /// slow wander that changes direction over time — as on the web.
    private func tick(_ now: Date) {
        defer { lastTick = now }
        #if DEBUG
        if peekDisableMotion { velocity = .zero; return }
        #endif
        guard let last = lastTick, !dragging else { return }
        let dt = min(now.timeIntervalSince(last), 1.0 / 20)

        let t = now.timeIntervalSinceReferenceDate
        let drift = CGSize(width: cos(t * 0.2) * 7, height: sin(t * 0.14) * 7)

        offset.width += (velocity.width + drift.width) * dt
        offset.height += (velocity.height + drift.height) * dt

        let fade = pow(0.04, dt)
        velocity = CGSize(width: velocity.width * fade, height: velocity.height * fade)
        if abs(velocity.width) < 1, abs(velocity.height) < 1 { velocity = .zero }
    }

    // MARK: - Overlays

    private var overlays: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    GlassCircleButton(systemImage: "arrow.left", size: 44, iconSize: 20,
                                      label: "Go back", action: onClose)
                    Spacer()
                    GlassCircleButton(systemImage: "square.grid.2x2", size: 44, iconSize: 20,
                                      label: "Switch to Catalogue") {
                        onClose()
                        store.tabRequest = .catalogue
                        #if DEBUG
                        peekSwitchToCatalogue?()
                        #endif
                    }
                }

                if let name = store.session?.storeName {
                    HStack(spacing: 8) {
                        Circle().fill(Color.gray.opacity(0.5)).frame(width: 5, height: 5)
                        Text(name)
                            .font(appearance.enabled ? appearance.body(16, weight: .medium) : .gilda(16))
                            .kerning(1.5)
                            .foregroundStyle(appearance.ink(Color(hex: 0x1F2937)))
                            .lineLimit(1)
                        Circle().fill(Color.gray.opacity(0.5)).frame(width: 5, height: 5)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.6), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                    .padding(.horizontal, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        let selected = store.selectedProductIDs.compactMap { id in products.first { $0.id == id } }
        if selected.isEmpty {
            Text(products.isEmpty ? " " : "Drag to explore · Hold a design to select it")
                .font(appearance.body(12, weight: .semibold))
                .foregroundStyle(appearance.ink(Color(hex: 0x374151)))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.6), lineWidth: 1) }
                .opacity(products.isEmpty ? 0 : 1)
        } else {
            HStack(spacing: 10) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(selected) { product in
                            ZStack(alignment: .topTrailing) {
                                ZStack {
                                    Color.white
                                    if let url = product.catalogueImageURL {
                                        ProtectedImageView(url: url, contentMode: .scaleAspectFill, multiply: !appearance.dark)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                Button { store.removeSelection(product.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white, Color.black.opacity(0.55))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 10, y: -10)
                                .accessibilityLabel("Remove \(product.title ?? "design")")
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, 4)
                }
                .scrollIndicators(.hidden)

                Button {
                    onClose()
                    store.push(.review(productID: nil))
                } label: {
                    Text("Next (\(selected.count))")
                        .font(appearance.body(14, weight: .bold))
                        .foregroundStyle(appearance.enabled ? appearance.onAccent : .white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: appearance.enabled ? [appearance.primaryStart, appearance.primaryEnd] : [Color(hex: 0x2A2A2A), Color(hex: 0x111111)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: appearance.enabled ? appearance.controlRadius : 12)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(appearance.enabled ? AnyShapeStyle(appearance.surface.opacity(0.96)) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 20))
            .overlay { RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 20).stroke(appearance.enabled ? appearance.border : .white.opacity(0.6), lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func open(_ product: Product) {
        onClose()
        store.push(.review(productID: product.id))
    }

    private func hold(_ product: Product) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            _ = store.toggleSelection(product.id)
        }
    }

    private func load() async {
        #if DEBUG
        if let peekOffset { offset = peekOffset }
        if let peek = store.peekProducts {
            products = peek.filter { $0.catalogueImageURL != nil }
            loaded = true
            return
        }
        #endif
        // Centred on the board, as the web starts.
        offset = CGSize(width: -board.width / 3, height: -board.height / 3)
        guard let session = store.session else { loaded = true; return }
        if let fetched = try? await EmployeeAPI.fetchSelectedProducts(retailerID: session.retailerID) {
            products = fetched.filter { $0.catalogueImageURL != nil }
            store.cache(fetched)
        }
        loaded = true
    }
}

// MARK: - Tile

/// One card on the board: the photo and its name, with a blue frame when it
/// is in the selection.
private struct CanvasTile: View {
    @Environment(\.employeeAppearance) private var appearance
    let product: Product
    let size: CGSize
    let isSelected: Bool
    let onOpen: () -> Void
    let onHold: () -> Void

    @State private var pressing = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                appearance.quiet(Color(hex: 0xF9FAFB))
                if let url = product.catalogueImageURL {
                    ProtectedImageView(url: url, contentMode: .scaleAspectFill, multiply: !appearance.dark)
                        .padding(10)
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()

            Text(product.title?.trimmed.nilIfEmpty ?? product.jewelleryType?.capitalized ?? "Jewellery")
                .font(appearance.enabled ? appearance.body(13, weight: .medium) : .gilda(13))
                .foregroundStyle(appearance.ink(Color(hex: 0x1F2937)))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 8)
                .background(appearance.panel())
                .overlay(alignment: .top) { Rectangle().fill(appearance.line(Color(hex: 0xF3F4F6))).frame(height: 1) }
        }
        .frame(width: size.width, height: size.height)
        .background(appearance.panel())
        .clipShape(RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 6))
        .overlay {
            RoundedRectangle(cornerRadius: appearance.enabled ? appearance.cardRadius : 6)
                .stroke(isSelected ? (appearance.enabled ? appearance.accent : Color(hex: 0x007AFF)) : Color(hex: 0xF3F4F6), lineWidth: isSelected ? 3 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.15 : 0.06), radius: isSelected ? 10 : 4, y: 2)
        .scaleEffect(pressing ? 0.95 : isSelected ? 0.97 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: pressing)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) {
            pressing = false
            onHold()
        } onPressingChanged: { pressing = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: isSelected ? "Remove from selection" : "Add to selection", onHold)
    }
}
