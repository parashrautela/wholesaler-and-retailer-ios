import SwiftUI

struct ThemeOption: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let colorHex: UInt32
}

/// Retailer Store Theme Picker (`/dashboard/retailer/theme`).
struct StoreThemeView: View {
    @Environment(\.dismiss) private var dismiss

    let themes: [ThemeOption] = [
        .init(id: "celestique", name: "Celestique Classic", description: "Timeless cream & dark gold aesthetic", colorHex: 0x2E2833),
        .init(id: "royal_gold", name: "Royal Gold", description: "Rich imperial yellow gold theme", colorHex: 0xD4AF37),
        .init(id: "minimal_slate", name: "Minimal Slate", description: "Clean modern monochrome theme", colorHex: 0x1F2937)
    ]

    @State private var selectedThemeID: String = "celestique"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Store Theme")
                        .font(.cirka(28))
                        .foregroundStyle(Palette.foreground)
                    Text("Select the store theme that best reflects your brand identity.")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)
                }

                VStack(spacing: Spacing.md) {
                    ForEach(themes) { theme in
                        ThemeOptionRow(
                            theme: theme,
                            isSelected: selectedThemeID == theme.id,
                            onSelect: { selectedThemeID = theme.id }
                        )
                    }
                }

                Spacer()

                Button("Save Theme") {
                    dismiss()
                }
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Palette.dark, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(Spacing.screenGutter)
            .navigationTitle("Store Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct ThemeOptionRow: View {
    let theme: ThemeOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(Color(hex: theme.colorHex))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.manrope(14, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                    Text(theme.description)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.dark)
                }
            }
            .padding(Spacing.md)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Palette.dark : Palette.border, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
