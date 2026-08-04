import Observation
import Supabase
import SwiftUI
import UIKit

/// Onboarding form state — the native counterpart of `context/OnboardContext.jsx`.
///
/// The web keeps this in memory only, so a page refresh wipes steps 1–2. A
/// SwiftUI `@State` object on the coordinator has the same lifetime (it dies
/// when the flow is left), which reproduces that without the surprise of a
/// refresh mid-flow.
@MainActor
@Observable
final class OnboardFlow {

    // Step 1 — identity
    var name = ""
    var aadhar = ""            // display form, "#### #### ####"
    var frontImage: PickedFile?
    var backImage: PickedFile?

    // Step 2 — business
    var businessName = ""
    var selectedState = ""
    var selectedCity = ""
    var logoImage: PickedFile?

    // Step 3 — documents
    var panFile: PickedFile?
    var gstFile: PickedFile?

    /// Errors only appear after a failed Next, matching `submitAttempted`.
    var submitAttempted = false
    var isSubmitting = false
    var submitError: String?

    // MARK: - Step 1 validation

    /// `/^[A-Za-z\s]*$/` — letters and spaces only, applied per keystroke.
    static func filterName(_ input: String) -> String {
        input.filter { $0.isLetter && $0.isASCII || $0 == " " }
    }

    /// Digits only, capped at 12, formatted `#### #### ####`.
    static func formatAadhar(_ input: String) -> String {
        let digits = String(input.filter(\.isNumber).prefix(12))
        return stride(from: 0, to: digits.count, by: 4).map { offset in
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: min(4, digits.count - offset))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }

    var aadharDigits: String { aadhar.filter(\.isNumber) }

    var nameError: String? {
        guard submitAttempted else { return nil }
        return name.trimmed.isEmpty ? "Name is required" : nil
    }
    var aadharError: String? {
        guard submitAttempted else { return nil }
        return aadharDigits.count == 12 ? nil : "Enter a valid 12-digit Aadhar number"
    }
    var frontError: String? {
        guard submitAttempted else { return nil }
        return frontImage == nil ? "Please upload Aadhar Front" : nil
    }
    var backError: String? {
        guard submitAttempted else { return nil }
        return backImage == nil ? "Please upload Aadhar Back" : nil
    }

    var step1Valid: Bool {
        !name.trimmed.isEmpty && aadharDigits.count == 12
            && frontImage != nil && backImage != nil
    }

    // MARK: - Step 2 validation

    var businessNameError: String? {
        guard submitAttempted else { return nil }
        return businessName.trimmed.count >= 2 ? nil : "Business name is required"
    }
    var stateError: String? {
        guard submitAttempted else { return nil }
        return selectedState.isEmpty ? "Please select a state" : nil
    }
    var cityError: String? {
        guard submitAttempted else { return nil }
        return selectedCity.trimmed.isEmpty ? "Please enter a city" : nil
    }
    var logoError: String? {
        guard submitAttempted else { return nil }
        return logoImage == nil ? "Please upload your business logo" : nil
    }

    var step2Valid: Bool {
        businessName.trimmed.count >= 2 && !selectedState.isEmpty
            && !selectedCity.trimmed.isEmpty && logoImage != nil
    }

    // MARK: - Step 3 validation

    var panError: String? {
        guard submitAttempted else { return nil }
        return panFile == nil ? "Please upload your PAN Card" : nil
    }
    var gstError: String? {
        guard submitAttempted else { return nil }
        return gstFile == nil ? "Please upload your GST Certificate" : nil
    }

    var step3Valid: Bool { panFile != nil && gstFile != nil }

    /// The 28 states the web offers, in its exact order. Union territories are
    /// deliberately absent — that matches the source.
    static let states = [
        "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
        "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka",
        "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya",
        "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim",
        "Tamil Nadu", "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand",
        "West Bengal",
    ]

    // MARK: - Submit

    /// Port of `Step3Footer.compressImage`: fit inside 1200×1200 preserving
    /// aspect, re-encode as JPEG quality 0.7. PDFs pass through untouched.
    static func compress(_ file: PickedFile) -> PickedFile {
        guard !file.isPDF, let image = UIImage(data: file.data) else { return file }

        let maxSide: CGFloat = 1200
        var size = image.size
        if size.width > maxSide || size.height > maxSide {
            let scale = min(maxSide / size.width, maxSide / size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }

        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1
            return f
        }())
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return file }

        return PickedFile(data: jpeg, filename: file.filename, mimeType: "image/jpeg")
    }

    /// The web POSTs everything to `/api/onboard/submit`, which authenticates
    /// from SSR cookies and uploads with the service-role key — neither of
    /// which a native client has. The same work is done here with the user's
    /// own session: upload each file to its bucket under `{uid}/…`, then upsert
    /// `wholesalers` (which RLS already permits for one's own row).
    func submit(user: User) async -> Bool {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let uid = user.id.uuidString
        let stamp = Int(Date().timeIntervalSince1970 * 1000)

        func ext(_ f: PickedFile) -> String { f.isPDF ? "pdf" : "jpg" }

        do {
            async let front = upload(frontImage, "aadhaar-documents", "\(uid)/aadhaar-front-\(stamp)")
            async let back = upload(backImage, "aadhaar-documents", "\(uid)/aadhaar-back-\(stamp)")
            async let pan = upload(panFile, "pan-documents", "\(uid)/pan-card-\(stamp)")
            async let gst = upload(gstFile, "gst-documents", "\(uid)/gst-certificate-\(stamp)")
            async let logo = upload(logoImage, "business-logos", "\(uid)/business-logo-\(stamp)")

            let urls = try await (front, back, pan, gst, logo)

            struct Row: Encodable {
                let user_id: String
                let email: String?
                let full_name: String
                let aadhar_number: String
                let business_name: String
                let state: String
                let city: String
                let aadhaar_front_url: String?
                let aadhaar_back_url: String?
                let pan_card_url: String?
                let gst_certificate_url: String?
                let business_logo_url: String?
                let verification_status: String
            }

            let row = Row(
                user_id: uid,
                email: user.email ?? user.phone,
                full_name: name.trimmed,
                aadhar_number: aadharDigits,
                business_name: businessName.trimmed,
                state: selectedState,
                city: selectedCity.trimmed,
                aadhaar_front_url: urls.0,
                aadhaar_back_url: urls.1,
                pan_card_url: urls.2,
                gst_certificate_url: urls.3,
                business_logo_url: urls.4,
                verification_status: VerificationStatus.pending.rawValue
            )

            _ = try await SupabaseManager.client
                .from("wholesalers")
                .upsert(row, onConflict: "user_id")
                .execute()

            return true
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    private func upload(_ file: PickedFile?, _ bucket: String, _ basePath: String) async throws -> String? {
        guard let file else { return nil }
        let prepared = Self.compress(file)
        let path = "\(basePath).\(prepared.isPDF ? "pdf" : "jpg")"
        return try await WholesalerAPI.upload(
            bucket: bucket,
            path: path,
            data: prepared.data,
            contentType: prepared.mimeType
        )
    }
}
