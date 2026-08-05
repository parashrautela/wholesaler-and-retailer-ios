import SwiftUI

struct EmployeeRowModel: Decodable, Identifiable, Sendable {
    let id: String
    let fullName: String?
    let email: String?
    let mobileNumber: String?
    let designation: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case mobileNumber = "mobile_number"
        case designation
        case status
    }
}

/// Employees Directory view (`/dashboard/retailer/employees`).
/// List of employees, status toggles (active/deactivated), and Add Employee trigger.
struct EmployeesListView: View {
    @Environment(SessionStore.self) private var session
    var onOpenAddEmployee: () -> Void

    @State private var employees: [EmployeeRowModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.dark)
            } else if let error = errorMessage {
                VStack(spacing: Spacing.md) {
                    Text(error)
                        .font(.manrope(14))
                        .foregroundStyle(Color.red)
                    Button("Retry") {
                        Task { await loadEmployees() }
                    }
                }
            } else if employees.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(employees) { emp in
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Palette.muted)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(emp.fullName ?? "Employee")
                                    .font(.manrope(14, weight: .bold))
                                    .foregroundStyle(Palette.foreground)

                                Text(emp.designation ?? "Staff")
                                    .font(.manrope(12))
                                    .foregroundStyle(Palette.muted)

                                if let email = emp.email {
                                    Text(email)
                                        .font(.manrope(11))
                                        .foregroundStyle(Palette.muted)
                                }
                            }

                            Spacer()

                            Text(emp.status?.capitalized ?? "Active")
                                .font(.manrope(10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(emp.status == "active" ? Color.green.opacity(0.15) : Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(emp.status == "active" ? Color.green : Color.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await loadEmployees()
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Employees")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenAddEmployee()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.dark)
                }
            }
        }
        .task {
            await loadEmployees()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(Palette.muted)
            Text("No Employees Added")
                .font(.cirka(24))
                .foregroundStyle(Palette.foreground)
            Text("Click below to create your first employee account.")
                .font(.manrope(14))
                .foregroundStyle(Palette.muted)

            Button("Add New Employee", action: onOpenAddEmployee)
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

    private func loadEmployees() async {
        guard let userId = session.user?.id else { return }
        isLoading = true
        do {
            let rows: [EmployeeRowModel] = try await SupabaseManager.client.from("employees")
                .select()
                .eq("retailer_id", value: userId.uuidString)
                .execute()
                .value
            employees = rows
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
