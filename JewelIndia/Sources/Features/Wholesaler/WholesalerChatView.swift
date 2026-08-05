import SwiftUI

/// The Wholesaler Chat / Queries view (`/dashboard/wholesaler/queries`).
/// Displays active conversation threads with retailers/employees and real-time messaging.
struct WholesalerChatView: View {
    @Environment(SessionStore.self) private var session

    @State private var conversations: [Conversation] = []
    @State private var selectedConversation: Conversation? = nil
    @State private var messages: [ChatMessage] = []
    @State private var newMessageText: String = ""

    @State private var isLoading = true
    @State private var isLoadingMessages = false
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.dark)
            } else if conversations.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(conversations) { conv in
                        Button {
                            selectedConversation = conv
                            Task { await loadMessages(for: conv) }
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Palette.muted)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Conversation #\(conv.id.prefix(8))")
                                        .font(.manrope(14, weight: .bold))
                                        .foregroundStyle(Palette.foreground)

                                    if let createdAt = conv.createdAt {
                                        Text(createdAt.prefix(10))
                                            .font(.manrope(12))
                                            .foregroundStyle(Palette.muted)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Queries & Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadConversations()
        }
        .sheet(item: $selectedConversation) { conv in
            NavigationStack {
                VStack {
                    if isLoadingMessages {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: Spacing.md) {
                                    ForEach(messages) { msg in
                                        ChatBubbleRow(message: msg)
                                            .id(msg.id)
                                    }
                                }
                                .padding(Spacing.screenGutter)
                            }
                            .onChange(of: messages.count) {
                                if let last = messages.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }

                        Divider()

                        // Input field
                        HStack(spacing: Spacing.sm) {
                            TextField("Type a message...", text: $newMessageText)
                                .font(.manrope(14))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Palette.cream, in: Capsule())

                            Button {
                                Task { await sendMessage() }
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .padding(10)
                                    .background(newMessageText.trimmed.isEmpty ? Palette.muted : Palette.dark, in: Circle())
                            }
                            .disabled(newMessageText.trimmed.isEmpty)
                        }
                        .padding(Spacing.screenGutter)
                    }
                }
                .navigationTitle("Chat #\(conv.id.prefix(8))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { selectedConversation = nil }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No Active Queries")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("When retailers send queries about your products, they will appear here.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Spacing.xl)
    }

    private func loadConversations() async {
        guard let userId = session.user?.id else { return }
        isLoading = true
        do {
            conversations = try await WholesalerAPI.fetchConversations(wholesalerID: userId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadMessages(for conversation: Conversation) async {
        isLoadingMessages = true
        do {
            messages = try await WholesalerAPI.fetchMessages(conversationID: conversation.id)
            try await WholesalerAPI.markMessagesRead(conversationID: conversation.id)
            isLoadingMessages = false
        } catch {
            isLoadingMessages = false
        }
    }

    private func sendMessage() async {
        guard let conv = selectedConversation, !newMessageText.trimmed.isEmpty else { return }
        let text = newMessageText.trimmed
        newMessageText = ""
        do {
            try await WholesalerAPI.sendMessage(conversationID: conv.id, content: text)
            await loadMessages(for: conv)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }
}

// MARK: - Chat Bubble Row

struct ChatBubbleRow: View {
    let message: ChatMessage

    var isFromMe: Bool {
        message.senderType == "wholesaler"
    }

    var body: some View {
        HStack {
            if isFromMe { Spacer() }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                Text(message.content ?? "")
                    .font(.manrope(14))
                    .foregroundStyle(isFromMe ? Color.white : Palette.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isFromMe ? Palette.dark : Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if !isFromMe {
                            RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1)
                        }
                    }

                if let date = message.createdAt {
                    Text(date.prefix(16).replacingOccurrences(of: "T", with: " "))
                        .font(.manrope(10))
                        .foregroundStyle(Palette.muted)
                }
            }

            if !isFromMe { Spacer() }
        }
    }
}
