import SwiftUI

/// One conversation. `side` is which side the reader is on (`wholesaler`, or
/// `employee` for the store), which is all that decides whose bubbles sit on
/// the right.
struct ChatThreadView: View {
    let conversationID: String
    let title: String
    let side: String

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var composerFocused: Bool

    #if DEBUG
    /// Peeks only: messages to show instead of fetching.
    var peekMessages: [ChatMessage]?
    #endif

    /// How often an open thread checks for replies.
    private static let pollInterval: Duration = .seconds(4)

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && messages.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if messages.isEmpty {
                Spacer()
                Text(errorMessage ?? "Say hello — ask about availability, purity or delivery.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(Spacing.xl)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(messages) { message in
                                ChatBubble(message: message, isMine: message.senderType == side)
                                    .id(message.id)
                            }
                        }
                        .padding(Spacing.screenGutter)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { scrollToEnd(proxy, animated: false) }
                    .onChange(of: messages.count) { scrollToEnd(proxy, animated: true) }
                }
            }

            if let errorMessage, !messages.isEmpty {
                Text(errorMessage)
                    .font(.manrope(12))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, Spacing.screenGutter)
                    .padding(.bottom, 4)
            }

            Divider()
            composer
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task { await watch() }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Type a message…", text: $draft, axis: .vertical)
                .font(.manrope(14))
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(Palette.border, lineWidth: 1) }

            Button {
                Task { await send() }
            } label: {
                Group {
                    if isSending {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(canSend ? Palette.dark : Palette.muted, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Spacing.screenGutter)
        .padding(.vertical, Spacing.sm)
        .background(Palette.background)
    }

    private var canSend: Bool { !draft.trimmed.isEmpty && !isSending }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    /// Loads, then keeps checking while the thread is on screen. The task is
    /// cancelled with the view, which ends the loop.
    private func watch() async {
        #if DEBUG
        if let peekMessages {
            messages = peekMessages
            isLoading = false
            return
        }
        #endif
        await refresh()
        isLoading = false
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { break }
            await refresh()
        }
    }

    private func refresh() async {
        do {
            let fetched = try await ChatAPI.fetchMessages(conversationID: conversationID)
            if fetched.map(\.id) != messages.map(\.id) { messages = fetched }
            if fetched.contains(where: { $0.senderType != side && $0.isRead != true }) {
                await ChatAPI.markRead(conversationID: conversationID)
            }
            if !isSending { errorMessage = nil }
        } catch {
            if error is CancellationError { return }
            if messages.isEmpty { errorMessage = "Couldn't load this conversation." }
        }
    }

    private func send() async {
        let text = draft.trimmed
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await ChatAPI.send(conversationID: conversationID, content: text)
            draft = ""
            errorMessage = nil
            await refresh()
        } catch {
            // The draft stays in the box so nothing typed is lost.
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(message.content ?? "")
                    .font(.manrope(14))
                    .foregroundStyle(isMine ? Color.white : Palette.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isMine ? Palette.dark : Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if !isMine {
                            RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1)
                        }
                    }

                if let when = ChatTime.full(message.createdAt) {
                    Text(when)
                        .font(.manrope(10))
                        .foregroundStyle(Palette.muted)
                }
            }

            if !isMine { Spacer(minLength: 48) }
        }
    }
}
