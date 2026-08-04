import SwiftUI

/// `/dashboard/wholesaler` — the landing screen.
///
/// Composition matches the web: sticky "Home" title, hero upload banner, an
/// "Insights" grid of four KPI cards, the Chamak promo, then the catalogue
/// category grid with a trailing "View All" tile.
struct WholesalerHomeView: View {
    @Environment(SessionStore.self) private var session

    @State private var model = HomeModel()
    let onSelectTab: (WholesalerShell.WholesalerTab) -> Void
    let onSelectCategory: (String?) -> Void
    let onOpenUploadHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                insights
                catalogueSection
            }
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .task { await model.load(session: session) }
        .refreshable { await model.load(session: session) }
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

            // The banner artwork is far wider than it is tall, so it must be
            // clipped to the container rather than allowed to set the
            // container's width — otherwise the card bleeds past its padding.
            ZStack(alignment: .bottom) {
                Color(hex: 0xFFFDF9)
                    .overlay {
                        Image("HeroFrame")
                            .resizable()
                            .scaledToFill()
                            .opacity(0.8)
                    }
                    .clipped()

                Button {
                    onSelectTab(.upload)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                        Text("Upload Now")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black, in: .rect(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.bottom, Spacing.lg)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: 0xF3E8D6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
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
                .padding(.bottom, Spacing.xl)

            VStack(spacing: Spacing.base) {
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
                    title: "New Chat",
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

            ChamakCard()
                .padding(.top, Spacing.xl)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Catalogue

    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("My Catalogue")
                .font(.cirka(34))
                .foregroundStyle(Palette.dark)
                .padding(.bottom, 6)

            Text("See and manage all your catalogue categories from one place.")
                .font(.gilroy(14, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, Spacing.lg)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.lg),
                          GridItem(.flexible(), spacing: Spacing.lg)],
                spacing: Spacing.lg
            ) {
                ForEach(CatalogueCategory.all) { category in
                    CategoryCard(category: category) {
                        onSelectCategory(category.slug)
                    }
                }
                ViewAllCard { onSelectCategory(nil) }
            }
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

    func load(session: SessionStore) async {
        guard let user = session.user else { return }
        isLoading = true
        defer { isLoading = false }

        let wholesaler = try? await WholesalerAPI.fetchWholesaler(
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
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(value)
                        .font(.cirka(48, weight: .medium))
                        .foregroundStyle(Color(hex: 0x111827))

                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: 0x374151))
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: 0x374151))
                        if showsBadge { PingDot() }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9CA3AF))
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
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

/// The gold gradient promo card. The "Coming soon" chip has no handler on the
/// web either — it is deliberately inert.
struct ChamakCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0xBB8651), Color(hex: 0xF6E0A7)],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Chamak")
                        .font(.cirka(32, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Review products with low engagement and Replace with better designs")
                        .font(.manrope(13))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Coming soon")
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black, in: .rect(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: 0xE4CC8F), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 4)
                        .padding(.top, Spacing.xs)
                }
                Spacer(minLength: 0)

                Image("ChamakNecklace")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .offset(x: 10, y: -6)
            }
            .padding(Spacing.xl)
        }
        .frame(minHeight: 220)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xE4CC8F).opacity(0.3), lineWidth: 1)
        }
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
                Color.clear
                    .overlay {
                        Image(category.asset)
                            .resizable()
                            .scaledToFill()
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
