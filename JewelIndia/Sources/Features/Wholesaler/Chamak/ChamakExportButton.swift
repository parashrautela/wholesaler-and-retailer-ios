import SwiftUI
import UIKit

/// "View & Export" for one Chamak result. Results are view-only by default —
/// watermarked and capture-protected on screen; this pays once for a clean
/// copy and hands it to the share sheet.
///
/// Shown only where export is on sale: the rate card is filtered by audience
/// on the server, so no price means no button.
struct ChamakExportButton: View {
    let generationID: String
    let imageURL: URL

    @Environment(CreditStore.self) private var credits

    @State private var isOwned = false
    @State private var isWorking = false
    @State private var confirmPay = false
    @State private var showTopUp = false
    @State private var message: String?
    @State private var shareFile: ShareFile?

    private static let priceKey = "chamak.export"

    private var price: Int? { credits.cost(for: Self.priceKey) }
    private var balance: Int { credits.wallet?.available ?? 0 }

    var body: some View {
        if let price {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: tapped) {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(isOwned ? "Export Image" : "Export · \(TopUpStyle.count(price)) credits")
                            .font(.manrope(13, weight: .bold))
                    }
                    .foregroundStyle(Palette.dark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                if let message {
                    Text(message)
                        .font(.manrope(11))
                        .foregroundStyle(Color.red)
                } else if !isOwned {
                    Text("Viewing is included. Exporting saves a clean copy you can share.")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                }
            }
            .task(id: generationID) { await loadOwnership() }
            .confirmationDialog("Export this image?", isPresented: $confirmPay, titleVisibility: .visible) {
                Button("Pay \(TopUpStyle.count(price)) Credits") {
                    Task { await payThenExport() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("One charge for this image. After that you can export it again for free.")
            }
            .sheet(isPresented: $showTopUp) {
                TopUpSheet()
                    .environment(credits)
            }
            .sheet(item: $shareFile) { file in
                ActivitySheet(items: [file.url])
            }
        }
    }

    private func tapped() {
        message = nil
        if isOwned {
            Task { await export() }
        } else if balance < (price ?? 0) {
            showTopUp = true
        } else {
            confirmPay = true
        }
    }

    private func loadOwnership() async {
        let keys = (try? await CreditsAPI.fetchEntitlementKeys()) ?? []
        isOwned = keys.contains("export.\(generationID.lowercased())")
    }

    private func payThenExport() async {
        isWorking = true
        do {
            let result = try await CreditsAPI.purchaseExport(generationID: generationID)
            if result.ok {
                isOwned = true
                await credits.refresh()
                isWorking = false
                await export()
                return
            } else if result.isInsufficientCredits {
                await credits.refresh()
                message = "You need \(TopUpStyle.count(result.shortBy ?? 0)) more credits to export."
            } else {
                message = "This image can't be exported right now."
            }
        } catch {
            // The charge may have landed; a retry replays it rather than repeating it.
            message = "Couldn't reach the server. Try again — you won't be charged twice."
        }
        isWorking = false
    }

    private func export() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard UIImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("chamak-\(generationID.prefix(8)).png")
            try data.write(to: file, options: .atomic)
            shareFile = ShareFile(url: file)
            StoreActivity.log(.imageExported)
        } catch {
            message = "Couldn't prepare the image. Please try again."
        }
    }
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
