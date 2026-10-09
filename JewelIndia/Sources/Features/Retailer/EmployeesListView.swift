import SwiftUI

/// The store's staff (`/dashboard/retailer/employees`): who can sign in,
/// how, and whether they still can. Every change goes through the
/// staff-accounts service; the list itself is the store's own `employees`
/// rows.
struct EmployeesListView: View {
    var onOpenAddEmployee: () -> Void

    @State private var staff: [StaffMember] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyID: String?
    @State private var confirmRemove: StaffMember?
    @State private var confirmReset: StaffMember?
    @State private var credentials: StaffCredentials?
    @State private var notice: String?

    #if DEBUG
    /// Peeks only: rows to show instead of fetching.
    var peekRows: [StaffMember]?
    #endif

    var body: some View {
        content
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Staff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenAddEmployee) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }
                    .accessibilityLabel("Add staff")
                }
            }
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: StaffAccountsAPI.changed)) { _ in
                Task { await load() }
            }
            .confirmationDialog(removeTitle, isPresented: removeShown, titleVisibility: .visible) {
                removeButtons
            } message: {
                if let member = confirmRemove, member.status != .invited {
                    Text("Their login stops working straight away. This can't be undone.")
                }
            }
            .confirmationDialog(resetTitle, isPresented: resetShown, titleVisibility: .visible) {
                resetButtons
            } message: {
                Text("Their old password stops working. You'll see the new one once, to pass on.")
            }
            .sheet(item: $credentials) { creds in
                StaffCredentialsView(member: creds.member, password: creds.password) { credentials = nil }
            }
            .alert(notice ?? "", isPresented: noticeShown) {
                Button("OK", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && staff.isEmpty {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.dark)
        } else if let error = errorMessage, staff.isEmpty {
            VStack(spacing: Spacing.md) {
                Text(error)
                    .font(.manrope(14))
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await load() } }
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.dark)
            }
            .padding(Spacing.xl)
        } else if staff.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(staff) { member in
                    StaffRow(member: member, busy: busyID == member.id)
                        .contextMenu { actions(for: member) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { confirmRemove = member } label: {
                                Label(member.status == .invited ? "Cancel" : "Remove", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("Staff sign in on the Jewels India app under “I work at a store”. Passwords are shown once when you create or reset them.")
                    .font(.manrope(12))
            }
        }
        .listStyle(.insetGrouped)
        .refreshTask { await load() }
    }

    // MARK: - Dialogs

    private var removeShown: Binding<Bool> {
        Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })
    }

    private var resetShown: Binding<Bool> {
        Binding(get: { confirmReset != nil }, set: { if !$0 { confirmReset = nil } })
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private var removeTitle: String {
        guard let member = confirmRemove else { return "" }
        return member.status == .invited ? "Cancel \(member.fullName)'s invitation?" : "Remove \(member.fullName)?"
    }

    private var resetTitle: String {
        confirmReset.map { "Reset \($0.fullName)'s password?" } ?? ""
    }

    @ViewBuilder
    private var removeButtons: some View {
        if let member = confirmRemove {
            Button(member.status == .invited ? "Cancel invitation" : "Remove from staff", role: .destructive) {
                Task { await remove(member) }
            }
        }
        Button("Keep", role: .cancel) {}
    }

    @ViewBuilder
    private var resetButtons: some View {
        if let member = confirmReset {
            Button("Reset password") { Task { await resetPassword(member) } }
        }
        Button("Keep the current one", role: .cancel) {}
    }

    @ViewBuilder
    private func actions(for member: StaffMember) -> some View {
        switch member.status {
        case .invited:
            Button(role: .destructive) { confirmRemove = member } label: {
                Label("Cancel invitation", systemImage: "envelope.badge.shield.half.filled")
            }
        case .active, .inactive:
            if !member.signsInWithGoogle {
                Button { confirmReset = member } label: {
                    Label("Reset password", systemImage: "key")
                }
            }
            Button { Task { await setActive(member, member.status != .active) } } label: {
                Label(member.status == .active ? "Deactivate" : "Reactivate",
                      systemImage: member.status == .active ? "pause.circle" : "play.circle")
            }
            Button(role: .destructive) { confirmRemove = member } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No staff yet")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("Create a login for each person at your store, or invite them by their Google address.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)

            Button("Add staff", action: onOpenAddEmployee)
                .buttonStyle(.plain)
                .font(.manrope(14, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Palette.dark, in: Capsule())
            Spacer()
        }
        .padding(Spacing.xl)
    }

    // MARK: - Data

    private func load() async {
        #if DEBUG
        if let peekRows {
            staff = peekRows
            isLoading = false
            return
        }
        #endif
        isLoading = true
        errorMessage = nil
        do {
            staff = try await StaffAccountsAPI.fetchStaff()
            isLoading = false
        } catch {
            isLoading = false
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Couldn't load your staff. Check your connection and try again."
        }
    }

    private func setActive(_ member: StaffMember, _ active: Bool) async {
        busyID = member.id
        defer { busyID = nil }
        do {
            let updated = try await StaffAccountsAPI.setActive(member.id, active)
            replace(updated)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func resetPassword(_ member: StaffMember) async {
        busyID = member.id
        defer { busyID = nil }
        do {
            let result = try await StaffAccountsAPI.resetPassword(member.id)
            credentials = StaffCredentials(member: result.member, password: result.password)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func remove(_ member: StaffMember) async {
        busyID = member.id
        defer { busyID = nil }
        do {
            try await StaffAccountsAPI.remove(member)
            staff.removeAll { $0.id == member.id }
        } catch {
            notice = error.localizedDescription
        }
    }

    private func replace(_ member: StaffMember) {
        if let index = staff.firstIndex(where: { $0.id == member.id }) {
            staff[index] = member
        }
    }
}

struct StaffCredentials: Identifiable {
    let member: StaffMember
    let password: String
    var id: String { member.id }
}

private struct StaffRow: View {
    let member: StaffMember
    let busy: Bool

    private var initials: String {
        let parts = member.fullName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(initials.isEmpty ? "?" : initials)
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Palette.dark)
                .frame(width: 40, height: 40)
                .background(Palette.cream, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(member.fullName)
                    .font(.manrope(14, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                if let designation = member.designation?.trimmed.nilIfEmpty {
                    Text(designation)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }
                HStack(spacing: 4) {
                    Image(systemName: member.signsInWithGoogle ? "g.circle" : "person.text.rectangle")
                        .font(.system(size: 10))
                    Text(member.signInLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.manrope(11))
                .foregroundStyle(Palette.muted)
            }

            Spacer()

            if busy {
                ProgressView().controlSize(.small)
            } else {
                StatusChip(status: member.status)
            }
        }
        .padding(.vertical, 4)
        .opacity(member.status == .inactive ? 0.6 : 1)
    }
}

private struct StatusChip: View {
    let status: StaffMember.Status

    private var label: String {
        switch status {
        case .active: "Active"
        case .inactive: "Off"
        case .invited: "Invited"
        }
    }

    private var color: Color {
        switch status {
        case .active: Color(hex: 0x15803D)
        case .inactive: Color(hex: 0x6B7280)
        case .invited: Color(hex: 0xB45309)
        }
    }

    var body: some View {
        Text(label)
            .font(.manrope(10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

/// The one time a password is visible: right after it is made.
struct StaffCredentialsView: View {
    let member: StaffMember
    let password: String
    let onDone: () -> Void

    @State private var copied: String?

    private var username: String { member.username ?? member.email }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share these with \(member.fullName.split(separator: " ").first.map(String.init) ?? member.fullName)")
                        .font(.cirka(24))
                        .foregroundStyle(Palette.foreground)
                    Text("They sign in on the Jewels India app under “I work at a store”.")
                        .font(.manrope(13))
                        .foregroundStyle(Palette.muted)
                }

                credential("USERNAME", value: username, key: "username")
                credential("PASSWORD", value: password, key: "password", monospaced: true)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color(hex: 0xB45309))
                    Text("This password is shown once and isn't stored anywhere. If it gets lost, reset it from your staff list.")
                        .font(.manrope(12))
                        .foregroundStyle(Color(hex: 0x92400E))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(hex: 0xFEF3C7), in: .rect(cornerRadius: 10))

                Button {
                    UIPasteboard.general.string = "Jewels India staff login\nUsername: \(username)\nPassword: \(password)\nSign in on the Jewels India app → I work at a store"
                    flash("both")
                } label: {
                    Label(copied == "both" ? "Copied" : "Copy both", systemImage: copied == "both" ? "checkmark" : "doc.on.doc")
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(Spacing.screenGutter)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Login created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func credential(_ label: String, value: String, key: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Palette.muted)
            HStack {
                Text(value)
                    .font(monospaced ? .system(size: 16, weight: .medium, design: .monospaced) : .manrope(15, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                    flash(key)
                } label: {
                    Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(copied == key ? Color.green : Palette.dark)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(label.lowercased())")
            }
            .padding(12)
            .background(Color.white, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1) }
        }
    }

    private func flash(_ key: String) {
        copied = key
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == key { copied = nil }
        }
    }
}
