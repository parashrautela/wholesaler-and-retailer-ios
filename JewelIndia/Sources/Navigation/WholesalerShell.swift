import SwiftUI

/// The wholesaler tab shell.
///
/// The tab set and its order come from the web app's **mobile** bottom nav
/// (`components/wholesaler/Sidebar.jsx`, `.wholesaler-bottom-nav`), not the
/// desktop icon rail — the mobile bar is already a floating translucent pill,
/// so the native Liquid Glass tab bar is the closer match. Web order is
/// Home → Catalogue → Add/Upload → Orders → Chat.
///
/// "Add Retailer" is deliberately not a tab: the web demotes it into the More
/// popover on mobile, so here it lives in the profile menu as a sheet.
///
/// iOS 26 renders `TabView` + `Tab` as the floating glass bar automatically —
/// no custom material is applied anywhere in this file.
struct WholesalerShell: View {
    @Environment(SessionStore.self) private var session

    @State private var selection: WholesalerTab = .home
    @State private var showLogoutConfirm = false
    @State private var showInviteRetailer = false

    @State private var homePath: [HomeRoute] = []
    @State private var catalogueCategory: String?

    enum WholesalerTab: Hashable {
        case home, catalogue, upload, orders, chat
    }

    enum HomeRoute: Hashable {
        case uploadHistory
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
                        onOpenUploadHistory: { homePath.append(.uploadHistory) }
                    )
                    .toolbar { profileMenu }
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .uploadHistory:
                            UploadHistoryView()
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
            Tab(Copy.WholesalerTab.upload, image: "NavUpload", value: .upload) {
                NavigationStack {
                    AddProductView()
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
        ToolbarItem(placement: .topBarTrailing) {
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
