import SwiftUI

/// The employee view's home (`EmployeeHomeClient.jsx` +
/// `DesignerCollectionSection.jsx`): a full-height hero on the store's theme
/// artwork — logo, name, and the "select view mode" card — then up to six of
/// the store's own designs, in the same per-person order as the web.
///
/// No title bar: the hero starts at the very top, as on the web.
struct EmployeeHomeView: View {
    @Environment(EmployeeStore.self) private var store
    let onOpenCatalogue: () -> Void

    @State private var designs: [RetailerDesign] = []
    @State private var selectedDesign: RetailerDesign?
    @State private var showCanvas = false
    @State private var showAllDesigns = false
    @State private var appeared = false


    var body: some View {
        if let session = store.session {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        hero(session, geo: geo)
                        DesignerCollectionSection(
                            designs: designs,
                            width: geo.size.width,
                            tallImage: CloudinaryArt.collectionImages[WebShuffle.imageIndex(for: session.seedID)],
                            onSelect: { design in
                                withAnimation(.easeOut(duration: 0.25)) { selectedDesign = design }
                            },
                            onViewAll: { showAllDesigns = true }
                        )
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .background(Color.white)
            }
            .overlay {
                if let design = selectedDesign {
                    EmployeeDesignDetail(design: design, theme: session.theme) {
                        withAnimation(.easeOut(duration: 0.2)) { selectedDesign = nil }
                    }
                    .transition(.opacity)
                }
            }
            .task(id: session.retailerID) { await loadDesigns(session) }
            .fullScreenCover(isPresented: $showCanvas) {
                EmployeePlaygroundPlaceholder { showCanvas = false }
            }
            .fullScreenCover(isPresented: $showAllDesigns) {
                EmployeeDesignsView(onClose: { showAllDesigns = false })
                    .environment(store)
            }
        }
    }

    // MARK: - Hero

    private func hero(_ session: EmployeeSession, geo: GeometryProxy) -> some View {
        let width = geo.size.width
        let medium = width >= 768
        let viewport = geo.size.height + geo.safeAreaInsets.top
        // `padding-top: clamp(100px, 15vh, 220px)`, measured below the status bar.
        let topPadding = geo.safeAreaInsets.top + cssClamp(100, 0.15, 220, width: geo.size.height)

        return VStack(spacing: 0) {
            logo(session, size: medium ? 96 : 80)
                .padding(.bottom, 16)

            let nameSize: CGFloat = medium ? 54 : 42
            Text(session.storeName)
                .font(.gilda(nameSize))
                .lineSpacing(nameSize * 0.25)
                .foregroundStyle(Color(hex: 0x2C1F18))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            let subSize: CGFloat = medium ? 15 : 13
            Text("Discover designs selected with precision, blending craftsmanship and ethnic style")
                .font(.manrope(subSize))
                .lineSpacing(subSize * 0.625)
                .foregroundStyle(Color(hex: 0x4A3B32))
                .multilineTextAlignment(.center)
                .frame(maxWidth: medium ? 448 : 320)
                .padding(.bottom, 24)

            ViewModeCard(
                width: width,
                onCatalog: onOpenCatalogue,
                onCanvas: { showCanvas = true }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, topPadding)
        .opacity(appeared ? 1 : 0)
        // A retailer also gets the web's 8pt slide (its banner's keyframes
        // override the plain fade).
        .offset(y: appeared || !session.isRetailer ? 0 : -8)
        .frame(maxWidth: .infinity, minHeight: viewport, alignment: .top)
        .background {
            CachedImage(url: session.theme.heroBackground)
                .allowsHitTesting(false)
        }
        .clipped()
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    private func logo(_ session: EmployeeSession, size: CGFloat) -> some View {
        CachedImage(url: session.storeLogoURL ?? CloudinaryArt.jewelLogo)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(Circle())
            .overlay { Circle().stroke(Color(hex: 0xF3F4F6), lineWidth: 1) }
            .shadow(color: .black.opacity(0.1), radius: 3, y: 4)
            .accessibilityLabel("\(session.storeName) Logo")
    }

    // MARK: - Data

    private func loadDesigns(_ session: EmployeeSession) async {
        #if DEBUG
        if let peekDesigns = store.peekDesigns {
            designs = WebShuffle.shuffled(peekDesigns, seedID: session.seedID)
            return
        }
        #endif
        guard let fetched = try? await EmployeeAPI.fetchDesigns(retailerID: session.retailerID) else { return }
        designs = WebShuffle.shuffled(fetched, seedID: session.seedID)
    }
}

// MARK: - "Select view mode" card

private struct ViewModeCard: View {
    let width: CGFloat
    let onCatalog: () -> Void
    let onCanvas: () -> Void

    /// `w-[85vw]`, capped per breakpoint.
    private var side: CGFloat {
        let cap: CGFloat = width >= 1280 ? 440 : width >= 1024 ? 380 : width >= 768 ? 320 : 280
        return min(width * 0.85, cap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let titleSize = cssClamp(20, 0.05, 26, width: width)
            Text("SELECT VIEW MODE")
                .font(.gilda(titleSize))
                .kerning(titleSize * 0.05)
                .lineSpacing(titleSize * 0.2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onCatalog) {
                    Text("CATALOG")
                        .font(.manrope(13, weight: .bold))
                        .kerning(1.3)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 4)
                }
                .buttonStyle(PressScaleStyle(scale: 1.02))

                Button(action: onCanvas) {
                    Text("INFINITE CANVAS")
                        .font(.manrope(12, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay { Rectangle().stroke(.white.opacity(0.4), lineWidth: 1) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 1.01))
            }
        }
        .padding(32)
        .frame(width: side, height: side)
        .background {
            CachedImage(url: CloudinaryArt.viewModeCard)
        }
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 25, y: 25)
    }
}

