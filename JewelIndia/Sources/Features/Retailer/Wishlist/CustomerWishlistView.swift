import SwiftUI

/// The Wishlists tab: the store's customers, each with boards of designs
/// they liked. Discover — the store's own shortlist — stays one tap away at
/// the top, since that is where designs are found in the first place.
struct CustomerWishlistView: View {
    @State private var customers: [StoreCustomer] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddCustomer = false
    @State private var confirmDelete: StoreCustomer?
    @State private var search = ""

    #if DEBUG
    /// Peeks only: rows to show instead of fetching.
    var peekRows: [StoreCustomer]?
    #endif

    private var visibleCustomers: [StoreCustomer] {
        let needle = search.trimmed.lowercased()
        guard !needle.isEmpty else { return customers }
        return customers.filter {
            $0.name.lowercased().contains(needle) || ($0.phone ?? "").contains(needle)
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    YourTasteView()
                } label: {
                    discoverRow
                }
            }

            Section {
                if isLoading && customers.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let errorMessage, customers.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Text(errorMessage)
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .font(.manrope(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                } else if customers.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleCustomers) { customer in
                        NavigationLink {
                            CustomerBoardsView(customer: customer) {
                                Task { await load() }
                            }
                        } label: {
                            CustomerRow(customer: customer)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                confirmDelete = customer
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Customers")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .searchable(text: $search, prompt: "Search customers")
        .navigationTitle("Customer Wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showAddCustomer = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                }
                .accessibilityLabel("Add customer")
            }
        }
        .task { await load() }
        .refreshTask { await load() }
        .sheet(isPresented: $showAddCustomer) {
            AddCustomerSheet {
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            confirmDelete.map { "Remove \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Customer", role: .destructive) {
                if let customer = confirmDelete {
                    Task { await remove(customer) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their boards and saved designs go with them. This can't be undone.")
        }
    }

    private var discoverRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Palette.dark, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover designs")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                Text("Browse the marketplace and keep your store's shortlist")
                    .font(.manrope(12))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.muted)
            Text("No customers yet")
                .font(.cirka(22))
                .foregroundStyle(Palette.foreground)
            Text("Add a customer to start saving the designs they like onto their own boards.")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button {
                showAddCustomer = true
            } label: {
                Text("Add Customer")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Palette.dark, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private func load() async {
        #if DEBUG
        if let peekRows {
            customers = peekRows
            isLoading = false
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            customers = try await WishlistAPI.fetchCustomers()
            errorMessage = nil
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Couldn't load your customers. Pull down to try again."
        }
    }

    private func remove(_ customer: StoreCustomer) async {
        do {
            try await WishlistAPI.deleteCustomer(id: customer.id)
            customers.removeAll { $0.id == customer.id }
        } catch {
            errorMessage = "Couldn't remove \(customer.name). Please try again."
        }
    }
}

private struct CustomerRow: View {
    let customer: StoreCustomer

    private var initials: String {
        customer.name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(initials)
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Palette.dark)
                .frame(width: 40, height: 40)
                .background(Palette.background, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name)
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                Text(subtitle)
                    .font(.manrope(12))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let designs = customer.designCount == 1 ? "1 design" : "\(customer.designCount) designs"
        if let phone = customer.phone?.trimmed.nilIfEmpty {
            return "\(phone) · \(designs)"
        }
        return designs
    }
}

// MARK: - Add customer

struct AddCustomerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdded: () -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool { !name.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section("Note") {
                    TextField("Occasion, budget, preferences (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .navigationTitle("New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await WishlistAPI.addCustomer(
                name: name.trimmed,
                phone: phone.trimmed.nilIfEmpty,
                note: note.trimmed.nilIfEmpty
            )
            onAdded()
            dismiss()
        } catch {
            errorMessage = "Couldn't save this customer. Please try again."
        }
    }
}
