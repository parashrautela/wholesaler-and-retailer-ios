import SwiftUI

public struct TransactionHistoryView: View {
    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case spent = "Spent"
        case added = "Added"
        case expired = "Expired"

        var id: String { rawValue }
    }

    @State private var entries: [CreditLedgerEntry] = []
    @State private var selectedFilter: FilterCategory = .all
    @State private var isLoading: Bool = false
    @State private var hasMore: Bool = true
    @State private var isInitialLoad: Bool = true

    public init() {}

    private var filteredEntries: [CreditLedgerEntry] {
        switch selectedFilter {
        case .all:
            return entries
        case .spent:
            return entries.filter { $0.delta < 0 && $0.kind != "expiry" }
        case .added:
            return entries.filter { $0.delta > 0 }
        case .expired:
            return entries.filter { $0.kind == "expiry" }
        }
    }

    private var groupedEntries: [(dateHeader: String, items: [CreditLedgerEntry])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let dict = Dictionary(grouping: filteredEntries) { entry -> String in
            guard let date = entry.date else { return "Earlier" }
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else {
                return formatter.string(from: date)
            }
        }

        // Maintain date order
        var seenHeaders: [String] = []
        var result: [(dateHeader: String, items: [CreditLedgerEntry])] = []

        for entry in filteredEntries {
            let header: String
            if let date = entry.date {
                if calendar.isDateInToday(date) {
                    header = "Today"
                } else if calendar.isDateInYesterday(date) {
                    header = "Yesterday"
                } else {
                    header = formatter.string(from: date)
                }
            } else {
                header = "Earlier"
            }

            if !seenHeaders.contains(header) {
                seenHeaders.append(header)
                if let items = dict[header] {
                    result.append((dateHeader: header, items: items))
                }
            }
        }

        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar

            if isInitialLoad && isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if filteredEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                        ForEach(groupedEntries, id: \.dateHeader) { group in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(group.dateHeader)
                                    .font(.manrope(12, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .padding(.horizontal, Spacing.base)
                                    .padding(.top, Spacing.xs)

                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                        entryRow(item)
                                        if index < group.items.count - 1 {
                                            Divider()
                                                .padding(.leading, 48)
                                        }
                                    }
                                }
                                .background(Color.white, in: .rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Palette.border, lineWidth: 1)
                                }
                                .padding(.horizontal, Spacing.base)
                            }
                        }

                        if hasMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .onAppear {
                                        Task { await loadMore() }
                                    }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.md)
                        }
                    }
                    .padding(.vertical, Spacing.base)
                }
                .refreshable {
                    await reload()
                }
            }
        }
        .background(Color(hex: 0xFAFAFA))
        .navigationTitle("Transaction History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isInitialLoad {
                await reload()
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCategory.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.manrope(13, weight: selectedFilter == filter ? .bold : .medium))
                            .foregroundStyle(selectedFilter == filter ? Palette.cream : Palette.dark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedFilter == filter ? Palette.dark : Color.white,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(selectedFilter == filter ? Color.clear : Palette.border, lineWidth: 1)
                            }
                    }
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Row

    private func entryRow(_ entry: CreditLedgerEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.delta > 0 ? Color(hex: 0xECFDF5) : Color(hex: 0xF3F4F6))
                    .frame(width: 36, height: 36)

                Image(systemName: entry.delta > 0 ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(entry.delta > 0 ? Color(hex: 0x059669) : Palette.dark)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.dark)

                HStack(spacing: 6) {
                    if let date = entry.date {
                        Text(timeString(from: date))
                            .font(.sfPro(12))
                            .foregroundStyle(Palette.muted)
                    }

                    Text("•")
                        .font(.sfPro(10))
                        .foregroundStyle(Palette.muted)

                    Text("Bal: \(entry.balanceAfter)")
                        .font(.sfPro(12))
                        .foregroundStyle(Palette.muted)
                }
            }

            Spacer()

            Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(entry.delta > 0 ? Color(hex: 0x059669) : Palette.dark)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Palette.muted)

            Text("No activity yet")
                .font(.cirka(20, weight: .bold))
                .foregroundStyle(Palette.dark)

            Text("Your credits activity and transactions will appear here as you use them.")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Data Fetching

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
            isInitialLoad = false
        }

        do {
            let fetched = try await CreditsAPI.fetchLedger(limit: 50)
            entries = fetched
            hasMore = fetched.count >= 50
        } catch {
            entries = []
            hasMore = false
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore, let lastEntry = entries.last, let lastDate = lastEntry.date else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let nextBatch = try await CreditsAPI.fetchLedger(limit: 50, before: lastDate)
            if nextBatch.isEmpty {
                hasMore = false
            } else {
                entries.append(contentsOf: nextBatch)
                hasMore = nextBatch.count >= 50
            }
        } catch {
            hasMore = false
        }
    }
}
