import SwiftUI

/// Retailer Catalogue (`/dashboard/retailer/catalogue`): the store's own
/// pieces. Staff see the same designs on their Designs screen.
struct RetailerCatalogueView: View {
    @Environment(SessionStore.self) private var session

    @State private var designs: [RetailerDesign] = []
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAdd = false
    @State private var selected: RetailerDesign?

    #if DEBUG
    /// Peeks only: designs to show instead of fetching.
    var peekDesigns: [RetailerDesign]?
    #endif

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    private var visible: [RetailerDesign] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return designs }
        return designs.filter { design in
            [design.title, design.type, design.category, design.purity, design.styleAesthetic]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(needle) }
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            searchBar

            if isLoading && designs.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if let errorMessage, designs.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load your catalogue", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if designs.isEmpty {
                emptyState
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.xl) {
                        ForEach(visible) { design in
                            Button { selected = design } label: { DesignCard(design: design) }
                                .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .padding(.horizontal, Spacing.screenGutter)
                    .padding(.bottom, Spacing.xl)
                }
                .scrollIndicators(.hidden)
                .refreshTask { await load() }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.dark)
                }
                .accessibilityLabel("Add design")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            AddDesignSheet { Task { await load() } }
        }
        .sheet(item: $selected) { design in
            StoreDesignDetail(design: design) {
                designs.removeAll { $0.id == design.id }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.muted)
            TextField("Search store designs...", text: $searchQuery)
                .font(.manrope(14))
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
        .padding(.horizontal, Spacing.screenGutter)
        .padding(.top, Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("Store Catalogue")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("Add your store's own pieces. Your staff will see them on their Designs screen.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Label("Add a Design", systemImage: "plus")
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Palette.dark, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .padding(Spacing.xl)
    }

    private func load() async {
        #if DEBUG
        if let peekDesigns {
            designs = peekDesigns
            isLoading = false
            return
        }
        #endif
        isLoading = designs.isEmpty
        defer { isLoading = false }
        do {
            designs = try await RetailerAPI.fetchDesigns()
            errorMessage = nil
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Pull down to try again."
        }
    }
}

private struct DesignCard: View {
    let design: RetailerDesign

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                Color(hex: 0xF7F7F7)
                if let url = design.imageLink {
                    CachedImage(url: url)
                } else {
                    Image(systemName: "photo").foregroundStyle(Palette.muted)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(design.title?.trimmed.nilIfEmpty ?? design.type?.capitalized ?? "Untitled")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Palette.foreground)
                .lineLimit(1)
            Text(caption)
                .font(.manrope(11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
    }

    private var caption: String {
        let weight = design.netWeight.flatMap { $0 > 0 ? String(format: "%.2fg", $0) : nil }
        return [design.purity?.uppercased(), weight].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
            ?? (design.type?.capitalized ?? " ")
    }
}

// MARK: - Detail

private struct StoreDesignDetail: View {
    @Environment(\.dismiss) private var dismiss
    let design: RetailerDesign
    let onDeleted: () -> Void

    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ZStack {
                        Color(hex: 0xF7F7F7)
                        if let url = design.imageLink {
                            CachedImage(url: url, contentMode: .fit)
                        }
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(design.title?.trimmed.nilIfEmpty ?? "Untitled")
                            .font(.cirka(26))
                            .foregroundStyle(Palette.foreground)
                        row("Type", design.type?.capitalized)
                        row("Category", design.category?.capitalized)
                        row("Style", design.styleAesthetic?.capitalized)
                        row("Purity", design.purity?.uppercased())
                        row("Net weight", design.netWeight.flatMap { $0 > 0 ? String(format: "%.2f g", $0) : nil })
                        row("Availability", design.isInStock == true
                            ? "In stock"
                            : design.productionTimeDays.map { "Made to order · \($0) days" } ?? "Made to order")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.manrope(12))
                            .foregroundStyle(Color.red)
                    }

                    Button(role: .destructive) { confirmDelete = true } label: {
                        HStack(spacing: 8) {
                            if isDeleting { ProgressView().controlSize(.small) }
                            Text("Remove from Catalogue")
                        }
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
                .padding(Spacing.base)
            }
            .navigationTitle("Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Remove this design?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await delete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your staff will no longer see it. This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value = value?.trimmed.nilIfEmpty {
            HStack {
                Text(label).foregroundStyle(Palette.muted)
                Spacer()
                Text(value).foregroundStyle(Palette.foreground)
            }
            .font(.manrope(13))
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await RetailerAPI.deleteDesign(design)
            onDeleted()
            dismiss()
        } catch {
            errorMessage = "Couldn't remove this design. Please try again."
        }
    }
}
