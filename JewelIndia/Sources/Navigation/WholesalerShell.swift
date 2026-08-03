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

    enum WholesalerTab: Hashable {
        case home, catalogue, upload, orders, chat
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(Copy.WholesalerTab.home, image: "NavHome", value: .home) {
                shellStack(Copy.WholesalerTab.home)
            }
            Tab(Copy.WholesalerTab.catalogue, image: "NavCatalogue", value: .catalogue) {
                shellStack(Copy.WholesalerTab.catalogue)
            }
            Tab(Copy.WholesalerTab.upload, image: "NavUpload", value: .upload) {
                shellStack(Copy.WholesalerTab.upload)
            }
            Tab(Copy.WholesalerTab.orders, image: "NavOrders", value: .orders) {
                shellStack(Copy.WholesalerTab.orders)
            }
            Tab(Copy.WholesalerTab.chat, image: "NavChat", value: .chat) {
                shellStack(Copy.WholesalerTab.chat)
            }
        }
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
            PhasePlaceholder(
                title: Copy.WholesalerTab.inviteRetailer,
                note: "Ported in Phase 2 — /dashboard/wholesaler/add-retailer"
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func shellStack(_ title: String) -> some View {
        NavigationStack {
            PhasePlaceholder(title: title, note: placeholderNote(title))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar { profileMenu }
        }
    }

    /// The wholesaler rail has no profile block on the web — its only trailing
    /// control is the logo, which acts as the logout trigger. A logo that
    /// destroys the session is not an acceptable native affordance, so logout
    /// moves into a labelled menu here (flagged in the Phase 1 notes).
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
                // The logo is a complete gradient tile with a white monogram,
                // so it renders as-authored rather than as a template mask.
                Image("JewelLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(.rect(cornerRadius: 6))
            }
            .accessibilityLabel("More options")
        }
    }

    private func placeholderNote(_ title: String) -> String {
        switch title {
        case Copy.WholesalerTab.home: "Phase 2 — /dashboard/wholesaler"
        case Copy.WholesalerTab.catalogue: "Phase 2 — /dashboard/wholesaler/catalogue"
        case Copy.WholesalerTab.upload: "Phase 2 — /dashboard/wholesaler/add-product (AI upload)"
        case Copy.WholesalerTab.orders: "Phase 2 — /dashboard/wholesaler/orders"
        default: "Phase 2 — /dashboard/wholesaler/queries"
        }
    }
}
