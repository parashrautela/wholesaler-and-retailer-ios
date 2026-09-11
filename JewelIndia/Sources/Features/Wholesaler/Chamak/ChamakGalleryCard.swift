import SwiftUI

/// One tile in a Chamak gallery grid — shared by the in-flow gallery and the
/// Chamak tab. `thumbnailURL` must already be signed: outputs live in a
/// private bucket, and the stored `outputImageURL` is only a path.
struct ChamakGalleryCard: View {
    let generation: ChamakGeneration
    let thumbnailURL: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    Color(hex: 0xF3F4F6)
                        .frame(height: 150)
                        .overlay {
                            if let thumbnailURL {
                                ProtectedImageView(url: thumbnailURL)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color(hex: 0xBB8651))
                            }
                        }
                        .clipped()
                        .clipShape(.rect(cornerRadius: 8))

                    statusBadge
                }

                // Prompt version used to sit here too and pushed the date onto
                // two lines in a two-column grid; it's still on the result
                // screen under Traceability.
                HStack(spacing: 6) {
                    modeBadge
                    Text(formattedDate)
                        .font(.manrope(11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(Spacing.sm)
            .background(Color.white, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.02), radius: 3, y: 1)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var modeBadge: some View {
        let isSet = generation.mode == .setCreation
        return Text(isSet ? "Set" : "Fusion")
            .font(.manrope(9, weight: .bold))
            .foregroundStyle(isSet ? Color(hex: 0xBB8651) : Color(hex: 0x6B7280))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSet ? Color(hex: 0xFFFBF4) : Color(hex: 0xF3F4F6), in: .capsule)
    }

    private var statusBadge: some View {
        let (color, text) = switch generation.status {
        case .done: (Color(hex: 0x16A34A), "Done")
        case .generating, .analyzing, .queued: (Color(hex: 0xD97706), "Processing")
        case .awaitingInput: (Color(hex: 0x2563EB), "Input")
        case .failed: (Color(hex: 0xDC2626), "Failed")
        }

        return Text(text)
            .font(.manrope(10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: .capsule)
            .padding(6)
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
