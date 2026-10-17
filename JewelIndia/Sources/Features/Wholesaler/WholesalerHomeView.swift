import SwiftUI

/// `/dashboard/wholesaler` — the landing screen.
///
/// Composition matches the web: sticky "Home" title, hero upload banner, an
/// "Insights" grid of four KPI cards, the Chamak promo, then the latest Chamak
/// creations (combines and sets). The catalogue category grid that used to
/// close the page is now the first page of the My Catalogue tab. iOS adds an
/// Invite Retailer card under the promo, since that action has no tab of its own.
struct WholesalerHomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CreditStore.self) private var credits

    @State private var model = HomeModel()
    @State private var showReport = false
    @State private var isLowBalanceBannerDismissed = false
    @State private var showTopUpSheet = false
    @State private var showAddProduct = false

    let onSelectTab: (WholesalerShell.WholesalerTab) -> Void
    let onOpenUploadHistory: () -> Void
    let onOpenTreasureChest: () -> Void
    let onInviteRetailer: () -> Void
    var onOpenManufacturingOffers: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                if let errorMessage = model.errorMessage {
                    homeErrorBanner(message: errorMessage)
                        .padding(.horizontal, Spacing.base)
                        .padding(.bottom, Spacing.base)
                }

                if let wallet = credits.wallet, wallet.lowBalance, !isLowBalanceBannerDismissed {
                    lowBalanceBanner(wallet: wallet)
                        .padding(.horizontal, Spacing.base)
                        .padding(.bottom, Spacing.base)
                }

                TreasureChestCard(
                    onOpenTreasureChest: onOpenTreasureChest,
                    onTopUp: { showTopUpSheet = true }
                )
                .padding(.horizontal, Spacing.base)
                .padding(.bottom, Spacing.base)

                insights
                LatestCreationsSection(onSeeAll: { onSelectTab(.chamak) })
            }
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await model.load(session: session)
            await credits.refresh()
        }
        .refreshTask {
            await model.load(session: session)
            await credits.refresh()
        }
        .sheet(isPresented: $showReport) {
            WholesalerReportView()
        }
        .sheet(isPresented: $showTopUpSheet) {
            TopUpSheet()
        }
        .sheet(isPresented: $showAddProduct, onDismiss: {
            // A submission bumps "Uploads Today".
            Task { await model.load(session: session) }
        }) {
            AddProductSheet()
                .environment(credits)
        }
    }

    // MARK: - Low Balance Banner

    private func lowBalanceBanner(wallet: CreditWallet) -> some View {
        let cost = credits.cost(for: "chamak.generate") ?? 200
        let fusionsLeft = cost > 0 ? (wallet.available / cost) : wallet.available

        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.statusPending)

            VStack(alignment: .leading, spacing: 2) {
                Text("Running low on credits")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Text("\(wallet.available) credits left, about \(fusionsLeft) more \(fusionsLeft == 1 ? "fusion" : "fusions").")
                    .font(.manrope(12))
                    .foregroundStyle(Color(hex: 0x92400E))
            }

            Spacer()

            Button {
                showTopUpSheet = true
            } label: {
                Text("Buy")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.dark, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                isLowBalanceBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .padding(6)
            }
        }
        .padding(Spacing.md)
        .background(Color(hex: 0xFFFBEB), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: 0xFDE68A), lineWidth: 1)
        }
    }

    private func homeErrorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.red)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.manrope(13))
                    .foregroundStyle(Palette.dark)

                Button("Retry") {
                    Task { await model.load(session: session) }
                }
                .buttonStyle(.plain)
                .font(.manrope(13, weight: .semibold))
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color(hex: 0xFEF2F2), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: 0xFECACA), lineWidth: 1)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome")
                .font(.sfPro(13))
                .foregroundStyle(Color(hex: 0x6B7280))

            // The web falls back to the literal word "Welcome" when the
            // business name is blank.
            Text(model.businessName.isEmpty ? "Welcome" : model.businessName)
                .font(.sfPro(22, weight: .medium))
                .foregroundStyle(Color(hex: 0x1F2937))
                .padding(.bottom, Spacing.base)

            UploadDesignCard { showAddProduct = true }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.base)
    }

    // MARK: - Insights

    private var insights: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Insights")
                .font(.cirka(34))
                .foregroundStyle(Palette.dark)
                .padding(.bottom, Spacing.base)

            WholesalerReportTeaser { showReport = true }
                .padding(.bottom, Spacing.sm)

            // Side by side in one row, so the four numbers take one line of
            // the screen instead of four.
            HStack(spacing: Spacing.sm) {
                StatCard(
                    title: "Live Products",
                    value: "\(model.productCount)",
                    symbol: "shippingbox",
                    showsBadge: false
                ) { onSelectTab(.catalogue) }

                StatCard(
                    title: "New Orders",
                    value: "\(model.pendingOrders)",
                    symbol: "bag",
                    showsBadge: model.pendingOrders > 0
                ) { onSelectTab(.orders) }

                StatCard(
                    title: "New Chats",
                    value: "\(model.unreadChats)",
                    symbol: "bubble.left",
                    showsBadge: model.unreadChats > 0
                ) { onSelectTab(.chat) }

                StatCard(
                    title: "Uploads Today",
                    value: model.usage.display,
                    symbol: "arrow.up.circle",
                    showsBadge: false
                ) { onOpenUploadHistory() }
            }

            if let onOpenManufacturingOffers {
                ManufacturingOffersCard(onOpenOffers: onOpenManufacturingOffers)
                    .padding(.top, Spacing.lg)
            }

            ChamakCard { onSelectTab(.chamak) }
            .padding(.top, Spacing.xl)

            InviteRetailerCard(action: onInviteRetailer)
                .padding(.top, Spacing.base)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.xl)
    }

}

