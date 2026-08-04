import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared chrome for the wholesaler onboarding flow, ported from
/// `components/onboard/{OnboardLayout,OnboardNavbar,LeftPanel,StepIndicator,ImageUploadBox}.jsx`.

// MARK: - Responsive clamp

/// CSS `clamp(min, <n>vw, max)`.
///
/// The onboarding screens size almost everything this way. On a phone the
/// viewport is narrow enough that nearly every clamp resolves to its **minimum**
/// — which is why the step-1 heading is only 16px on mobile web. That is
/// faithful, not a mistake.
func clampVW(_ minimum: CGFloat, _ vw: CGFloat, _ maximum: CGFloat, width: CGFloat) -> CGFloat {
    min(max(minimum, width * vw / 100), maximum)
}

// MARK: - Colours specific to onboarding

enum OnboardColor {
    static let text = Color(hex: 0x374151)
    static let heading = Color(hex: 0x111827)
    static let subtle = Color(hex: 0x9CA3AF)
    static let fieldFill = Color(hex: 0xF5F5F5)
    static let border = Color(hex: 0xE5E7EB)
    static let navBorder = Color(hex: 0xE0E0E0)
    static let danger = Color(hex: 0xEF4444)
    static let uploadFill = Color(hex: 0xEEF4FF)
    static let uploadBorder = Color(hex: 0x2563EB)
    static let uploadFilled = Color(hex: 0x22C55E)
    static let disabled = Color(hex: 0xD1D5DB)
    static let submitting = Color(hex: 0x6B7280)
}

// MARK: - Layout

struct OnboardLayout<Content: View>: View {
    let step: Int
    let heading: String
    let subheading: String
    /// Whether a Back control is shown. Step 1 has one on the web (it signs you
    /// out); here it pops the stack instead — see `OnboardNavbar`.
    var showsBack: Bool = true
    var onBack: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let gutter = clampVW(16, 3, 48, width: w)
            let isWide = w >= Breakpoint.md

            VStack(spacing: 0) {
                OnboardNavbar(gutter: gutter, showsBack: showsBack, onBack: onBack)

                ScrollView {
                    let columns = VStack(alignment: .leading, spacing: 0) {
                        LeftPanel(heading: heading, subheading: subheading, width: w)
                        StepIndicator(step: step, totalSteps: 3)
                            .padding(.top, Spacing.xl)
                    }

                    Group {
                        if isWide {
                            HStack(alignment: .top, spacing: clampVW(24, 1, 48, width: w)) {
                                columns.frame(width: 340)
                                content.frame(width: 500)
                                Spacer(minLength: 0)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: Spacing.xxl) {
                                columns
                                content
                            }
                        }
                    }
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, gutter)
                    .padding(.top, clampVW(24, 3, 40, width: w))
                    .padding(.bottom, Spacing.xxxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color.white)
        }
        // `.onboard-page-transition` — 350ms fade + 8pt rise on every step.
        .transition(.onboardPage)
    }
}

/// The top bar. On the web **both** controls sign the user out — the left one
/// is labelled "Back" but calls `supabase.auth.signOut()`.
///
/// That is reproduced here only for the explicitly-labelled "Sign out" control.
/// "Back" pops the navigation stack and keeps the session: a back chevron that
/// destroys a half-finished onboarding session is a trap on iOS, where back is
/// also an edge-swipe gesture. Deliberate, user-approved divergence.
struct OnboardNavbar: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    let gutter: CGFloat
    var showsBack: Bool
    var onBack: (() -> Void)?

    @State private var confirmSignOut = false

    var body: some View {
        HStack {
            if showsBack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(OnboardColor.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                confirmSignOut = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person")
                        .font(.system(size: 13))
                    Text("Sign out")
                        .font(.system(size: 14))
                }
                .foregroundStyle(OnboardColor.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, gutter)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OnboardColor.navBorder).frame(height: Stroke.hairline)
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to finish onboarding.")
        }
    }
}

struct LeftPanel: View {
    let heading: String
    let subheading: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("JewelLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: clampVW(28, 3, 36, width: width),
                           height: clampVW(28, 3, 36, width: width))
                    .clipShape(.rect(cornerRadius: 7))
                Text("Jewels India")
                    .font(.system(size: clampVW(15, 1.6, 18, width: width), weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(OnboardColor.heading)
            }
            .padding(.bottom, Spacing.xl)

            Text(heading)
                .font(.system(size: clampVW(16, 1.8, 23, width: width), weight: .heavy))
                .foregroundStyle(OnboardColor.heading)
                .lineSpacing(clampVW(16, 1.8, 23, width: width) * 0.2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Spacing.sm)

            Text(subheading)
                .font(.system(size: clampVW(13, 1.3, 14, width: width), weight: .medium))
                .foregroundStyle(OnboardColor.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Progress rail. Width math is `((step - 1) / 3) * 100`, so step 1 starts at
/// 0% — the bar shows progress *completed*, not the current step.
struct StepIndicator: View {
    let step: Int
    let totalSteps: Int

    @State private var progress: CGFloat = 0

    private var target: CGFloat { CGFloat(step - 1) / 3.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("Step \(step)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(OnboardColor.heading)
                Text(" of \(totalSteps)")
                    .font(.system(size: 13))
                    .foregroundStyle(OnboardColor.subtle)
            }
            .tracking(13 * 0.1)   // tracking-widest
            .textCase(.uppercase)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(OnboardColor.border)
                    Capsule()
                        .fill(OnboardColor.heading)
                        .frame(width: max(0, proxy.size.width * progress))
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            // `transition: width 800ms cubic-bezier(0.25, 1, 0.5, 1)`
            withAnimation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.8)) {
                progress = target
            }
        }
        .onChange(of: step) { _, _ in
            withAnimation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.8)) {
                progress = target
            }
        }
    }
}

