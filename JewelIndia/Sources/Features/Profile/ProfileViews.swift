import SwiftUI
import Supabase

// MARK: - Wholesaler

/// The wholesaler's profile: who they are on Jewel India, their wallet and
/// shortcuts, the legal pages, and Log Out.
struct WholesalerProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onInviteRetailer: () -> Void = {}

    @State private var details: WholesalerDetails?
    @State private var isLoading = true
    @State private var confirmLogout = false

    #if DEBUG
    /// Peeks only.
    var peekDetails: WholesalerDetails?
    #endif

    var body: some View {
        List {
            Section {
                ProfileHeader(
                    imageURL: details?.logoURL,
                    title: details?.businessName ?? (isLoading ? " " : "Your business"),
                    subtitle: details?.ownerName,
                    badge: details?.statusLabel
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Account") {
                ProfileRow(label: "Email", value: details?.email ?? session.user?.email)
                ProfileRow(label: "Phone", value: session.user?.phone?.nilIfEmpty.map { "+\($0)" })
                ProfileRow(label: "Location", value: details?.location)
                ProfileRow(label: "Member since", value: details?.memberSince)
            }

            Section {
                NavigationLink {
                    TreasureChestView()
                } label: {
                    Label("Treasure Chest", systemImage: "sparkles")
                }
                Button {
                    dismiss()
                    onInviteRetailer()
                } label: {
                    Label("Invite a Retailer", systemImage: "person.badge.plus")
                }
            }

            LegalSection()

            Section {
                Button(role: .destructive) { confirmLogout = true } label: {
                    Label(Copy.logoutConfirm, systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Palette.dark)
        .task { await load() }
        .confirmationDialog(Copy.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(Copy.logoutConfirm, role: .destructive) { Task { await session.signOut() } }
            Button(Copy.logoutCancel, role: .cancel) {}
        } message: {
            Text(Copy.logoutBody)
        }
    }

    private func load() async {
        #if DEBUG
        if let peekDetails { details = peekDetails; isLoading = false; return }
        #endif
        defer { isLoading = false }
        guard let user = session.user else { return }
        details = try? await SupabaseManager.client.from("wholesalers")
            .select("business_name, full_name, email, city, state, verification_status, business_logo_url, created_at")
            .eq("user_id", value: user.id.uuidString)
            .single()
            .execute()
            .value
    }
}

struct WholesalerDetails: Decodable, Sendable {
    let businessName: String?
    let ownerName: String?
    let email: String?
    let city: String?
    let state: String?
    let status: String?
    let logo: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case email, city, state
        case businessName = "business_name"
        case ownerName = "full_name"
        case status = "verification_status"
        case logo = "business_logo_url"
        case createdAt = "created_at"
    }

    var logoURL: URL? { logo?.trimmed.nilIfEmpty.flatMap(URL.init(string:)) }
    var location: String? {
        [city, state].compactMap { $0?.trimmed.nilIfEmpty }.joined(separator: ", ").nilIfEmpty
    }
    var memberSince: String? {
        ChatTime.date(createdAt)?.formatted(.dateTime.month(.wide).year())
    }
    var statusLabel: String? {
        switch status {
        case "verified": "Verified"
        case "pending": "Under review"
        case "rejected": "Needs changes"
        default: nil
        }
    }

    #if DEBUG
    init(businessName: String, ownerName: String, email: String, city: String, state: String) {
        self.businessName = businessName; self.ownerName = ownerName; self.email = email
        self.city = city; self.state = state; self.status = "verified"; self.logo = nil
        self.createdAt = "2026-09-06T10:00:00.000000+00:00"
    }
    #endif
}

// MARK: - Staff

/// The staff profile: who they are, which store, and Log Out. A store owner
/// looking through Employee View sees their store and a way back to it.
struct StaffProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let current: EmployeeSession
    var onBackToDashboard: () -> Void = {}

    @State private var me: StaffDetails?
    @State private var confirmLogout = false

    #if DEBUG
    /// Peeks only.
    var peekDetails: StaffDetails?
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileHeader(
                        imageURL: current.storeLogoURL,
                        title: me?.name ?? (current.isRetailer ? current.storeName : " "),
                        subtitle: current.isRetailer ? "Store owner · Employee View" : current.storeName,
                        badge: me?.designation
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if !current.isRetailer {
                    Section("Account") {
                        ProfileRow(label: "Username", value: me?.username)
                        ProfileRow(label: "Phone", value: me?.phone)
                        ProfileRow(label: "Store", value: current.storeName)
                    }
                } else {
                    Section {
                        Button {
                            dismiss()
                            onBackToDashboard()
                        } label: {
                            Label("Back to Store Dashboard", systemImage: "square.grid.2x2")
                        }
                    }
                }

                LegalSection()

                Section {
                    Button(role: .destructive) { confirmLogout = true } label: {
                        Label(Copy.logoutConfirm, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    if !current.isRetailer {
                        Text("Forgot your password? Ask your store owner to reset it.")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Palette.dark)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .confirmationDialog(Copy.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(Copy.logoutConfirm, role: .destructive) { Task { await session.signOut() } }
                Button(Copy.logoutCancel, role: .cancel) {}
            } message: {
                Text(Copy.logoutBody)
            }
        }
    }

    private func load() async {
        #if DEBUG
        if let peekDetails { me = peekDetails; return }
        #endif
        guard case .employee(let id) = current.identity else { return }
        // RLS: "Employees can view self".
        me = try? await SupabaseManager.client.from("employees")
            .select("full_name, email, designation, phone")
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }
}

struct StaffDetails: Decodable, Sendable {
    let name: String?
    let username: String?
    let designation: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case designation, phone
        case name = "full_name"
        case username = "email"
    }

    #if DEBUG
    init(name: String, username: String, designation: String?, phone: String?) {
        self.name = name; self.username = username; self.designation = designation; self.phone = phone
    }
    #endif
}

/// The round button staff use to open their profile.
struct StaffProfileButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(hex: 0x111827))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.6), lineWidth: 1) }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }
}

// MARK: - Shared pieces

private struct ProfileHeader: View {
    let imageURL: URL?
    let title: String
    let subtitle: String?
    let badge: String?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Color.white
                if let imageURL {
                    CachedImage(url: imageURL)
                } else {
                    Image("JewelLogo").resizable().scaledToFill()
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            .overlay { Circle().stroke(Palette.border, lineWidth: 1) }

            Text(title)
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
                .multilineTextAlignment(.center)
            if let subtitle = subtitle?.trimmed.nilIfEmpty {
                Text(subtitle)
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
            }
            if let badge = badge?.trimmed.nilIfEmpty {
                Text(badge)
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x047857))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xD1FAE5), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }
}

private struct ProfileRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = value?.trimmed.nilIfEmpty {
            HStack {
                Text(label).foregroundStyle(Palette.muted)
                Spacer()
                Text(value)
                    .foregroundStyle(Palette.foreground)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .font(.manrope(14))
        }
    }
}

private struct LegalSection: View {
    var body: some View {
        Section {
            Link(destination: LegalLinks.terms) {
                Label("Terms & Conditions", systemImage: "doc.text")
            }
            Link(destination: LegalLinks.privacy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        }
    }
}