// MARK: - Model

@MainActor
@Observable
final class HomeModel {
    var businessName = ""
    var productCount = 0
    var pendingOrders = 0
    var unreadChats = 0
    var usage: UploadUsage = .unknown
    var isLoading = true
    var errorMessage: String? = nil

    func load(session: SessionStore) async {
        guard let user = session.user else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let wholesaler = try await WholesalerAPI.fetchWholesaler(
                userID: user.id,
                email: user.email
            )
            businessName = wholesaler?.displayName ?? ""

            // The web flips this on first render; it is what moves a verified
            // wholesaler past the "submitted" gate on the next sign-in.
            if wholesaler?.hasVisitedDashboard != true {
                await WholesalerAPI.markDashboardVisited(userID: user.id)
            }

            async let products = WholesalerAPI.countProducts(wholesalerID: user.id)
            async let orders = WholesalerAPI.countPendingOrders(wholesalerID: user.id)
            async let chats = WholesalerAPI.countUnreadConversations(wholesalerID: user.id)
            async let usageValue = WholesalerAPI.fetchUploadUsage(wholesalerID: user.id)

            productCount = await products
            pendingOrders = await orders
            unreadChats = await chats
            usage = await usageValue
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Couldn't load your dashboard. Check your connection and try again."
        }
    }
}

// MARK: - Cards

/// `BottomStatCard` — big Cirka numeral, label row, trailing chevron, and a
/// pinging red dot when there is something new.
struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    let showsBadge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x374151))
                    Spacer(minLength: 0)
                    if showsBadge { PingDot() }
                }
                Text(value)
                    .font(.cirka(28, weight: .medium))
                    .foregroundStyle(Color(hex: 0x111827))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x374151))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// `animate-ping` — an expanding, fading ring behind a solid dot.
struct PingDot: View {
    @State private var animating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xF87171))
                .frame(width: 8, height: 8)
                .scaleEffect(animating ? 2 : 1)
                .opacity(animating ? 0 : 0.75)
            Circle()
                .fill(Color(hex: 0xEF4444))
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}

