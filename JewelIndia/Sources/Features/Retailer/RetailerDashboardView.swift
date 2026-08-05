import SwiftUI

/// The Retailer Dashboard view (`/dashboard/retailer`).
/// Displays store metrics, quick action cards, the Employee Portal copyable URL card,
/// and employee management shortcuts.
struct RetailerDashboardView: View {
    @Environment(SessionStore.self) private var session
    var onOpenAddEmployee: () -> Void

    @State private var portalURL: String = "https://app.jewelindia.shop/employee-login"
    @State private var isCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Welcome Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Retailer Dashboard")
                        .font(.cirka(32))
                        .foregroundStyle(Palette.foreground)
                    Text("Welcome back! Here's your store overview and management portal.")
                        .font(.manrope(14))
                        .foregroundStyle(Palette.muted)
                }

                // Employee Portal URL Card
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.blue)
                        Text("Employee Portal")
                            .font(.manrope(16, weight: .bold))
                            .foregroundStyle(Palette.foreground)
                    }

                    Text("Share this URL with your store employees so they can access the catalogue.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)

                    HStack {
                        Text(portalURL)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.foreground)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = portalURL
                            isCopied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                isCopied = false
                            }
                        } label: {
                            Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.manrope(12, weight: .bold))
                                .foregroundStyle(isCopied ? Color.green : Color.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1) }
                }
                .padding(Spacing.md)
                .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.2), lineWidth: 1) }

                // Quick Action Grid
                Text("Quick Actions")
                    .font(.cirka(22))
                    .foregroundStyle(Palette.foreground)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                    // Add Employee Card
                    Button(action: onOpenAddEmployee) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.blue)
                            Text("Add Employee")
                                .font(.manrope(14, weight: .bold))
                                .foregroundStyle(Palette.foreground)
                            Text("Create accounts and login credentials for staff.")
                                .font(.manrope(12))
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    // Upload Design Card
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.dark)
                        Text("Upload Design")
                            .font(.manrope(14, weight: .bold))
                            .foregroundStyle(Palette.foreground)
                        Text("Add custom jewellery designs to your store.")
                            .font(.manrope(12))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
            }
            .padding(Spacing.screenGutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}
