import SwiftUI

/// The employee view's home (`EmployeeHomeClient.jsx` +
/// `DesignerCollectionSection.jsx`): a full-height hero on the store's theme
/// artwork — logo, name, and the "select view mode" card — then up to six of
/// the store's own designs, in the same per-person order as the web.
///
/// No title bar: the hero starts at the very top, as on the web.
struct EmployeeHomeView: View {
    @Environment(\.employeeAppearance) private var appearance
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
                        Group {
                            if appearance.creative { creativeHero(session, geo: geo) }
                            else if appearance.enabled { sarvamHero(session, geo: geo) }
                            else { hero(session, geo: geo) }
                        }
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
                .ignoresSafeArea(edges: appearance.enabled ? [] : .top)
                .background(appearance.panel())
            }
            .fullScreenCover(item: $selectedDesign) { design in
                EmployeeDesignDetail(design: design, theme: session.theme) { selectedDesign = nil }
                    .employeeAppearanceChrome()
            }
            .task(id: session.retailerID) { await loadDesigns(session) }
            .fullScreenCover(isPresented: $showCanvas) {
                EmployeeInfiniteCanvas { showCanvas = false }
                    .environment(store)
                    .employeeAppearanceChrome()
            }
            .fullScreenCover(isPresented: $showAllDesigns) {
                EmployeeDesignsView(onClose: { showAllDesigns = false })
                    .environment(store)
                    .employeeAppearanceChrome()
            }
        }
    }

    // MARK: - Creative employee directions

    @ViewBuilder private func creativeHero(_ session: EmployeeSession, geo: GeometryProxy) -> some View {
        switch appearance.style {
        case .jaipur: jaipurHero(session, geo: geo)
        case .aegean: aegeanHero(session, geo: geo)
        case .neelam: neelamHero(session, geo: geo)
        default: EmptyView()
        }
    }

    private func jaipurHero(_ session: EmployeeSession, geo: GeometryProxy) -> some View {
        let landscape = geo.size.width >= 900
        return VStack(spacing: 0) {
            HStack {
                Text("JAIPUR / THE COURTYARD").font(appearance.body(10, weight: .semibold)).kerning(2)
                Spacer()
                EmployeeStyleEmblem().frame(width: 44, height: 44)
            }
            .foregroundStyle(appearance.accent)
            .padding(.bottom, landscape ? 12 : 48)
            logo(session, size: landscape ? 42 : 58).padding(.bottom, landscape ? 12 : 24)
            Text("A tradition of\nbeautiful things.")
                .font(appearance.display(landscape ? 44 : (geo.size.width >= 768 ? 52 : 38)))
                .foregroundStyle(appearance.text).multilineTextAlignment(.center)
                .lineSpacing(4).padding(.bottom, landscape ? 12 : 18)
            Text(session.storeName)
                .font(appearance.body(14, weight: .semibold)).kerning(1.5)
                .foregroundStyle(appearance.accent).multilineTextAlignment(.center)
            EmployeeStyleMotif().frame(maxWidth: 260).padding(.vertical, landscape ? 12 : 24)
            Text("Discover the craft. Find the perfect piece.")
                .font(appearance.body(15)).foregroundStyle(appearance.muted)
                .multilineTextAlignment(.center).padding(.bottom, landscape ? 20 : 30)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sarvamActions }
                VStack(spacing: 12) { sarvamActions }
            }
            .padding(.bottom, landscape ? 20 : 30)
            heritageDesignRail(width: geo.size.width, landscape: landscape).padding(.bottom, landscape ? 20 : 30)
            HStack(spacing: 12) {
                Rectangle().frame(height: 1)
                Text("CRAFT • COLLECTION • CONNECTION").font(appearance.body(9, weight: .medium)).kerning(1.4).fixedSize()
                Rectangle().frame(height: 1)
            }.foregroundStyle(appearance.muted.opacity(0.65))
        }
        .padding(.horizontal, geo.size.width >= 641 ? 48 : 24)
        .padding(.vertical, landscape ? 24 : 32)
        .frame(maxWidth: .infinity)
        .background { EmployeeCreativeBackdrop() }
    }

    private func aegeanHero(_ session: EmployeeSession, geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .center) {
                logo(session, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.storeName).font(appearance.body(16, weight: .medium))
                    Text("THE AEGEAN GALLERY").font(appearance.body(9, weight: .medium)).kerning(2.4).foregroundStyle(appearance.accent)
                }
                Spacer()
                EmployeeStyleEmblem().frame(width: 68, height: 68)
            }
            EmployeeStyleMotif()
            if geo.size.width >= 900 {
                HStack(alignment: .center, spacing: 48) {
                    aegeanIntroduction.frame(maxWidth: .infinity, alignment: .leading)
                    heroDesign(height: 310).frame(maxWidth: .infinity)
                }
            } else {
                aegeanIntroduction
                heroDesign(height: 230)
            }
            HStack(spacing: 20) {
                Text("01 / EXPLORE").font(appearance.body(9, weight: .medium)).kerning(2)
                Rectangle().frame(height: 1)
                Text("02 / CURATE").font(appearance.body(9, weight: .medium)).kerning(2)
            }.foregroundStyle(appearance.muted)
        }
        .foregroundStyle(appearance.text)
        .padding(.horizontal, geo.size.width >= 641 ? 88 : 28)
        .padding(.vertical, 40)
        .background { EmployeeCreativeBackdrop() }
    }

    private var aegeanIntroduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("An eye for\nthe exceptional.")
                .font(appearance.display(48)).lineSpacing(2).kerning(0.3)
                .fixedSize(horizontal: false, vertical: true)
            Text("A considered collection.\nA new perspective on every piece.")
                .font(appearance.body(16)).lineSpacing(5).foregroundStyle(appearance.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sarvamActions }
                VStack(alignment: .leading, spacing: 12) { sarvamActions }
            }
        }
    }

    private func neelamHero(_ session: EmployeeSession, geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                logo(session, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEELAM ATELIER").font(appearance.body(10, weight: .medium)).kerning(2.5).foregroundStyle(appearance.accent)
                    Text(session.storeName).font(appearance.body(15, weight: .medium)).foregroundStyle(appearance.text)
                }
                Spacer()
                EmployeeStyleEmblem().frame(width: 64, height: 64)
            }
            Rectangle().fill(appearance.border).frame(height: 1)
            if geo.size.width >= 900 {
                HStack(alignment: .center, spacing: 48) {
                    atelierIntroduction.frame(maxWidth: .infinity, alignment: .leading)
                    heroDesign(height: 350).frame(maxWidth: .infinity)
                }
            } else {
                atelierIntroduction
                heroDesign(height: 290)
            }
            EmployeeStyleMotif()
            HStack {
                Text("DESIGNED TO BE DISCOVERED").font(appearance.body(9, weight: .medium)).kerning(1.8)
                Spacer()
                Text("YOUR COLLECTION ROOM").font(appearance.body(9, weight: .medium)).kerning(1.8)
            }.foregroundStyle(appearance.muted)
        }
        .padding(.horizontal, geo.size.width >= 641 ? 48 : 24)
        .padding(.vertical, 32)
        .background { EmployeeCreativeBackdrop() }
    }

    private var atelierIntroduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("For pieces\nwith presence.")
                .font(appearance.display(56)).kerning(-0.5).foregroundStyle(appearance.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Indian craftsmanship, viewed through a modern lens. Explore, select and connect with your wholesalers.")
                .font(appearance.body(15)).lineSpacing(5).foregroundStyle(appearance.muted)
                .frame(maxWidth: 440, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sarvamActions }
                VStack(alignment: .leading, spacing: 12) { sarvamActions }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder private func heritageDesignRail(width: CGFloat, landscape: Bool) -> some View {
        if !designs.isEmpty {
            VStack(spacing: 14) {
                Text("A GLIMPSE OF YOUR COLLECTION").font(appearance.body(9, weight: .medium)).kerning(1.8).foregroundStyle(appearance.accent)
                HStack(alignment: .top, spacing: width >= 641 ? 22 : 12) {
                    ForEach(Array(designs.prefix(3))) { design in
                        Button { selectedDesign = design } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    appearance.subtle
                                    ProtectedImageView(url: design.imageLink, contentMode: .scaleAspectFill, watermark: true)
                                }
                                .frame(height: landscape ? 128 : (width >= 641 ? 170 : 120))
                                .clipShape(EmployeeCourtyardArch())
                                .overlay { EmployeeCourtyardArch().stroke(appearance.accent.opacity(0.3), lineWidth: 1) }
                                Text(design.cardTitle).font(appearance.body(11, weight: .medium)).foregroundStyle(appearance.text).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityLabel("View design, \(design.cardTitle)")
                    }
                }
            }.frame(maxWidth: 620)
        }
    }

    @ViewBuilder private func heroDesign(height: CGFloat) -> some View {
        if let design = designs.first {
            Button { selectedDesign = design } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        appearance.subtle
                        ProtectedImageView(url: design.imageLink, contentMode: .scaleAspectFill, watermark: true, multiply: false)
                    }
                    .frame(height: height).clipped()
                    .padding(appearance.style == .neelam ? 10 : 0)
                    .background(appearance.surface)
                    .overlay { if appearance.style == .neelam { Rectangle().stroke(appearance.accent.opacity(0.3), lineWidth: 1).padding(5) } }
                    .clipShape(.rect(topLeadingRadius: appearance.style == .aegean ? height * 0.35 : 0,
                                     bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                     topTrailingRadius: appearance.style == .aegean ? height * 0.35 : 0))
                    if appearance.style == .aegean {
                        VStack(spacing: 3) {
                            Rectangle().fill(appearance.border).frame(height: 3)
                            Rectangle().fill(appearance.subtle).frame(height: 9).padding(.horizontal, 10)
                            Rectangle().fill(appearance.border.opacity(0.7)).frame(height: 2).padding(.horizontal, 5)
                        }.padding(.top, 6).padding(.horizontal, 12)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FROM YOUR COLLECTION").font(appearance.body(9, weight: .medium)).kerning(1.6).foregroundStyle(appearance.accent)
                            Text(design.cardTitle).font(appearance.body(14, weight: .medium)).foregroundStyle(appearance.text).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .light)).foregroundStyle(appearance.accent)
                    }
                    .padding(20).background(appearance.surface)
                }
                .overlay { Rectangle().stroke(appearance.border, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View featured design, \(design.cardTitle)")
        } else {
            VStack(spacing: 16) {
                Image(systemName: "diamond").font(.system(size: 64, weight: .ultraLight))
                Text("Your next discovery awaits.").font(appearance.display(24))
            }
            .foregroundStyle(appearance.accent)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(appearance.surface)
            .overlay { Rectangle().stroke(appearance.border, lineWidth: 1) }
        }
    }

    // MARK: - Hero

    private func sarvamHero(_ session: EmployeeSession, geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            logo(session, size: 64).padding(.bottom, 28)
            Text("Your store. Your collection.")
                .font(appearance.body(13, weight: .medium))
                .foregroundStyle(appearance.accent)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(appearance.accent.opacity(0.12)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(appearance.accent.opacity(0.12)).frame(height: 1) }
                .padding(.bottom, 30)
            Text(session.storeName)
                .font(appearance.display(geo.size.width >= 768 ? 54 : 44))
                .kerning(-1.3)
                .foregroundStyle(appearance.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
            Text("Discover designs selected with precision, blending craftsmanship and ethnic style")
                .font(appearance.body(geo.size.width >= 640 ? 18 : 16))
                .lineSpacing(6)
                .foregroundStyle(appearance.ink(Color(hex: 0x3D3D3D)))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { sarvamActions }
                VStack(spacing: 16) { sarvamActions }
            }
            .padding(.top, 36)
            Spacer(minLength: 48)
            Text("JEWELLERY, THOUGHTFULLY SELECTED")
                .font(appearance.body(11))
                .kerning(1.5)
                .foregroundStyle(appearance.muted)
                .multilineTextAlignment(.center)
                .padding(.bottom, 112)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: geo.size.height)
        .background { EmployeeHeroGradient() }
    }

    @ViewBuilder private var sarvamActions: some View {
        Button("Catalogue", action: onOpenCatalogue)
            .buttonStyle(EmployeeSarvamButtonStyle())
        Button("Infinite Canvas") { showCanvas = true }
            .buttonStyle(EmployeeSarvamButtonStyle(secondary: true))
    }

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
                .font(appearance.display(nameSize))
                .lineSpacing(nameSize * 0.25)
                .foregroundStyle(appearance.ink(Color(hex: 0x2C1F18)))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            let subSize: CGFloat = medium ? 15 : 13
            Text("Discover designs selected with precision, blending craftsmanship and ethnic style")
                .font(appearance.body(subSize))
                .lineSpacing(subSize * 0.625)
                .foregroundStyle(appearance.secondaryInk(Color(hex: 0x4A3B32)))
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
            .background(appearance.panel())
            .clipShape(Circle())
            .overlay { Circle().stroke(appearance.line(Color(hex: 0xF3F4F6)), lineWidth: 1) }
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
    @Environment(\.employeeAppearance) private var appearance
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
                .font(appearance.display(titleSize))
                .kerning(titleSize * 0.05)
                .lineSpacing(titleSize * 0.2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onCatalog) {
                    Text("CATALOG")
                        .font(appearance.body(13, weight: .bold))
                        .kerning(1.3)
                        .foregroundStyle(appearance.ink(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(appearance.panel())
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 4)
                }
                .buttonStyle(PressScaleStyle(scale: 1.02))

                Button(action: onCanvas) {
                    Text("INFINITE CANVAS")
                        .font(appearance.body(12, weight: .semibold))
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
    @Environment(\.employeeAppearance) private var appearance
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
                    .padding(.leading, appearance.enabled ? 0 : (large ? 48 : medium ? 32 : 16))
                    .padding(.bottom, 48)

                HStack(alignment: .top, spacing: 32) {
                    grid
                    if large && !appearance.enabled {
                        tall
                    }
                }

                Button(action: onViewAll) {
                    Text("VIEW ALL")
                        .font(appearance.body(11, weight: .semibold))
                        .kerning(2.75)
                        .foregroundStyle(appearance.secondaryInk(Color(hex: 0x6A7282)))
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
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            .background(appearance.panel())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: medium ? 12 : 8) {
            let heading: CGFloat = appearance.enabled ? (medium ? 36 : 28) : (large ? 46 : medium ? 40 : 32)
            Text("Designer collection")
                .font(appearance.display(heading))
                .lineSpacing(heading * 0.25)
                .foregroundStyle(appearance.ink(Color(hex: 0x111827)))
            let sub: CGFloat = large ? 18 : medium ? 16 : 14
            // Copied exactly, including the web's "the our own".
            Text("Original designs, crafted for your store")
                .font(appearance.body(sub, weight: .light))
                .lineSpacing(sub * 0.5)
                .foregroundStyle(appearance.secondaryInk(Color(hex: 0x99A1AF)))
        }
    }

    private var grid: some View {
        let columns = width >= 640 ? 2 : 1
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: appearance.enabled ? 24 : 32, alignment: .top), count: columns),
            spacing: appearance.enabled ? 24 : (medium ? 64 : 48)
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
    @Environment(\.employeeAppearance) private var appearance
    let design: RetailerDesign
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Color(hex: 0xF8F8F8)
                    .aspectRatio(5.0 / 4.0, contentMode: .fit)
                    .overlay {
                        ProtectedImageView(url: design.imageLink, contentMode: .scaleAspectFit,
                                           watermark: true, multiply: !appearance.dark)
                    }
                    .clipped()
                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)

                Text(design.cardTitle)
                    .font(appearance.enabled ? appearance.body(15, weight: .medium) : .cirka(13))
                    .kerning(0.325)
                    .foregroundStyle(appearance.ink(Color(hex: 0x364153)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
            }
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .employeeCard()
        .accessibilityLabel(design.cardTitle)
    }
}