/// Mobile upload entry — Figma 3027:9020. Artwork uses the original layer assets.
struct UploadDesignCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleLineHeight = 21.6
    @ScaledMetric(relativeTo: .largeTitle) private var titleHeight = 37
    @ScaledMetric(relativeTo: .largeTitle) private var titleCapTrim = 3.225
    @ScaledMetric(relativeTo: .caption) private var subtitleHeight = 14
    @ScaledMetric(relativeTo: .body) private var actionHeight = 35

    let onUpload: () -> Void

    var body: some View {
        Button(action: onUpload) {
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("Upload New Jewellery")
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            Text("Upload New")
                                .frame(height: titleLineHeight)
                            Text("Jewellery")
                                .frame(height: titleLineHeight)
                        }
                        // Match Figma's 0.9 line height and trimmed cap bounds.
                        .frame(height: titleHeight)
                        .offset(y: -titleCapTrim)
                    }
                    Text("Reimagine Your Collection")
                        .font(.manrope(9.937, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xA09D8A))
                        .frame(minHeight: subtitleHeight)
                }
                .font(.cirka(24, weight: .bold))
                .foregroundStyle(Color(hex: 0x604C0D))
                .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Image("UploadDesignIcon")
                        .frame(width: 14.9053, height: 14.9053)
                        .accessibilityHidden(true)
                    Text("Upload Now")
                        .font(.manrope(14, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 125.905, minHeight: actionHeight)
                .background(Color(hex: 0x292826), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color(hex: 0xE4CC8F), lineWidth: 0.4)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color(hex: 0xE4CC8F).opacity(0.39), lineWidth: 2.484)
                        .blur(radius: 2.484)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .shadow(color: .black.opacity(0.25), radius: 2.515, y: 2.484)
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 182.589)
            .padding(.horizontal, 14)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, minHeight: 158)
            .background {
                GeometryReader { geometry in
                    artwork
                        .frame(width: 354, height: 158)
                        .scaleEffect(geometry.size.width / 354, anchor: .topLeading)
                        .opacity(dynamicTypeSize.isAccessibilitySize ? 0.2 : 1)
                }
                .accessibilityHidden(true)
            }
            .background(Color(hex: 0xFFFBF2))
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(hex: 0xFAF1F1), lineWidth: 0.621)
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Upload new jewellery")
        .accessibilityHint("Opens the form to upload a design to your catalogue.")
    }

    /// Fixed coordinates apply only to the decorative Figma canvas; content
    /// above uses intrinsic SwiftUI layout and grows with Dynamic Type.
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0xFFFBF2)

            Image("UploadDesignRightHand")
                .resizable()
                .frame(width: 198, height: 198 * 351 / 589)
                .frame(width: 198, height: 126, alignment: .top)
                .blur(radius: 1.4)
                .blendMode(.hardLight)
                .opacity(0.54)
                .rotationEffect(.degrees(12.63))
                .position(x: 231 + 220.756 / 2, y: 14 + 166.237 / 2)

            Image("UploadDesignWash")
                .resizable()
                .frame(width: 354, height: 88.811)
                .position(x: 177, y: 158 + 0.15 - 88.811 / 2)

            Image("UploadDesignLeftHand")
                .resizable()
                .frame(width: 236, height: 130)
                .blur(radius: 0.975)
                .blendMode(.hardLight)
                .opacity(0.54)
                .rotationEffect(.degrees(-18.04))
                .position(x: -151 + 264.660 / 2, y: -8 + 196.704 / 2)

            coin(x: 142, y: -37, opacity: 0.2)
            coin(x: 5, y: 122, opacity: 0.35)
            coin(x: 300, y: -10, opacity: 0.35, blur: 1)
        }
    }

    private func coin(x: CGFloat, y: CGFloat, opacity: Double, blur: CGFloat = 0) -> some View {
        Color.clear
            .frame(width: 69.558, height: 66.817)
            .overlay(alignment: .topLeading) {
                Image("UploadDesignCoin")
                    .resizable()
                    .frame(width: 69.558 * 1.1188, height: 66.817 * 1.041)
                    .offset(x: -69.558 * 0.1182, y: -66.817 * 0.0205)
            }
            .clipped()
            .blur(radius: blur)
            .opacity(opacity)
            .position(x: x + 69.558 / 2, y: y + 66.817 / 2)
    }
}