// MARK: - Designer collection

/// Nothing at all when the store has no designs — the web returns null.
struct DesignerCollectionSection: View {
    let designs: [RetailerDesign]
    let width: CGFloat
    let tallImage: URL?
    let onSelect: (RetailerDesign) -> Void
    let onViewAll: () -> Void

    private var medium: Bool { width >= 768 }
    private var large: Bool { width >= 1024 }

    var body: some View {
        if !designs.isEmpty {
            VStack(spacing: 0) {
                header
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, large ? 48 : medium ? 32 : 16)
                    .padding(.bottom, 48)

                HStack(alignment: .top, spacing: 32) {
                    grid
                    if large {
                        tall
                    }
                }

                Button(action: onViewAll) {
                    Text("VIEW ALL")
                        .font(.manrope(11, weight: .semibold))
                        .kerning(2.75)
                        .foregroundStyle(Color(hex: 0x6A7282))
                        .underline(color: Color(hex: 0xD1D5DC))
                        .baselineOffset(0)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 48)
            }
            .frame(maxWidth: 1280)
            .padding(.horizontal, medium ? 32 : 16)
            .padding(.top, 64)
            .padding(.bottom, 160)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: medium ? 12 : 8) {
            let heading: CGFloat = large ? 46 : medium ? 40 : 32
            Text("Designer collection")
                .font(.gilda(heading))
                .lineSpacing(heading * 0.25)
                .foregroundStyle(Color(hex: 0x111827))
            let sub: CGFloat = large ? 18 : medium ? 16 : 14
            // Copied exactly, including the web's "the our own".
            Text("Crafted in house with the taste of the our own")
                .font(.manrope(sub, weight: .light))
                .lineSpacing(sub * 0.5)
                .foregroundStyle(Color(hex: 0x99A1AF))
        }
    }

    private var grid: some View {
        let columns = width >= 640 ? 2 : 1
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: columns),
            spacing: medium ? 64 : 48
        ) {
            ForEach(designs) { design in
                DesignCard(design: design) { onSelect(design) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Wide screens only: a tall featured image, 28% of the row.
    private var tall: some View {
        CachedImage(url: tallImage)
            .overlay { Color.black.opacity(0.05) }
            .frame(width: (min(width, 1280) - 64) * 0.28)
            .frame(maxHeight: .infinity)
            .clipped()
            .shadow(color: .black.opacity(0.25), radius: 25, y: 25)
            .accessibilityLabel("Featured collection")
    }
}

private struct DesignCard: View {
    let design: RetailerDesign
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Color(hex: 0xF8F8F8)
                    .aspectRatio(5.0 / 4.0, contentMode: .fit)
                    .overlay {
                        ProtectedImageView(url: design.imageLink, contentMode: .scaleAspectFit,
                                           watermark: true, multiply: true)
                    }
                    .clipped()
                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)

                Text(design.cardTitle)
                    .font(.cirka(13))
                    .kerning(0.325)
                    .foregroundStyle(Color(hex: 0x364153))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
            }
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel(design.cardTitle)
    }
}

// MARK: - Not yet ported

/// The playground (infinite canvas) is its own large piece; until it lands,
/// its button opens this rather than doing nothing.
struct EmployeePlaygroundPlaceholder: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0xFAFAFA).ignoresSafeArea()
            ComingSoonView(title: "Infinite Canvas", symbol: "square.grid.3x3",
                           message: "Browse your store's picks on an endless canvas. Coming in the next update.")
            GlassCircleButton(systemImage: "arrow.left", label: "Go back", action: onClose)
                .padding(24)
        }
    }
}
