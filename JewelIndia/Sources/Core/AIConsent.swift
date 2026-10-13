import SwiftUI

/// Permission to send jewellery photos to third-party AI providers. App Review
/// (5.1.2(i)) requires saying who receives the data and getting an explicit
/// yes before the first upload, so every AI entry point asks once per account.
enum AIConsent {
    /// Who actually receives the photos — keep in step with the ai-pipeline
    /// service and the privacy policy.
    static let providers = "Reve, NanoBanana (Google image models) and OpenAI"

    private static func key() -> String {
        let user = SupabaseManager.client.auth.currentUser?.id.uuidString.lowercased() ?? "signed-out"
        return "ai-consent.v1.\(user)"
    }

    static var isGranted: Bool {
        UserDefaults.standard.bool(forKey: key())
    }

    static func grant() {
        UserDefaults.standard.set(true, forKey: key())
    }

    /// The last line of defence: every call that sends photos to the AI
    /// service checks this, whichever screen it came from.
    static func requireGranted() throws {
        guard isGranted else { throw Required() }
    }

    struct Required: LocalizedError {
        var errorDescription: String? { "Allow AI image processing to use this feature." }
    }
}

/// Shows the permission screen in place of an AI feature until it is granted.
struct AIConsentGate<Content: View>: View {
    var onDecline: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var granted = AIConsent.isGranted

    var body: some View {
        if granted {
            content()
        } else {
            AIConsentPrompt(
                onAllow: {
                    AIConsent.grant()
                    granted = true
                },
                onDecline: onDecline
            )
        }
    }
}

/// The permission screen itself, also used as a sheet before re-processing.
struct AIConsentPrompt: View {
    let onAllow: () -> Void
    var onDecline: (() -> Void)?

    @State private var page: BrowserPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.dark)

                Text("Allow AI image processing?")
                    .font(.cirka(28))
                    .foregroundStyle(Palette.foreground)

                Text("Jewel India's studio images and Chamak designs are created by AI partners. When you use these features, the jewellery photos you choose and the details you enter for them are sent to \(AIConsent.providers) to generate the result.")
                    .font(.manrope(14))
                    .foregroundStyle(Palette.foreground)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    bullet("Only photos you upload for an AI feature are sent — nothing else from your device.")
                    bullet("They are used only to create your images, not for advertising.")
                    bullet("You can keep using the rest of Jewel India without AI features.")
                }

                Button {
                    page = BrowserPage(url: LegalLinks.privacy)
                } label: {
                    Text("Read our Privacy Policy")
                        .font(.manrope(13, weight: .semibold))
                        .underline()
                        .foregroundStyle(Palette.dark)
                }

                Button(action: onAllow) {
                    Text("Allow")
                        .font(.manrope(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.dark, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, Spacing.sm)

                if let onDecline {
                    Button("Not now", action: onDecline)
                        .font(.manrope(14, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(item: $page) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 3)
            Text(text)
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
        }
    }
}
