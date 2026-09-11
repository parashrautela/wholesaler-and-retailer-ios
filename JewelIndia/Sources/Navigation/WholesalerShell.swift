import SwiftUI

/// The wholesaler tab shell: Home → Catalogue → Chamak → Orders → Chat.
///
/// This deliberately departs from the web's mobile bottom nav
/// (`components/wholesaler/Sidebar.jsx`: Home → Catalogue → Add/Upload →
/// Orders → Chat). Chamak — Fusion and Set Creation — was reachable only from
/// the profile menu and one Home card, so it takes the centre slot:
/// - Catalogue on its left is what Chamak works from.
/// - Orders and Chat on its right are where you sell.
///
/// Add/Upload gave up its tab for it. Uploading is an action on the
/// catalogue rather than a place, so it's a sheet opened from Catalogue's +
/// and Home's "Upload Now". Invite Retailer isn't a tab either: it's a Home
/// card, the Orders/Chat empty states, and the profile menu.
///
/// iOS 26 renders `TabView` + `Tab` as the floating glass bar automatically —
/// no custom material is applied anywhere in this file.
struct WholesalerShell: View {
    @Environment(SessionStore.self) private var session
    @State private var credits = CreditStore()

    @State private var selection: WholesalerTab = .home
    @State private var showLogoutConfirm = false
    @State private var showInviteRetailer = false
    @State private var showTreasureChestSheet = false

    @State private var homePath: [HomeRoute] = []
    @State private var catalogueCategory: String?

    init() {}

    #if DEBUG
    /// Peeks only: start from a seeded wallet.
    init(credits: CreditStore) {
        _credits = State(initialValue: credits)
    }
    #endif

    enum WholesalerTab: Hashable {
        case home, catalogue, chamak, orders, chat
    }

    enum HomeRoute: Hashable {
        case uploadHistory
        case treasureChest
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(Copy.WholesalerTab.home, image: "NavHome", value: .home) {
                NavigationStack(path: $homePath) {
                    WholesalerHomeView(
                        onSelectTab: { selection = $0 },
                        onSelectCategory: { slug in
                            catalogueCategory = slug
                            selection = .catalogue
                        },
                        onOpenUploadHistory: { homePath.append(.uploadHistory) },
                        onOpenTreasureChest: { homePath.append(.treasureChest) },
                        onInviteRetailer: { showInviteRetailer = true }
                    )
                    .toolbar { profileMenu }
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .uploadHistory:
                            UploadHistoryView()
                        case .treasureChest:
                            TreasureChestView()
                        }
                    }
                }
            }

            Tab(Copy.WholesalerTab.catalogue, image: "NavCatalogue", value: .catalogue) {
                NavigationStack {
                    WholesalerCatalogueView(initialCategory: catalogueCategory)
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.WholesalerTab.chamak, systemImage: "sparkles", value: .chamak) {
                NavigationStack {
                    ChamakHubView()
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.WholesalerTab.orders, image: "NavOrders", value: .orders) {
                NavigationStack {
                    WholesalerOrdersView()
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.WholesalerTab.chat, image: "NavChat", value: .chat) {
                NavigationStack {
                    WholesalerChatView()
                        .toolbar { profileMenu }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Palette.dark)
        .environment(credits)
        .task {
            await credits.refresh()
        }
        .sheet(isPresented: $showTreasureChestSheet) {
            NavigationStack {
                TreasureChestView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showTreasureChestSheet = false
                            }
                            .font(.manrope(14, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                        }
                    }
            }
            .environment(credits)
        }
        .confirmationDialog(
            Copy.logoutTitle,
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button(Copy.logoutConfirm, role: .destructive) {
                Task { await session.signOut() }
            }
            Button(Copy.logoutCancel, role: .cancel) {}
        } message: {
            Text(Copy.logoutBody)
        }
        .sheet(isPresented: $showInviteRetailer) {
            InviteRetailerSheet()
                .presentationDetents([.medium, .large])
        }
    }

    @ToolbarContentBuilder
    private var profileMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            CreditBalancePill {
                if selection == .home {
                    homePath.append(.treasureChest)
                } else {
                    showTreasureChestSheet = true
                }
            }

            Menu {
                Button {
                    showInviteRetailer = true
                } label: {
                    Label(Copy.WholesalerTab.inviteRetailer, image: "NavAddRetailer")
                }
                Divider()
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label(Copy.logoutConfirm, systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image("JewelLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(.rect(cornerRadius: 6))
            }
            .accessibilityLabel("More options")
        }
    }
}
