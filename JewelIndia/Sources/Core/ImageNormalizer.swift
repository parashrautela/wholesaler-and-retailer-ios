import UIKit

/// Normalises picked images to JPEG before they leave the device.
///
/// ## Why this is needed on iOS but not on the web
///
/// The web receives a `File` from `<input type="file">`, which on a desktop is
/// already a JPEG or PNG sitting on disk — so `AddProductForm.jsx` uploads it
/// untouched. `PhotosPicker` is different: `loadTransferable(type: Data.self)`
/// hands back the asset's *original* representation, which for anything shot on
/// an iPhone or iPad is **HEIC**, and at full sensor resolution is routinely
/// 3–12 MB.
///
/// Uploading that raw does two bad things:
///   • HEIC bytes get labelled `image/jpeg`, so the pipeline's decoder is handed
///     a format it did not ask for;
///   • the body can exceed the pipeline's 10 MB cap, and Railway's edge closes
///     the connection instead of returning 413 — which reaches the app as
///     `NSURLErrorNetworkConnectionLost` ("The network connection was lost")
///     rather than as the "File exceeds 10 MB limit." the web would show.
///
/// Re-encoding here is therefore a deliberate divergence from the web, forced by
/// the platform rather than chosen.
enum ImageNormalizer {

    /// Comfortably under the pipeline's 10 MB cap, leaving room for the
    /// multipart envelope.
    static let maxUploadBytes = 8 * 1024 * 1024

    /// Product photos feed an AI enhancement step, so they keep more detail
    /// than the onboarding documents do.
    static let maxProductDimension: CGFloat = 2048

    /// Identity/business documents only need to be legible.
    static let maxDocumentDimension: CGFloat = 1200

    /// Converts arbitrary image data (HEIC, PNG, JPEG, …) into JPEG bounded by
    /// `maxDimension`, stepping quality down until it fits `maxUploadBytes`.
    /// Returns `nil` only when the data is not a decodable image at all.
    static func jpeg(
        from data: Data,
        maxDimension: CGFloat,
        quality: CGFloat = 0.85
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        var size = image.size
        if size.width > maxDimension || size.height > maxDimension {
            let scale = min(maxDimension / size.width, maxDimension / size.height)
            size = CGSize(width: (size.width * scale).rounded(),
                          height: (size.height * scale).rounded())
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true   // JPEG has no alpha; avoids a black matte
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        var currentQuality = quality
        var encoded = resized.jpegData(compressionQuality: currentQuality)
        while let candidate = encoded, candidate.count > maxUploadBytes, currentQuality > 0.4 {
            currentQuality -= 0.15
            encoded = resized.jpegData(compressionQuality: currentQuality)
        }
        return encoded
    }

    /// Normalises a picked file in place. PDFs pass through untouched — the
    /// pipeline and the document buckets both accept them as-is.
    static func normalized(
        _ file: PickedFile,
        maxDimension: CGFloat,
        quality: CGFloat = 0.85
    ) -> PickedFile {
        guard !file.isPDF,
              let data = jpeg(from: file.data, maxDimension: maxDimension, quality: quality)
        else { return file }

        let stem = (file.filename as NSString).deletingPathExtension
        return PickedFile(
            data: data,
            filename: (stem.isEmpty ? "upload" : stem) + ".jpg",
            mimeType: "image/jpeg"
        )
    }
}