// MARK: - Text field

/// `bg-#F5F5F5 rounded-[8px]`, red 1.5pt border in the error state.
struct OnboardTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var error: String?
    var keyboard: UIKeyboardType = .default
    var disabled = false
    /// Applied on every keystroke, mirroring the web's input filters.
    var filter: ((String) -> String)?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardColor.text)

            TextField(placeholder, text: $text)
                .focused($focused)
                .disabled(disabled)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .font(.system(size: 15))
                .foregroundStyle(OnboardColor.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    disabled ? Color(hex: 0xF9FAFB) : OnboardColor.fieldFill,
                    in: .rect(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            error != nil ? OnboardColor.danger
                                : (focused ? Color.black.opacity(0.1) : .clear),
                            lineWidth: error != nil ? 1.5 : 2
                        )
                }
                .opacity(disabled ? 0.8 : 1)
                .onChange(of: text) { _, newValue in
                    if let filter {
                        let cleaned = filter(newValue)
                        if cleaned != newValue { text = cleaned }
                    }
                }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardColor.danger)
            }
        }
    }
}

// MARK: - Image / document upload tile

/// A file the user picked during onboarding.
struct PickedFile: Equatable, Sendable {
    var data: Data
    var filename: String
    var mimeType: String

    var isPDF: Bool { mimeType == "application/pdf" }
    var image: UIImage? { isPDF ? nil : UIImage(data: data) }
}

/// `components/onboard/ImageUploadBox.jsx`.
///
/// Empty → dashed blue border with a plus glyph. Error → dashed red.
/// Filled → solid 2pt green border with the preview. PDFs render a red doc
/// icon plus the truncated filename.
struct ImageUploadBox: View {
    let label: String
    @Binding var file: PickedFile?
    var error: String?
    /// The business logo uses `object-contain` with padding; documents use cover.
    var contentMode: ContentMode = .fill
    var allowsPDF = false

    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingSourceChoice = false

    private var borderColor: Color {
        if file != nil { return OnboardColor.uploadFilled }
        return error != nil ? OnboardColor.danger : OnboardColor.uploadBorder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardColor.text)
            }

            ZStack(alignment: .topTrailing) {
                tile
                if file != nil { removeButton }
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardColor.danger)
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: allowsPDF ? [.image, .pdf] : [.image]
        ) { result in
            handleImport(result)
        }
        // The web has a single `<input type=file>`; on iOS the photo library and
        // the file system are separate providers, so a PDF-capable tile has to
        // offer both. Image-only tiles go straight to the library.
        .confirmationDialog("Add \(label.replacingOccurrences(of: "*", with: ""))",
                            isPresented: $showingSourceChoice,
                            titleVisibility: .visible) {
            Button("Photo Library") { showingPhotoPicker = true }
            Button("Browse Files") { showingFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var tile: some View {
        // A transparent square that fills the available column width sets the
        // geometry; the content is overlaid on top. Applying `.aspectRatio` to
        // the content itself would size the tile to the 48pt glyph instead.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { tileContent }
            .background(OnboardColor.uploadFill, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(
                            lineWidth: file != nil ? 2 : 1.5,
                            dash: file != nil ? [] : [6, 5]
                        )
                    )
            }
            .contentShape(.rect)
            .onTapGesture {
                // The web only opens the picker when the tile is empty.
                guard file == nil else { return }
                if allowsPDF { showingSourceChoice = true } else { showingPhotoPicker = true }
            }
    }

    private var tileContent: some View {
        Group {
            if let file {
                if let image = file.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .padding(contentMode == .fit ? 16 : 0)
                } else {
                    // PDF
                    VStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color(hex: 0xDC2626))
                        Text(file.filename)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0x6B7280))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 120)
                    }
                }
            } else {
                Circle()
                    .stroke(borderColor, lineWidth: 2)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(borderColor)
                    }
            }
        }
        .clipped()
    }

    private var removeButton: some View {
        Button {
            file = nil
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardColor.text)
                .frame(width: 28, height: 28)
                .background(Color.white, in: .circle)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .padding(8)
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        file = PickedFile(data: data, filename: "upload.jpg", mimeType: "image/jpeg")
        photoItem = nil
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let type = UTType(filenameExtension: url.pathExtension)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        file = PickedFile(data: data, filename: url.lastPathComponent, mimeType: mime)
    }
}

// MARK: - Footer CTA

/// The onboarding Next / Submit button. Enabled black, disabled `#D1D5DB`,
/// submitting `#6B7280` with a spinner.
struct OnboardPrimaryButton: View {
    let title: String
    var busyTitle: String?
    var isBusy = false
    var isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text(isBusy ? (busyTitle ?? title) : title)
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(0.3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                isBusy ? OnboardColor.submitting : (isEnabled ? .black : OnboardColor.disabled),
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

/// The 7px legal note under the upload tiles, on steps 1–3.
struct OnboardLegalNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("*Your documents are encrypted and only used for verification.")
            Text("We never share them.")
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.black)
        .lineSpacing(2)
    }
}
