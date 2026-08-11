import Observation
import Supabase
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Retailer onboarding form state — the counterpart of `OnboardFlow` for
/// `/onboard-retailer`.
///
/// The previous `RetailerOnboardCoordinator` collected only a name, a store
/// name and a state, and "submitted" by inserting a `retailers` row with none
/// of the fields the rest of the app depends on: no Aadhaar number or images,
/// no city, no logo, no PAN, no GST. `_spec/06-retailer-screens.md` §4–§6
/// documents the same three-step, five-document flow as the wholesaler side,
/// and the `retailers` table (`_spec/04-data-contracts.md` §1.4) has the exact
/// same columns for it. This is that flow, built the same way `OnboardFlow`
/// was.
@MainActor
@Observable
final class RetailerOnboardFlow {

    // Step 1 — identity
    var name = ""
    var aadhar = ""
    var frontImage: PickedFile?
    var backImage: PickedFile?

    // Step 2 — store
    var storeName = ""
    var selectedState = ""
    var selectedCity = ""
    var logoImage: PickedFile?

    // Step 3 — documents
    var panFile: PickedFile?
    var gstFile: PickedFile?

    var submitAttempted = false
    var isSubmitting = false
    var submitError: String?

    // MARK: - Step 1 validation

    static func filterName(_ input: String) -> String { OnboardFlow.filterName(input) }
    static func formatAadhar(_ input: String) -> String { OnboardFlow.formatAadhar(input) }

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

    var storeNameError: String? {
        guard submitAttempted else { return nil }
        return storeName.trimmed.count >= 2 ? nil : "Store name is required"
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
        return logoImage == nil ? "Please upload your store logo" : nil
    }

    var step2Valid: Bool {
        storeName.trimmed.count >= 2 && !selectedState.isEmpty
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

    /// 29 states, exact web order (`RetailerBusinessForm.jsx`) — one entry
    /// longer than the wholesaler list and not alphabetical at the end: Delhi
    /// is deliberately last.
    static let states = [
        "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
        "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka",
        "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya",
        "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim",
        "Tamil Nadu", "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand",
        "West Bengal", "Delhi",
    ]

    // MARK: - Submit

    static func compress(_ file: PickedFile) -> PickedFile {
        ImageNormalizer.normalized(
            file,
            maxDimension: ImageNormalizer.maxDocumentDimension,
            quality: 0.7
        )
    }

    /// Mirrors `OnboardFlow.submit(user:)` exactly — same session guard, same
    /// lower-cased uid for the storage-policy folder check, same five buckets,
    /// same retry wrapping — pointed at `retailers` instead of `wholesalers`.
    func submit(user: User, referralCode: String?) async -> Bool {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        guard let session = try? await SupabaseManager.client.auth.session,
              session.user.id == user.id else {
            submitError = """
                Your session isn't active on this device, so the uploads can't \
                be authorised. Please sign out and sign in again.
                """
            return false
        }

        let uid = user.id.uuidString.lowercased()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)

        do {
            async let front = upload(frontImage, "aadhaar-documents", "\(uid)/aadhaar-front-\(stamp)", "Aadhar Front")
            async let back = upload(backImage, "aadhaar-documents", "\(uid)/aadhaar-back-\(stamp)", "Aadhar Back")
            async let pan = upload(panFile, "pan-documents", "\(uid)/pan-card-\(stamp)", "PAN Card")
            async let gst = upload(gstFile, "gst-documents", "\(uid)/gst-certificate-\(stamp)", "GST Certificate")
            async let logo = upload(logoImage, "business-logos", "\(uid)/business-logo-\(stamp)", "Store Logo")

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
                // Recorded so the referral is visible to the wholesaler who
                // shared the link — but the *attribution* (`referred_by`,
                // `referral_links.uses_count`) is intentionally not resolved
                // here. That needs read access to another wholesaler's
                // `referral_links` row, which the anon client's RLS has not
                // been verified to allow; see the implementation plan.
                let referral_code: String?
                let verification_status: String
            }

            let row = Row(
                user_id: uid,
                email: user.email ?? user.phone,
                full_name: name.trimmed,
                aadhar_number: aadharDigits,
                business_name: storeName.trimmed,
                state: selectedState,
                city: selectedCity.trimmed,
                aadhaar_front_url: urls.0,
                aadhaar_back_url: urls.1,
                pan_card_url: urls.2,
                gst_certificate_url: urls.3,
                business_logo_url: urls.4,
                referral_code: referralCode,
                verification_status: VerificationStatus.pending.rawValue
            )

            _ = try await JewelNetwork.withRetry {
                try await SupabaseManager.client
                    .from("retailers")
                    .upsert(row, onConflict: "user_id")
                    .execute()
            }

            return true
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    private func upload(
        _ file: PickedFile?,
        _ bucket: String,
        _ basePath: String,
        _ label: String
    ) async throws -> String? {
        guard let file else { return nil }
        let prepared = Self.compress(file)
        let ext = UTType(mimeType: prepared.mimeType)?.preferredFilenameExtension
            ?? (prepared.isPDF ? "pdf" : "jpg")
        let path = "\(basePath).\(ext)"
        do {
            return try await JewelNetwork.withRetry {
                try await WholesalerAPI.upload(
                    bucket: bucket,
                    path: path,
                    data: prepared.data,
                    contentType: prepared.mimeType
                )
            }
        } catch {
            throw UploadFailure(label: label, underlying: error)
        }
    }

    struct UploadFailure: LocalizedError {
        let label: String
        let underlying: any Error

        var errorDescription: String? {
            "Couldn't upload your \(label): \(underlying.localizedDescription)"
        }
    }
}
