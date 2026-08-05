import SwiftUI

/// The retailer tab shell.
///
/// Tab set and order come from the web's mobile bottom nav in
/// `components/retailer/RetailerSidebar.jsx`: Dashboard → Catalogue →
/// Employees → Your Taste. Store Theme, Employee View and Log Out live in the
/// avatar-triggered menu, exactly as they do in the web's More popover.
///
/// Retailer icons are not Cloudinary assets on the web (unlike the wholesaler
/// rail), so SF Symbols are used here.
struct RetailerShell: View {
    @Environment(SessionStore.self) private var session

    @State private var selection: RetailerTab = .dashboard
    @State private var showLogoutConfirm = false
    @State private var showTheme = false
    @State private var showAddEmployee = false

    enum RetailerTab: Hashable {
        case dashboard, catalogue, employees, yourTaste
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
            Tab(Copy.RetailerTab.yourTaste, systemImage: "heart", value: .yourTaste) {
                NavigationStack {
                    YourTasteView()
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
        .sheet(isPresented: $showTheme) {
            StoreThemeView()
        }
        .sheet(isPresented: $showAddEmployee) {
            AddEmployeeSheet()
        }
    }

    private func shellStack(_ title: String, note: String) -> some View {
        NavigationStack {
            PhasePlaceholder(title: title, note: note)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar { profileMenu }
        }
    }

    @ToolbarContentBuilder
    private var profileMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
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

/// The scene a verified retailer lands in by default — `jewel_view_mode` is
/// absent, which the web treats as employee mode.
struct EmployeeShell: View {
    @Environment(SessionStore.self) private var session

    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            PhasePlaceholder(
                title: "Employee View",
                note: "Phase 3 — /dashboard/employee (retailers land here by default)"
            )
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await switchToRetailerView() }
                        } label: {
                            Label("Take me to dashboard", systemImage: "square.grid.2x2.fill")
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
            .safeAreaInset(edge: .top) { employeeBanner }
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
    }

    /// The persistent capsule the web pins while a retailer is in employee
    /// mode — `#FEF3C7` fill, `#F59E0B` border, `#B45309` text.
    private var employeeBanner: some View {
        Text("EMPLOYEE VIEW ACTIVE")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(hex: 0xB45309))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(hex: 0xFEF3C7), in: .capsule)
            .overlay { Capsule().stroke(Color(hex: 0xF59E0B), lineWidth: 1) }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, Spacing.screenGutter)
            .padding(.bottom, Spacing.sm)
    }

    private func switchToRetailerView() async {
        guard let id = session.user?.id else { return }
        ViewModeStore.set(.retailer, for: id)
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
