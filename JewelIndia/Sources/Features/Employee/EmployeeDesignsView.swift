import SwiftUI

/// The store's own designs, all of them (`/dashboard/employee/designs`,
/// titled "Catalogue" on screen). Read-only: category tiles, four filters,
/// ten per page, and the same full-screen detail as Home.
struct EmployeeDesignsView: View {
    @Environment(EmployeeStore.self) private var store
    let onClose: () -> Void

    @State private var designs: [RetailerDesign] = []
    @State private var loaded = false
    @State private var category = "all"
    @State private var filters = EmployeeFilterState()
    @State private var page = 1
    @State private var header: SmartHeaderState = .top
    @State private var lastOffset: CGFloat = 0
    @State private var width: CGFloat = 390
    @State private var selected: RetailerDesign?


    private static let perPage = 10

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    headerContent
                        .opacity(header == .up ? 0 : 1)
                    content(proxy: proxy)
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
                let next = SmartHeaderState.next(offset: offset, previous: lastOffset)
                if next != header {
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.7)) { header = next }
                }
                lastOffset = offset
            }
        }
        .background(Color.white)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .overlay {
            if let design = selected, let session = store.session {
                EmployeeDesignDetail(design: design, theme: session.theme) {
                    withAnimation(.easeOut(duration: 0.2)) { selected = nil }
                }
                .transition(.opacity)
            }
        }
        .task { await load() }
        .onChange(of: category) { page = 1 }
        .onChange(of: filters) { page = 1 }
    }

    // MARK: - Header

    private var medium: Bool { width >= 768 }
    private var collapsed: Bool { header != .top }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("Catalogue")
                    .font(.gilda(medium ? 40 : 32))
                    .kerning((medium ? 40 : 32) * -0.025)
                    .foregroundStyle(Color(hex: 0x111827))
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: 0x4A5565))
                            .frame(width: 40, height: 40)
                            .background(Color.white, in: Circle())
                            .overlay { Circle().stroke(Color(hex: 0xE5E7EB), lineWidth: 1) }
                            .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Go back")
                    Spacer()
                }
            }
            .frame(maxHeight: collapsed ? 0 : 100)
            .opacity(collapsed ? 0 : 1)
            .clipped()
            .padding(.bottom, collapsed ? 0 : 40)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Curated Collection")
                        .font(.gilda(medium ? 24 : 20))
                        .foregroundStyle(Color(hex: 0x111827))
                    Text("From everyday elegance to statement pieces")
                        .font(.manrope(medium ? 14 : 13))
                        .foregroundStyle(Color(hex: 0x99A1AF))
                }
                .frame(maxHeight: collapsed ? 0 : 100, alignment: .top)
                .opacity(collapsed ? 0 : 1)
                .clipped()

                VStack(alignment: .leading, spacing: collapsed ? 0 : 32) {
                    categoryRow
                        .frame(maxHeight: collapsed ? 0 : 150, alignment: .top)
                        .opacity(collapsed ? 0 : 1)
                        .clipped()
                        .allowsHitTesting(!collapsed)
                    EmployeeFilterRow(state: $filters)
                }
            }
        }
        .frame(maxWidth: 1280, alignment: .leading)
        .padding(.horizontal, medium ? 32 : 16)
        .padding(.top, collapsed ? 12 : 32)
        .padding(.bottom, collapsed ? 12 : 24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.95))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF3F4F6)).frame(height: 1) }
    }

    private var categoryRow: some View {
        HStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: medium ? 24 : 16) {
                    ForEach(categoryTabs, id: \.self) { name in
                        let key = name.lowercased()
                        EmployeeCategoryTile(
                            name: name,
                            imageURL: EmployeeCategoryArt.url(for: key) ?? firstImage(in: key) ?? EmployeeCategoryArt.fallback,
                            isActive: category == key,
                            size: medium ? 64 : 56
                        ) { category = key }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: width * 0.85, alignment: .leading)

            Spacer(minLength: 8)

            Button { category = "all" } label: {
                Text("View all")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1E2939))
                    .underline(color: Color(hex: 0xD1D5DC))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Content

    private func content(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if loaded && filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No designs found.")
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6A7282))
                    Text("Try adjusting your category or feature filters.")
                        .font(.manrope(12))
                        .foregroundStyle(Color(hex: 0x99A1AF))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 64)
                .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: 0xE5E7EB), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            } else if !loaded {
                ProgressView().padding(.top, 64)
            } else {
                let columns = width >= 768 ? 3 : width >= 640 ? 2 : 1
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: columns),
                    spacing: 64
                ) {
                    ForEach(pageItems) { design in
                        DesignsCard(design: design) {
                            withAnimation(.easeOut(duration: 0.25)) { selected = design }
                        }
                    }
                }

                if totalPages > 1 {
                    EmployeePager(page: page, totalPages: totalPages) { next in
                        page = next
                        withAnimation(.smooth) { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
        }
        .frame(maxWidth: 1280)
        .padding(.horizontal, medium ? 32 : 16)
        .padding(.vertical, 32)
    }

    // MARK: - Data

    /// "All" first, then the fixed categories, then any the store used that
    /// aren't among them — de-duplicated ignoring case. "Gold" is never a tile.
    private var categoryTabs: [String] {
        var seen = Set<String>()
        var tabs: [String] = []
        for name in EmployeeCategoryArt.names + designs.compactMap(\.category) {
            let key = name.lowercased()
            guard !name.isEmpty, key != "all", key != "gold", seen.insert(key).inserted else { continue }
            tabs.append(name)
        }
        return tabs
    }

    private func firstImage(in key: String) -> URL? {
        designs.first { ($0.category ?? "uncategorized").lowercased() == key }?.imageLink
    }

    private var filtered: [RetailerDesign] {
        designs.filter { design in
            if category != "all" {
                let own = (design.category ?? "uncategorized").lowercased() == category
                guard own || design.tags.map({ $0.lowercased() }).contains(category) else { return false }
            }
            return filters.matches(size: design.size, purity: design.purity, netWeight: design.netWeight,
                                   inStock: design.isInStock, productionDays: design.productionTimeDays,
                                   tags: design.tags)
        }
    }

    private var totalPages: Int {
        Int((Double(filtered.count) / Double(Self.perPage)).rounded(.up))
    }

    private var pageItems: [RetailerDesign] {
        let start = (page - 1) * Self.perPage
        guard start < filtered.count else { return [] }
        return Array(filtered[start..<min(start + Self.perPage, filtered.count)])
    }

    private func load() async {
        #if DEBUG
        if let peekDesigns = store.peekDesigns {
            designs = peekDesigns
            loaded = true
            return
        }
        #endif
        guard let session = store.session else { return }
        designs = (try? await EmployeeAPI.fetchDesigns(retailerID: session.retailerID, newestFirst: true)) ?? []
        loaded = true
    }
}

/// A square design card. The web uses a plain image here, not the
/// watermarked one; so does this.
private struct DesignsCard: View {
    let design: RetailerDesign
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Color(hex: 0xF4F4F4)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let url = design.imageLink {
                            ProtectedImageView(url: url, contentMode: .scaleAspectFill, multiply: true)
                        } else {
                            Text("No image")
                                .font(.manrope(12, weight: .light))
                                .foregroundStyle(Color(hex: 0xD1D5DC))
                        }
                    }
                    .clipped()

                Text(design.cardTitle)
                    .font(.cirka(15))
                    .kerning(0.375)
                    .foregroundStyle(Color(hex: 0x1E2939))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel(design.cardTitle)
    }
}
