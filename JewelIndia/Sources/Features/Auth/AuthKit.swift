import SwiftUI

/// Shared auth chrome and controls, built to the exact measurements in
/// `components/auth/AuthLayout.jsx` and the individual auth forms.
///
/// The web forms are styled inline rather than through the Tailwind theme, and
/// the numbers differ from screen to screen (the entry screen uses 52 pt inputs
/// with `#D9D0C5` borders; sign-in uses 48 pt with `#E5E7EB`). Those differences
/// are real, so the components below take their metrics as parameters instead
/// of averaging them into one house style.

/// Tailwind's responsive breakpoints, so layout decisions can be keyed off the
/// same numbers the web uses.
///
/// These compare against real width rather than size class, so an iPad in a
/// narrow Split View collapses to the phone layout exactly as a narrow browser
/// window does.
enum Breakpoint {
    static let sm: CGFloat = 640
    static let md: CGFloat = 768
    static let lg: CGFloat = 1024
    static let xl: CGFloat = 1280
}

// MARK: - Palette local to the auth flow

/// Hex values that appear only in the auth screens' inline styles and are not
/// part of the celestique `@theme` block.
enum AuthColor {
    static let brandSquare = Color(hex: 0x6B4F4F)
    static let ink = Color(hex: 0x111111)
    static let subheading = Color(hex: 0x4B5563)
    static let labelDark = Color(hex: 0x333333)
    static let fieldBorder = Color(hex: 0xD9D0C5)
    static let fieldFill = Color(hex: 0xFAFAFA)
    static let hairline = Color(hex: 0xE0E0E0)
    static let dividerText = Color(hex: 0x999999)
    static let buttonEnabled = Color(hex: 0x1A1A1A)
    static let buttonDisabled = Color(hex: 0xBBBBBB)
    static let errorDot = Color(hex: 0xEF4444)
    static let errorText = Color(hex: 0xDC2626)

    // Sign-in / OTP / set-password family
    static let slate = Color(hex: 0x1F2937)
    static let slateHover = Color(hex: 0x111827)
    static let border2 = Color(hex: 0xE5E7EB)
    static let fill2 = Color(hex: 0xF9FAFB)
    static let text2 = Color(hex: 0x111827)
    static let placeholder = Color(hex: 0x9CA3AF)
    static let muted2 = Color(hex: 0x6B7280)
    static let focusBorder = Color(hex: 0x374151)
    static let otpBorder = Color(hex: 0xD1D5DB)
    static let rulePass = Color(hex: 0x16A34A)
}

// MARK: - Layout shell

/// `components/auth/AuthLayout.jsx`.
///
/// The responsive auth layout shell.
/// On tablet / wide screens, the form column is guaranteed a comfortable width
/// (480–520 pt) so cards, inputs, and legal disclaimers never break words awkwardly,
/// while the editorial photography flexes to fill the remainder.
struct AuthLayout<Content: View>: View {
    var title: String?
    var subtitle: String?
    /// The OTP and Set Password screens replace the plain title with their own
    /// multi-line node at different sizes.
    var titleView: AnyView?
    var topTrailing: AnyView? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let showsPanel = proxy.size.width >= Breakpoint.md
            // On iPad portrait (~768–834 pt) and landscape (>= 1024 pt):
            // Allocate the form column a healthy width (at least 480 pt, up to 520 pt)
            // so role cards and long titles have generous space. The image panel flexes.
            let formWidth: CGFloat = {
                if !showsPanel { return proxy.size.width }
                return min(520, max(480, proxy.size.width * 0.45))
            }()
            let imageWidth: CGFloat = max(0, proxy.size.width - formWidth)

            HStack(spacing: 0) {
                if showsPanel {
                    Image("AuthPanelImage")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageWidth, height: proxy.size.height)
                        .clipped()
                        .accessibilityLabel("Jewellery")
                }

                ScrollView {
                    stack(wide: showsPanel)
                        .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .frame(width: showsPanel ? formWidth : proxy.size.width)
                .background(Color.white)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(Color.white)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func stack(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow
                .padding(.bottom, wide ? 28 : 22)

            if let titleView {
                titleView
            } else if let title {
                Text(title)
                    .font(.custom("Georgia", size: wide ? 40 : 34).weight(.bold))
                    .foregroundStyle(AuthColor.ink)
                    .lineSpacing(wide ? 4 : 2)
                    .padding(.bottom, 8)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(AuthColor.subheading)
                    .lineSpacing(15 * 0.3)
                    .padding(.bottom, 20)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, wide ? 32 : 24)
        .padding(.top, wide ? 40 : 28)
        .padding(.bottom, 32)
    }

    private var brandRow: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AuthColor.ink)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: .circle)
                        .overlay(Circle().stroke(AuthColor.border2, lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle(scale: 0.94))
                .accessibilityLabel("Back")
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AuthColor.brandSquare)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(Copy.brandMark)
                        .font(.custom("Georgia", size: 16).weight(.bold))
                        .tracking(16 * 0.02)
                        .foregroundStyle(.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: 0xD4AF37).opacity(0.35), lineWidth: 1)
                )

            Text(Copy.brandWordmark)
                .font(.system(size: 17, weight: .bold))
                .tracking(17 * 0.01)
                .foregroundStyle(AuthColor.ink)

            Spacer()

            if let topTrailing {
                topTrailing
            }
        }
    }
}

// MARK: - Field label

