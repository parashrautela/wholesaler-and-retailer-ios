import SwiftUI

/// The chat list, shared by every role: a wholesaler's Chat tab, a store
/// owner's Chats, and staff Queries. The server decides which threads the
/// caller sees and what each row may name (`ChatAPI.fetchThreads`).
struct ChatThreadsView: View {
    /// What to say when there is nothing yet — it differs by who is looking.
    var emptyTitle = "No conversations yet"
    var emptyMessage = "Questions about designs will appear here."
    /// Reports whether anything is unread, for a tab's dot.
    var onUnreadChanged: (Bool) -> Void = { _ in }
    /// Store side only: a design someone just asked to chat about. The list
    /// opens — or starts — its thread, then clears this.
    var startAbout: Binding<String?> = .constant(nil)

    @State private var threads: [ChatThread] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var open: ChatThread?
    @State private var startError: String?

    #if DEBUG
    /// Peeks only: rows to show instead of fetching.
    var peekThreads: [ChatThread]?
    #endif

    var body: some View {
        Group {
            if isLoading && threads.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, threads.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load chats", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if threads.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Palette.muted)
                    Text(emptyTitle)
                        .font(.cirka(24))
                        .foregroundStyle(Palette.foreground)
                    Text(emptyMessage)
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(threads) { thread in
                    Button { open = thread } label: { ChatThreadRow(thread: thread) }
                        .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .background(Color.white)
        .task { await load() }
        .task(id: startAbout.wrappedValue) { await startPendingThread() }
        .refreshTask { await load() }
        .alert(startError ?? "", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $open, onDismiss: { Task { await load() } }) { thread in
            NavigationStack {
                ChatThreadView(conversationID: thread.id, title: thread.title, side: thread.side)
            }
        }
    }

    private func startPendingThread() async {
        guard let productID = startAbout.wrappedValue else { return }
        startAbout.wrappedValue = nil
        do {
            let id = try await ChatAPI.open(productID: productID)
            await load()
            open = threads.first { $0.id.lowercased() == id.lowercased() }
                ?? ChatThread(id: id, side: "employee", productID: productID, productTitle: nil)
        } catch {
            startError = error.localizedDescription
        }
    }

    private func load() async {
        #if DEBUG
        if let peekThreads {
            threads = peekThreads
            isLoading = false
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await ChatAPI.fetchThreads()
            errorMessage = nil
            onUnreadChanged(threads.contains { $0.unread > 0 })
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Pull down to try again."
        }
    }
}

private struct ChatThreadRow: View {
    let thread: ChatThread

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Color(hex: 0xF7F7F7)
                if let url = thread.imageURL {
                    CachedImage(url: url)
                } else {
                    Image(systemName: "photo").foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(thread.title)
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    if let when = ChatTime.short(thread.lastAt) {
                        Text(when)
                            .font(.manrope(11))
                            .foregroundStyle(Palette.muted)
                    }
                }
                if let subtitle = thread.subtitle {
                    Text(subtitle)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                HStack {
                    Text(preview)
                        .font(.manrope(13, weight: thread.unread > 0 ? .semibold : .regular))
                        .foregroundStyle(thread.unread > 0 ? Palette.foreground : Palette.muted)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    if thread.unread > 0 {
                        Text("\(thread.unread)")
                            .font(.manrope(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.dark, in: Capsule())
                            .accessibilityLabel("\(thread.unread) unread")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var preview: String {
        guard let last = thread.lastMessage?.trimmed.nilIfEmpty else { return "No messages yet" }
        return thread.lastFrom == thread.side ? "You: \(last)" : last
    }
}

/// Server timestamps are UTC with microseconds; show them in the reader's
/// own time.
enum ChatTime {
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// Time today, otherwise the date.
    static func short(_ raw: String?) -> String? {
        guard let date = date(raw) else { return nil }
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func full(_ raw: String?) -> String? {
        guard let date = date(raw) else { return nil }
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
