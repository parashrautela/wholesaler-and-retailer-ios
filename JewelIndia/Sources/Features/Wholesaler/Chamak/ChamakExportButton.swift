import SwiftUI
import UIKit

/// Free 2K export for one Chamak result: the lossless original PNG the
/// pipeline stored, handed to the share sheet. No charge and no unlock — the
/// paid tier is 4K, which this button does not offer.
///
/// Export used to be a one-off paid unlock (`chamak.export`, retailers only),
/// which hid it from wholesalers entirely. Those entitlements stay on record
/// but nothing here reads them any more.
struct ChamakExportButton: View {
    let generationID: String
    /// Storage path of the lossless original. Signed at export time, so a
    /// result left open past the one-hour signature still exports.
    let imagePath: String

    @State private var isWorking = false
    @State private var message: String?
    @State private var shareFile: ShareFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                message = nil
                Task { await export() }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("Download 2K · Free")
                        .font(.manrope(14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: 0x212120), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            if let message {
                Text(message)
                    .font(.manrope(11))
                    .foregroundStyle(Color.red)
            }
        }
        .sheet(item: $shareFile) { file in
            ActivitySheet(items: [file.url])
        }
    }

    private func export() async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let imageURL = await ChamakAPI.getSignedURL(path: imagePath) else {
                throw URLError(.badURL)
            }
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