struct AuthFieldLabel: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = AuthColor.labelDark

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(size * 0.01)
            .foregroundStyle(color)
            .padding(.bottom, 8)
    }
}

// MARK: - Text field

/// The entry screen's field: 52 pt tall, `#FAFAFA` fill, `#D9D0C5` border that
/// turns `#111111` on focus.
struct AuthTextField: View {
    @Binding var text: String
    var placeholder: String
    var height: CGFloat = 52
    var fill: Color = AuthColor.fieldFill
    var idleBorder: Color = AuthColor.fieldBorder
    var focusBorder: Color = AuthColor.ink
    var borderWidth: CGFloat = 1.5
    var cornerRadius: CGFloat = 8
    var fontSize: CGFloat = 14
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .font(.system(size: fontSize))
            .foregroundStyle(AuthColor.ink)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(fill, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(focused ? focusBorder : idleBorder, lineWidth: borderWidth)
            }
            .animation(.easeInOut(duration: 0.2), value: focused)  // transition: border-color 0.2s
    }
}

/// Password field with the eye toggle the web renders at `right-[12px]`.
struct AuthSecureField: View {
    @Binding var text: String
    var placeholder: String
    var height: CGFloat = 48
    var fontSize: CGFloat = 15
    var contentType: UITextContentType = .password

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .focused($focused)
            .font(.system(size: fontSize))
            .foregroundStyle(AuthColor.text2)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.leading, 12)
            .padding(.trailing, 40)
            .frame(height: height)
            .background(Color.white, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(focused ? AuthColor.focusBorder : AuthColor.border2, lineWidth: 1.5)
            }

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 15))
                    .foregroundStyle(AuthColor.placeholder)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel(revealed ? "Hide password" : "Show password")
        }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// MARK: - Error row

/// `flex items-start gap-2` with a small red dot — the web's only error
/// presentation in the auth flow.
struct AuthErrorRow: View {
    let message: String
    var dotSize: CGFloat = 5
    var dotTopPadding: CGFloat = 5
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AuthColor.errorDot)
                .frame(width: dotSize, height: dotSize)
                .padding(.top, dotTopPadding)
            Text(message)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(AuthColor.errorText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }
}

// MARK: - Primary button

/// The entry screen's CTA: 56 pt, `#1A1A1A`, greying to `#BBBBBB` when
/// disabled or loading.
struct AuthPrimaryButton: View {
    let title: String
    var height: CGFloat = 56
    var cornerRadius: CGFloat = 8
    var fontSize: CGFloat = 15
    var fontWeight: Font.Weight = .semibold
    var tracking: CGFloat = 0.02
    var enabledFill: Color = AuthColor.buttonEnabled
    var disabledFill: Color = AuthColor.buttonDisabled
    /// Sign-in and later screens fade the same fill instead of swapping it.
    var usesOpacityWhenDisabled = false
    var isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: fontWeight))
                .tracking(fontSize * tracking)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    usesOpacityWhenDisabled ? enabledFill : (isEnabled ? enabledFill : disabledFill),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .opacity(usesOpacityWhenDisabled && !isEnabled ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Legal footnote

/// `By continuing, you agree to our Terms of Service and Privacy Policy`,
/// then a way to reach support.
///
/// The web's links have no destination (`href="#"` or plain spans). Here they
/// open the real pages, in a browser over the app: App Review expects the
/// terms, the privacy policy and support to be reachable before sign-in.
struct AuthLegalText: View {
    var fontSize: CGFloat = 13
    var color: Color = AuthColor.subheading
    var emphasisColor: Color = AuthColor.ink
    var trailingPeriod = false
    var showsSupport = true

    @State private var page: BrowserPage?

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.6) {
            Text(agreement)
            if showsSupport {
                Text(support)
            }
        }
        .font(.system(size: fontSize))
        .foregroundStyle(color)
        // Links take the tint, not the run's own colour.
        .tint(emphasisColor)
        .lineSpacing(fontSize * 0.5)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.openURL, OpenURLAction { url in
            page = BrowserPage(url: url)
            return .handled
        })
        .sheet(item: $page) { page in
            InAppBrowser(url: page.url).ignoresSafeArea()
        }
    }

    private var agreement: AttributedString {
        var text = AttributedString(Copy.legal)
        text += link(Copy.legalTerms, to: LegalLinks.terms)
        text += AttributedString(Copy.legalAnd)
        text += link(Copy.legalPrivacy, to: LegalLinks.privacy)
        if trailingPeriod { text += AttributedString(".") }
        return text
    }

    private var support: AttributedString {
        var text = AttributedString(Copy.legalSupportLead)
        text += link(Copy.legalSupport, to: LegalLinks.support)
        if trailingPeriod { text += AttributedString(".") }
        return text
    }

    private func link(_ label: String, to url: URL) -> AttributedString {
        var part = AttributedString(label)
        part.link = url
        part.font = .system(size: fontSize, weight: .bold)
        part.underlineStyle = .single
        return part
    }
}

// MARK: - OR divider

struct AuthOrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(AuthColor.hairline).frame(height: 1)
            Text(Copy.entryDivider)
                .font(.system(size: 11, weight: .medium))
                .tracking(11 * 0.05)
                .foregroundStyle(AuthColor.dividerText)
            Rectangle().fill(AuthColor.hairline).frame(height: 1)
        }
        .padding(.vertical, 16)
    }
}
