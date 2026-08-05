import SwiftUI

/// Add Employee sheet (`/dashboard/retailer?modal=add-employee`).
/// 2-step modal:
/// Step 1: Employee Name, 10-digit Indian Mobile Number, Email, Designation.
/// Step 2: Auto-generated login email confirmation, set password, confirm password, and save.
struct AddEmployeeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    @State private var step: Int = 1
    @State private var fullName: String = ""
    @State private var mobileNumber: String = ""
    @State private var email: String = ""
    @State private var designation: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                if let error = errorMessage {
                    Text(error)
                        .font(.manrope(13))
                        .foregroundStyle(Color.red)
                        .padding(10)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                if step == 1 {
                    step1Form
                } else {
                    step2Form
                }

                Spacer()

                Button {
                    if step == 1 {
                        validateAndNext()
                    } else {
                        Task { await createEmployee() }
                    }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(step == 1 ? "Set Password →" : "Create Employee Account")
                                .font(.manrope(15, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSubmitting)
            }
            .padding(Spacing.screenGutter)
            .navigationTitle(step == 1 ? "Add New Employee" : "Set Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var step1Form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EMPLOYEE NAME*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("Eg. Parash Rautela", text: $fullName)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MOBILE NO*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("9834874396", text: $mobileNumber)
                    .keyboardType(.numberPad)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("EMAIL ID*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("Parashe@gmail.com", text: $email)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DESIGNATION*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                TextField("Sales Manager", text: $designation)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var step2Form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LOGIN EMAIL")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                Text(email)
                    .font(.manrope(14, weight: .bold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SET PASSWORD*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                SecureField("Enter password", text: $password)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("CONFIRM PASSWORD*")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                SecureField("Confirm password", text: $confirmPassword)
                    .font(.manrope(14))
                    .padding(12)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func validateAndNext() {
        errorMessage = nil
        guard !fullName.trimmed.isEmpty, !mobileNumber.trimmed.isEmpty, !email.trimmed.isEmpty, !designation.trimmed.isEmpty else {
            errorMessage = "Please fill all fields."
            return
        }
        guard mobileNumber.trimmed.count == 10 else {
            errorMessage = "Please enter a valid 10-digit Indian mobile number."
            return
        }
        step = 2
    }

    private func createEmployee() async {
        errorMessage = nil
        guard !password.isEmpty, password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        guard let user = session.user else { return }

        isSubmitting = true
        do {
            struct EmployeeInsert: Encodable {
                let retailer_id: String
                let full_name: String
                let email: String
                let mobile_number: String
                let designation: String
                let status: String
            }
            let payload = EmployeeInsert(
                retailer_id: user.id.uuidString,
                full_name: fullName.trimmed,
                email: email.trimmed,
                mobile_number: mobileNumber.trimmed,
                designation: designation.trimmed,
                status: "active"
            )
            _ = try await SupabaseManager.client.from("employees").insert(payload).execute()
            dismiss()
        } catch {
            errorMessage = "Failed to create employee: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}
