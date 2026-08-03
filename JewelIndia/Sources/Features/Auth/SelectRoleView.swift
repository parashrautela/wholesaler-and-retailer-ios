import SwiftUI

/// `/select-role` — `components/auth/SelectRoleForm.jsx`.
///
/// The only auth screen that does **not** use `AuthLayout`: it is styled
/// entirely with the celestique `@theme` tokens, so it looks like the rest of
/// the product rather than like the sign-in flow.
struct SelectRoleView: View {
    @Environment(SessionStore.self) private var session

    @State private var selected: UserRole?
    @State private var error: String?
    @State private var loading = false

    private var email: String {
        session.user?.email ?? session.user?.phone ?? ""
    }

    var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    gemMark
                        .padding(.bottom, 32)

                    VStack(spacing: 0) {
                        header
                        Rectangle()
                            .fill(Palette.taupe)
                            .frame(height: Stroke.hairline)
                        body_
                    }
                    .background(Palette.cream)
                    .overlay { Rectangle().stroke(Palette.taupe, lineWidth: Stroke.hairline) }

                    Text(Copy.selectRoleSignedInAs(email))
                        .font(.system(size: 9))
                        .tracking(9 * 0.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.dark.opacity(0.4))
                        .padding(.top, 24)
                }
                .frame(maxWidth: 448)   // max-w-md
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// A 16×16 bordered square holding the 8×8 gem path
    /// `M6.5 2h11l4 6-9.5 14L2.5 8l4-6z`.
    private var gemMark: some View {
        Rectangle()
            .stroke(Palette.dark, lineWidth: Stroke.hairline)
            .frame(width: 64, height: 64)
            .overlay {
                GemShape()
                    .stroke(Palette.dark, lineWidth: 1.5)
                    .frame(width: 32, height: 32)
            }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(Copy.selectRoleHeading)
                .font(.cirka(30))
                .foregroundStyle(Palette.dark)
                .multilineTextAlignment(.center)

            Text(Copy.selectRoleSub)
                .font(.system(size: 10))
                .tracking(10 * 0.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.dark.opacity(0.6))
                .multilineTextAlignment(.center)

            Text(Copy.selectRoleSub2)
                .font(.system(size: 9))
                .tracking(9 * 0.1)
                .foregroundStyle(Palette.dark.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }

    private var body_: some View {
        VStack(spacing: 16) {
            roleCard(
                .wholesaler,
                title: Copy.selectRoleWholesalerTitle,
                detail: Copy.selectRoleWholesalerBody,
                symbol: "briefcase"
            )
            roleCard(
                .retailer,
                title: Copy.selectRoleRetailerTitle,
                detail: Copy.selectRoleRetailerBody,
                symbol: "bag"
            )

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .tracking(10 * 0.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0x991B1B))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0xFEF2F2))
                    .overlay { Rectangle().stroke(Color(hex: 0xFECACA), lineWidth: 1) }
            }

            CelestiqueButton(
                title: Copy.selectRoleButton,
                isLoading: loading,
                isEnabled: selected != nil && !loading
            ) {
                Task { await submit() }
            }
        }
        .padding(32)
    }

    private func roleCard(
        _ role: UserRole,
        title: String,
        detail: String,
        symbol: String
    ) -> some View {
        let isSelected = selected == role
        return Button {
            selected = role
            if error != nil { error = nil }
        } label: {
            HStack(alignment: .top, spacing: 24) {
                // A square radio, not a round one.
                Rectangle()
                    .stroke(isSelected ? Palette.dark : Palette.taupe, lineWidth: 1)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isSelected {
                            Rectangle()
                                .fill(Palette.cream)
                                .frame(width: 6, height: 6)
                                .background(Palette.dark)
                        }
                    }
                    .background(isSelected ? Palette.dark : .clear)
                    .padding(.top, 2)

                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Palette.dark)
                    .frame(width: 24, height: 24)
                    .padding(12)
                    .overlay { Rectangle().stroke(Palette.taupe, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.cirka(18))
                        .foregroundStyle(Palette.dark)
                    Text(detail)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(isSelected ? Palette.taupe.opacity(0.1) : .clear)
            .overlay {
                Rectangle()
                    .stroke(isSelected ? Palette.dark : Palette.taupe, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: isSelected)
    }

    private func submit() async {
        guard let selected else {
            error = Copy.selectRoleEmpty
            return
        }
        loading = true
        error = nil
        if let message = await session.setUserRole(selected) {
            error = message
        }
        loading = false
    }
}

/// `components/ui/Button.jsx` — the celestique primary button. While loading
/// the label goes invisible and a ring spinner overlays it.
struct CelestiqueButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    @State private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(11 * 0.1)   // tracking-widest
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.cream)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Palette.taupe, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                spin = true
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Palette.dark)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// `M6.5 2h11l4 6-9.5 14L2.5 8l4-6z` on a 24×24 viewBox.
struct GemShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.move(to: CGPoint(x: 6.5 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 17.5 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 21.5 * s, y: 8 * s))
        p.addLine(to: CGPoint(x: 12 * s, y: 22 * s))
        p.addLine(to: CGPoint(x: 2.5 * s, y: 8 * s))
        p.addLine(to: CGPoint(x: 6.5 * s, y: 2 * s))
        p.closeSubpath()
        return p
    }
}
