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
    @State private var isAtBottom = true
    @State private var unseenMessageCount = 0
    @State private var scrollTarget: String?
    @State private var reportTarget: ChatMessage?
    @State private var reportSent = false
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
                                ChatBubble(
                                    message: message,
                                    isMine: message.senderType == side,
                                    onReport: { reportTarget = $0 }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(Spacing.screenGutter)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { scrollToEnd(proxy, animated: false) }
                    .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                        max(0, geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y + geometry.contentInsets.bottom)
                    }) { _, distanceFromBottom in
                        isAtBottom = distanceFromBottom < 72
                        if isAtBottom { unseenMessageCount = 0 }
                    }
                    .onChange(of: scrollTarget) {
                        guard let scrollTarget else { return }
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(scrollTarget, anchor: .bottom)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if unseenMessageCount > 0 {
                            Button {
                                unseenMessageCount = 0
                                scrollTarget = messages.last?.id
                            } label: {
                                Label("\(unseenMessageCount) new \(unseenMessageCount == 1 ? "message" : "messages")", systemImage: "arrow.down")
                                    .font(.manrope(12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Palette.dark, in: Capsule())
                                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Jump to latest message")
                            .padding(.bottom, Spacing.sm)
                        }
                    }
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let latestIncomingMessage {
                        Button(role: .destructive) {
                            reportTarget = latestIncomingMessage
                        } label: {
                            Label("Report latest message", systemImage: "flag")
                        }
                    } else {
                        Text("No message to report yet")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.dark)
                }
                .accessibilityLabel("Conversation options")
            }
        }
        .task { await watch() }
        .sheet(item: $reportTarget) { message in
            ReportChatMessageSheet(message: message) { submission in
                try await ChatAPI.report(
                    conversationID: conversationID,
                    messageID: message.id,
                    reason: submission.reason,
                    details: submission.details
                )
            } onReported: {
                reportSent = true
            }
        }
        .alert("Report received", isPresented: $reportSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thanks for letting us know. Our team will review this message.")
        }
    }

    private var latestIncomingMessage: ChatMessage? {
        messages.last { $0.senderType != side }
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
        scrollTarget = last.id
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
            if fetched.map(\.id) != messages.map(\.id) {
                let wasAtBottom = isAtBottom
                let previousCount = messages.count
                messages = fetched
                if wasAtBottom {
                    unseenMessageCount = 0
                    scrollTarget = fetched.last?.id
                } else {
                    unseenMessageCount += max(1, fetched.count - previousCount)
                }
            }
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
            unseenMessageCount = 0
            scrollTarget = messages.last?.id
        } catch {
            // The draft stays in the box so nothing typed is lost.
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let onReport: (ChatMessage) -> Void

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
        .contextMenu {
            if !isMine {
                Button(role: .destructive) {
                    onReport(message)
                } label: {
                    Label("Report message", systemImage: "flag")
                }
            }
        }
    }
}

private struct ReportChatMessageSheet: View {
    private enum Reason: String, CaseIterable, Identifiable {
        case spam
        case harassment
        case inappropriate
        case scam
        case other

        var id: String { rawValue }
        var title: String {
            switch self {
            case .spam: "Spam or unwanted solicitation"
            case .harassment: "Harassment or abusive language"
            case .inappropriate: "Inappropriate content"
            case .scam: "Fraud or misleading activity"
            case .other: "Something else"
            }
        }
    }

    struct Submission {
        let reason: String
        let details: String
    }

    let message: ChatMessage
    let submit: (Submission) async throws -> Void
    let onReported: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason = .spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    Text(message.content?.trimmed.nilIfEmpty ?? "Message unavailable")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(5)
                }

                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(Reason.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    TextField("Additional details (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.manrope(13))
                            .foregroundStyle(Palette.statusRejected)
                    }
                }

                Section {
                    Text("Reports are reviewed by the Jewel India team.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Report message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Sending…" : "Submit") {
                        Task { await sendReport() }
                    }
                    .disabled(isSubmitting)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sendReport() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await submit(Submission(reason: reason.rawValue, details: details.trimmed))
            onReported()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
