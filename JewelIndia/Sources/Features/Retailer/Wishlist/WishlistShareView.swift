import SwiftUI

struct WishlistShareView: View {
    let board: CustomerBoard
    @Environment(\.dismiss) private var dismiss
    @State private var viewers = 1
    @State private var duration = 1440
    @State private var customMinutes = 30
    @State private var created: WishlistShare?
    @State private var shares: [WishlistShare] = []
    @State private var busy = false
    @State private var message: String?
    @State private var isLoadingLinks = true
    @State private var linksNeedRefresh = false
    @State private var creationNotice: String?
    @State private var linkLoadVersion = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("No sign-in needed. Each browser gets one viewing session, lasting up to 30 minutes. Opening the wishlist uses a slot.")
                    Stepper("Maximum viewers: \(viewers)", value: $viewers, in: 1...100)
                    Picker("Link validity", selection: $duration) {
                        Text("1 hour").tag(60)
                        Text("24 hours").tag(1440)
                        Text("7 days").tag(10080)
                        Text("Custom duration").tag(0)
                    }
                    if duration == 0 {
                        TextField("Minutes (5–10,080)", value: $customMinutes, format: .number)
                            .keyboardType(.numberPad)
                    }
                    Text("Shares the designs currently on this board. Customer names, contact details and notes stay private.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(busy ? "Please wait…" : "Create new link") {
                        Task { await create() }
                    }.disabled(busy || board.products.isEmpty || (duration == 0 && !(5...10080).contains(customMinutes)))
                    if let creationNotice { Text(creationNotice).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text(board.title) }

                if let created, let url = created.url {
                    Section("Your link is ready") {
                        ShareLink(item: url) { Label("Share wishlist", systemImage: "square.and.arrow.up") }
                        Button("Copy link") { UIPasteboard.general.url = url; message = "Link copied." }
                        if let expiry = created.expiry {
                            Text("Expires \(expiry.formatted(date: .abbreviated, time: .shortened))")
                        }
                        Text("Copy this link now. It cannot be retrieved later.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let message { Section { Text(message).font(.footnote) } }
                Section("Recent links") {
                    if isLoadingLinks && shares.isEmpty { ProgressView("Loading links…") }
                    else if linksNeedRefresh {
                        Text("Recent links will refresh when your connection is available.").font(.footnote).foregroundStyle(.secondary)
                        Button("Refresh links") { Task { await load() } }.disabled(isLoadingLinks)
                    } else if shares.isEmpty { Text("No links created yet.").foregroundStyle(.secondary) }
                    ForEach(shares) { share in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(share.viewsUsed) / \(share.maxViewers) slots used")
                            if let expiry = share.expiry { Text("Expires \(expiry.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary) }
                            if share.revokedAt != nil { Text("Revoked").font(.footnote) }
                            else if (share.expiry ?? .distantPast) > .now {
                                Button("Revoke link", role: .destructive) { Task { await revoke(share) } }.disabled(busy)
                            } else { Text("Expired").font(.footnote) }
                        }
                    }
                }
            }
            .navigationTitle("Share wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        let version = UUID()
        linkLoadVersion = version
        isLoadingLinks = true
        defer { if linkLoadVersion == version { isLoadingLinks = false } }
        do {
            let fetched = try await WishlistAPI.fetchShares(boardID: board.id)
            guard linkLoadVersion == version else { return }
            shares = fetched
            linksNeedRefresh = false
        } catch {
            guard linkLoadVersion == version, !(error is CancellationError) else { return }
            linksNeedRefresh = true
        }
    }
    private func create() async {
        guard !busy else { return }
        busy = true; message = nil; creationNotice = nil; created = nil
        defer { busy = false }
        do {
            created = try await WishlistAPI.createShare(boardID: board.id, viewers: viewers,
                minutes: duration == 0 ? customMinutes : duration)
            await load()
        } catch { creationNotice = error.localizedDescription }
    }
    private func revoke(_ share: WishlistShare) async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await WishlistAPI.revokeShare(id: share.id)
            if created?.id == share.id { created = nil }
            await load()
            message = "Link revoked. Further access is blocked."
        } catch { message = error.localizedDescription }
    }
}
