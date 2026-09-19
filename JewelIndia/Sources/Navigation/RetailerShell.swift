import SwiftUI

/// The retailer tab shell.
///
/// Tab set and order come from the web's mobile bottom nav in
/// `components/retailer/RetailerSidebar.jsx`: Dashboard → Catalogue →
/// Employees → Discover. On device the Discover slot is Wishlists — the
/// store's customers and their boards — with Discover one tap inside it. Store Theme, Employee View and Log Out live in the
/// avatar-triggered menu, exactly as they do in the web's More popover.
///
/// Retailer icons are not Cloudinary assets on the web (unlike the wholesaler
/// rail), so SF Symbols are used here.
struct RetailerShell: View {
    @Environment(SessionStore.self) private var session

    @State private var credits = CreditStore()
    @State private var selection: RetailerTab = .dashboard
    @State private var showTreasureChest = false
    @State private var showPlans = false
    @State private var showChamak = false
    @State private var showChats = false
    @State private var showLogoutConfirm = false
    @State private var showTheme = false
    @State private var showAddEmployee = false

    enum RetailerTab: Hashable {
        case dashboard, catalogue, employees, yourTaste, orders
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(Copy.RetailerTab.dashboard, systemImage: "square.grid.2x2.fill", value: .dashboard) {
                NavigationStack {
                    RetailerDashboardView(onOpenAddEmployee: { showAddEmployee = true })
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.RetailerTab.catalogue, systemImage: "square.grid.2x2", value: .catalogue) {
                NavigationStack {
                    RetailerCatalogueView()
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.RetailerTab.employees, systemImage: "person.2", value: .employees) {
                NavigationStack {
                    EmployeesListView(onOpenAddEmployee: { showAddEmployee = true })
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.RetailerTab.yourTaste, systemImage: "heart.text.square", value: .yourTaste) {
                NavigationStack {
                    CustomerWishlistView()
                        .toolbar { profileMenu }
                }
            }
            Tab(Copy.RetailerTab.orders, systemImage: "bag", value: .orders) {
                NavigationStack {
                    RetailerOrdersView()
                        .toolbar { profileMenu }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Palette.dark)
        .environment(credits)
        .task {
            StoreActivity.registerDevice()
            await credits.refresh()
            await credits.refreshPlan()
        }
        // Five tabs is the phone's limit, so Chamak opens from the menu. The
        // flow itself is the wholesaler's, picking from the store's designs.
        .fullScreenCover(isPresented: $showChamak) {
            NavigationStack {
                ChamakHubView(catalogueSource: .storeDesigns)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showChamak = false
                            }
                            .font(.manrope(14, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                        }
                    }
            }
            .environment(credits)
        }
        .sheet(isPresented: $showChats) {
            NavigationStack {
                ChatThreadsView(
                    emptyTitle: "No chats yet",
                    emptyMessage: "Open a design in Discover and tap “Ask About this Design” to talk to its supplier. Your staff's chats show up here too."
                )
                .navigationTitle("Chats")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showChats = false
                        }
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                    }
                }
            }
        }
        .sheet(isPresented: $showPlans) {
            NavigationStack {
                PlansView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showPlans = false
                            }
                            .font(.manrope(14, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                        }
                    }
            }
            .environment(credits)
        }
        .sheet(isPresented: $showTreasureChest) {
            NavigationStack {
                TreasureChestView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showTreasureChest = false
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
        .sheet(isPresented: $showTheme) {
            StoreThemeView()
                .environment(credits)
        }
        .sheet(isPresented: $showAddEmployee) {
            AddEmployeeSheet()
        }
    }

    @ToolbarContentBuilder
    private var profileMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            CreditBalancePill {
                showTreasureChest = true
            }

            Menu {
                Button {
                    showChamak = true
                } label: {
                    Label("Chamak Studio", systemImage: "sparkles")
                }
                Button {
                    showChats = true
                } label: {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                }
                Divider()
                Button {
                    showTreasureChest = true
                } label: {
                    Label("Treasure Chest", systemImage: "shippingbox")
                }
                Button {
                    showPlans = true
                } label: {
                    Label("Plans", systemImage: "crown")
                }
                Button {
                    showTheme = true
                } label: {
                    Label("Store Theme", systemImage: "paintpalette")
                }
                Button {
                    Task { await switchToEmployeeView() }
                } label: {
                    Label("Employee View", systemImage: "person.crop.rectangle")
                }
                Divider()
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label(Copy.logoutConfirm, systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.dark)
            }
            .accessibilityLabel("More options")
        }
    }

    /// The web posts `/api/auth/toggle-view {mode:"employee"}` and then hard-
    /// navigates. That endpoint exists only to write an httpOnly cookie the
    /// server can read; on device the preference is local, so the mode is set
    /// directly and the root scene swaps.
    private func switchToEmployeeView() async {
        guard let id = session.user?.id else { return }
        ViewModeStore.set(.employee, for: id)
        await session.refreshDestination()
    }
}

/// A visible marker for surfaces that land in a later phase, so a demo build
/// never silently shows an empty screen.
struct PhasePlaceholder: View {
    let title: String
    let note: String

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Text(title)
                    .font(.cirka(30))
                    .foregroundStyle(Palette.foreground)
                Text(note)
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.xxl)
        }
    }
}
