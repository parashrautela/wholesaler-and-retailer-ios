import SwiftUI

struct ChamakFeedbackSheet: View {
    @Bindable var vm: ChamakViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("How satisfied are you with this Chamak fusion?")
                    .font(.cirka(20, weight: .bold))
                    .foregroundStyle(Palette.dark)

                // Satisfaction buttons
                HStack(spacing: Spacing.md) {
                    Button {
                        vm.feedbackSatisfied = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.thumbsup.fill")
                            Text("Satisfied")
                        }
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(vm.feedbackSatisfied ? Color.white : Palette.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            vm.feedbackSatisfied ? Color(hex: 0x16A34A) : Color(hex: 0xF3F4F6),
                            in: .rect(cornerRadius: 10)
                        )
                    }

                    Button {
                        vm.feedbackSatisfied = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.thumbsdown.fill")
                            Text("Needs Work")
                        }
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(!vm.feedbackSatisfied ? Color.white : Palette.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            !vm.feedbackSatisfied ? Color(hex: 0xDC2626) : Color(hex: 0xF3F4F6),
                            in: .rect(cornerRadius: 10)
                        )
                    }
                }

                // Feedback Text
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.feedbackSatisfied ? "What did you like most? (Optional)" : "What went wrong with the fusion?")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(Palette.dark)

                    TextField(
                        "Provide details so we can tune future design prompt compilations...",
                        text: $vm.feedbackText,
                        axis: .vertical
                    )
                    .lineLimit(4...6)
                    .font(.manrope(13))
                    .padding(Spacing.md)
                    .background(Color(hex: 0xF9FAFB), in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                    }
                }

                Spacer()

                Button {
                    Task {
                        await vm.submitFeedback()
                        dismiss()
                    }
                } label: {
                    Text("Submit Feedback")
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: .rect(cornerRadius: 10))
                }
            }
            .padding(Spacing.xl)
            .navigationTitle("Chamak Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
