import SwiftUI

/// One tile in a Chamak gallery grid — shared by the in-flow gallery and the
/// Chamak tab. `thumbnailURL` must already be signed: outputs live in a
/// private bucket, and the stored `outputImageURL` is only a path.
///
/// Same frame as the catalogue cards (square photo, two short lines) so every
/// grid in the app reads alike. The two designs that went in sit stacked in
/// the corner — which pair made this is the first thing you want to know
/// scanning a gallery — and a run that isn't finished says so in the photo
/// area rather than in a badge over an empty grey box.
struct ChamakGalleryCard: View {
    let generation: ChamakGeneration
    let thumbnailURL: URL?
    let action: () -> Void

    private var isSet: Bool { generation.mode == .setCreation }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Color(hex: 0xF3F4F6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { preview }
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        sourceStack.padding(8)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isSet ? "Set Creation" : "Chamak Fusion")
                        .font(.manrope(13, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: 5, y: 2)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(isSet ? "Set Creation" : "Chamak Fusion"), \(subtitle), \(statusText)")
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        switch generation.status {
        case .done:
            if let thumbnailURL {
                ProtectedImageView(url: thumbnailURL)
            } else {
                // Finished, but the signed URL isn't back (or failed) yet.
                placeholder(symbol: "sparkles", tint: Color(hex: 0xBB8651), text: nil)
            }
        case .queued, .analyzing, .generating:
            VStack(spacing: 8) {
                ProgressView()
                    .tint(Color(hex: 0xBB8651))
                Text("Creating…")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x92400E))
            }
        case .awaitingInput:
            placeholder(symbol: "slider.horizontal.3", tint: Color(hex: 0x2563EB), text: "Needs your input")
        case .failed:
            placeholder(symbol: "exclamationmark.triangle", tint: Color(hex: 0xDC2626), text: "Didn't finish")
        }
    }

    private func placeholder(symbol: String, tint: Color, text: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(tint)
            if let text {
                Text(text)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    // MARK: - Sources

    /// The two inputs, overlapped like a pair of prints.
    @ViewBuilder
    private var sourceStack: some View {
        let urls = [generation.sourceImage1URL, generation.sourceImage2URL]
            .compactMap { URL(string: $0) }
            .filter { $0.scheme != nil }
        if !urls.isEmpty {
            HStack(spacing: -10) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    Color(hex: 0xF3F4F6)
                        .frame(width: 30, height: 30)
                        .overlay { ProtectedImageView(url: url) }
                        .clipShape(.rect(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(.white, lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Text

    /// "10 Sep", plus the backdrop for a set ("10 Sep · Velvet Bust").
    private var subtitle: String {
        [formattedDate, isSet ? generation.setBackdrop?.label : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var statusText: String {
        switch generation.status {
        case .done: "Done"
        case .queued, .analyzing, .generating: "Creating"
        case .awaitingInput: "Needs your input"
        case .failed: "Didn't finish"
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let raw = generation.createdAt
        guard let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
            return "Recent"
        }
        // "10 Sep" this year, "10 Sep 2025" otherwise — short enough for one line.
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