/// Mobile Chamak Studio entry card — Figma 2989:8560.
/// The whole card shares the CTA action, giving its compact pill a generous hit area.
struct ChamakCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleHeight = 48
    @ScaledMetric(relativeTo: .body) private var copyHeight = 38
    @ScaledMetric(relativeTo: .body) private var buttonHeight = 31

    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Chamak Studio")
                        .font(.cirka(32, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: 0x3E3E3E), Color(hex: 0x323232)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(minHeight: titleHeight, alignment: .leading)

                    Text("Reimagine your jewellery.\nCreate something new.")
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x494949).opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: copyHeight, alignment: .leading)
                }

                HStack(spacing: 6) {
                    Text("Get started")
                        .font(.manrope(14, weight: .semibold))
                    Image("ChamakStudioArrow")
                        .frame(width: 19, height: 18)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.black)
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .frame(minHeight: buttonHeight)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0xB6B6B6), Color(hex: 0x9E9E9E)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(Color(hex: 0xA0A0A0), lineWidth: 0.4)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color(hex: 0xEEEEEE).opacity(0.25), lineWidth: 2)
                        .blur(radius: 2)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
                }
                .shadow(color: Color(hex: 0x7E7E7E).opacity(0.25), radius: 2, y: 4)
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 211, alignment: .leading)
            .padding(.leading, 16)
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 16 : 0)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, minHeight: 193, alignment: .leading)
            .background(alignment: .trailing) {
                // Figma's artwork group includes the original soft mask.
                // The exported visible bounds are 155 × 193 at the trailing edge.
                Image("ChamakStudioArtwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 155, height: 193)
                    .opacity(dynamicTypeSize.isAccessibilitySize ? 0.2 : 1)
                    .accessibilityHidden(true)
            }
            .background(
                LinearGradient(
                    colors: [Color(hex: 0xEAEAEA), Color(hex: 0xCDCDCD)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(.rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Chamak Studio")
        .accessibilityHint("Reimagine your jewellery. Get started with combining designs or creating a set.")
    }
}

/// Home's "Latest Creations": the newest finished Chamak combines or sets,
/// switched with a Chamak | Sets toggle. Tapping a tile reopens that result in
/// the Chamak flow, the same as the Chamak tab's gallery; "See all" goes to
/// that tab.
struct LatestCreationsSection: View {
    @Environment(SessionStore.self) private var session
    @Environment(CreditStore.self) private var credits

    @State private var gallery: ChamakViewModel
    @State private var launch: ChamakLaunch?
    @State private var hasLoaded = false
    @State private var selectedMode: ChamakMode = .fusion

    let onSeeAll: () -> Void

    /// Two by two on a phone, one row on an iPad (the grid columns adapt).
    private static let shown = 4

    /// `gallery` is injectable only so a debug peek can show sample tiles.
    init(onSeeAll: @escaping () -> Void, gallery: ChamakViewModel? = nil) {
        self.onSeeAll = onSeeAll
        _gallery = State(initialValue: gallery ?? ChamakViewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Latest Creations")
                    .font(.cirka(34))
                    .foregroundStyle(Palette.dark)
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
            }
            .padding(.bottom, 6)

            Text("Your newest Chamak designs and sets.")
                .font(.gilroy(14, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, Spacing.lg)

            Picker("Creation type", selection: $selectedMode) {
                Text("Chamak").tag(ChamakMode.fusion)
                Text("Sets").tag(ChamakMode.setCreation)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.bottom, Spacing.md)

            creationsGrid(mode: selectedMode)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.xl)
        .task { await load() }
        // A run finished from here should show up on the way back.
        .fullScreenCover(item: $launch, onDismiss: { Task { await load() } }) { launch in
            if let user = session.user {
                ChamakFlowCoordinator(
                    wholesalerID: user.id,
                    mode: launch.mode,
                    openingGeneration: launch.generation,
                    catalogueSource: .ownProducts
                )
                .environment(credits)
            }
        }
    }

    private func load() async {
        guard let user = session.user else {
            hasLoaded = true
            return
        }
        await gallery.refreshGallery(wholesalerID: user.id)
        hasLoaded = true
    }

    /// Newest first, as the gallery is fetched; finished results only.
    private func latest(_ mode: ChamakMode) -> [ChamakGeneration] {
        Array(gallery.galleryGenerations.filter { $0.mode == mode && $0.status == .done }.prefix(Self.shown))
    }

    @ViewBuilder
    private func creationsGrid(mode: ChamakMode) -> some View {
        let generations = latest(mode)
        if !hasLoaded, gallery.galleryGenerations.isEmpty {
            ProgressView()
                .tint(Palette.dark)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if generations.isEmpty {
            emptyRow(mode: mode)
        } else {
            // Same columns as the Chamak tab's gallery, so tiles match.
            LazyVGrid(columns: ChamakHubView.galleryColumns, spacing: Spacing.md) {
                ForEach(generations) { generation in
                    ChamakGalleryCard(
                        generation: generation,
                        thumbnailURL: gallery.galleryThumbnailURLs[generation.id]
                    ) {
                        launch = ChamakLaunch(mode: generation.mode, generation: generation)
                    }
                }
            }
        }
    }

    /// Nothing made in this mode yet (or the gallery couldn't load): offer to
    /// start one rather than leave an empty strip.
    private func emptyRow(mode: ChamakMode) -> some View {
        Button {
            launch = ChamakLaunch(mode: mode)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: 0xBB8651))
                Text(gallery.galleryErrorMessage != nil
                     ? "Couldn't load your creations. Tap to open Chamak."
                     : (mode == .setCreation ? "No sets yet. Create your first set." : "No designs yet. Create with Chamak."))
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Palette.dark)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(Spacing.base)
            .background(Color(hex: 0xF9F9F8), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE7E5E4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A category tile: full-bleed image, dark gradient over the top half, centred
/// serif label near the top.
struct CategoryCard: View {
    let category: CatalogueCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Same clipping discipline as the hero: the tile's size comes from
            // the grid cell, and the image fills and is clipped to it.
            ZStack(alignment: .top) {
                // Most category photos have their name printed across the
                // top, which read twice under the label below ("Necklace"
                // over "Necklace"). Rendering taller than the tile and pinning
                // to the bottom crops that band away.
                Color.clear
                    .overlay(alignment: .bottom) {
                        Image(category.asset)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 272)
                    }
                    .clipped()

                LinearGradient(
                    colors: [Palette.dark.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                Text(category.name)
                    .font(.cirka(19, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.top, Spacing.xl)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// The dashed trailing tile.
struct ViewAllCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Text("→")
                    .font(.system(size: 30))
                    .foregroundStyle(Palette.muted)
                Text("View All")
                    .font(.gilroy(14, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Palette.border,
                        style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                    )
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// The web signals interactivity with hover (`scale-[1.02]`, raised shadow).
/// iOS has no hover, so the equivalent affordance is a press state — the
/// substitution the shell spec calls for.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
