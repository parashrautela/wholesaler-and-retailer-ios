import Foundation
import Supabase

enum ChamakAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    struct ChamakError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Every `chamak_generations`/`chamak_feedback` write is gated by
    /// `auth.uid() = wholesaler_id` RLS (see `SUPABASE_CHAMAK_MIGRATION.sql`).
    /// `wholesalerID` here is always a live `session.user.id`, so a mismatch
    /// isn't a bad id — it means the SDK doesn't actually have a session
    /// attached to the request, and the insert goes out as `anon`. That fails
    /// this check every time, immediately, with a bare "new row violates
    /// row-level security policy" — indistinguishable from a real policy bug
    /// unless this is checked first. Same fix, same reasoning, as
    /// `OnboardFlow.submit`.
    private static func requireLiveSession(matching wholesalerID: UUID) async throws {
        guard let session = try? await SupabaseManager.client.auth.session,
              session.user.id == wholesalerID else {
            throw ChamakError(message: """
                Your session isn't active on this device, so this can't be \
                authorised. Please sign out and sign in again.
                """)
        }
    }

    // MARK: - Products for Picker

    /// Fetches all active products belonging to this wholesaler with valid images
    static func fetchWholesalerProducts(wholesalerID: UUID) async throws -> [Product] {
        let rows: [Product] = try await db.from("products")
            .select()
            .eq("wholesaler_id", value: wholesalerID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        // Filter for products that have at least one usable image URL
        return rows.filter { product in
            let url = product.processedImageURL ?? product.imageURL ?? product.rawImageURL
            return url != nil && !url!.isEmpty
        }
    }

    // MARK: - Quota Check

    /// Checks remaining daily AI quota against the existing daily limits
    static func checkQuota(wholesalerID: UUID) async -> (canGenerate: Bool, remaining: Int, limit: Int) {
        let usage = await WholesalerAPI.fetchUploadUsage(wholesalerID: wholesalerID)
        let limit = usage.limit ?? 10
        let remaining = max(0, limit - usage.used)
        let canGenerate = usage.isUnlimited || remaining > 0
        return (canGenerate, remaining, limit)
    }

    // MARK: - Direct Source Upload

    /// Uploads a custom user photo directly to storage for Chamak analysis
    static func uploadSourceImage(
        wholesalerID: UUID,
        imageData: Data,
        slot: Int
    ) async throws -> String {
        let uid = wholesalerID.uuidString.lowercased()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "raw/\(uid)/chamak_\(slot)_\(stamp).jpg"
        return try await WholesalerAPI.upload(
            bucket: "plant-images",
            path: path,
            data: imageData,
            contentType: "image/jpeg"
        )
    }

    // MARK: - Stage 1: Create & Analyze

    struct CreateGenerationPayload: Encodable {
        let wholesaler_id: String
        let source_image_1_url: String
        let source_image_2_url: String
        let status: String
        let prompt_version: String
    }

    /// Inserts the initial row into `chamak_generations`
    static func createGeneration(
        wholesalerID: UUID,
        source1URL: String,
        source2URL: String
    ) async throws -> ChamakGeneration {
        try await requireLiveSession(matching: wholesalerID)

        let payload = CreateGenerationPayload(
            // Lower-cased for the same reason as onboarding's storage paths:
            // `auth.uid()::text` renders lower case, and while a `uuid`-typed
            // RLS comparison is case-insensitive, keeping this consistent
            // with every other `{uid}/...` write in the app avoids relying on
            // that distinction implicitly.
            wholesaler_id: wholesalerID.uuidString.lowercased(),
            source_image_1_url: source1URL,
            source_image_2_url: source2URL,
            status: ChamakStatus.queued.rawValue,
            prompt_version: "v1.0-chamak"
        )

        let created: ChamakGeneration = try await JewelNetwork.withRetry {
            try await db.from("chamak_generations")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
        }

        return created
    }

    /// Triggers Stage 1 vision analysis on the backend service.
    ///
    /// A non-2xx or thrown request used to be swallowed into a silent
    /// `status = "analyzing"` write with no error surfaced — so a missing or
    /// failing backend route was indistinguishable from "still working" until
    /// the view model's poller gave up on its own, ~100 seconds later. This
    /// now throws immediately with whatever detail the backend gave, and
    /// marks the row `failed` so a stuck "analyzing" row doesn't linger.
    static func triggerStage1Analysis(generationID: UUID) async throws {
        var request = URLRequest(url: AppConfig.aiPipelineURL.appending(path: "/api/chamak/analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "generation_id": generationID.uuidString
        ])
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            try? await updateStatus(generationID: generationID, status: .failed)
            throw ChamakError(message: "Couldn't reach the analysis service. Check your connection and try again.")
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (detail?["detail"] as? String) ?? (detail?["message"] as? String)
                ?? "The analysis service didn't accept this request."
            try? await updateStatus(generationID: generationID, status: .failed)
            throw ChamakError(message: message)
        }
    }

    // MARK: - Fetch Status / Generation

    static func fetchGeneration(generationID: UUID) async throws -> ChamakGeneration {
        let row: ChamakGeneration = try await db.from("chamak_generations")
            .select()
            .eq("id", value: generationID.uuidString)
            .single()
            .execute()
            .value
        return row
    }

    static func updateStatus(generationID: UUID, status: ChamakStatus) async throws {
        struct StatusPatch: Encodable {
            let status: String
        }
        _ = try await db.from("chamak_generations")
            .update(StatusPatch(status: status.rawValue))
            .eq("id", value: generationID.uuidString)
            .execute()
    }

    // MARK: - Stage 3 & 4: Submit Form and Generate

    struct FormUpdatePayload: Encodable {
        let wholesaler_form_json: WholesalerFormInput
        let note_text: String?
        let status: String
    }

    static func submitFormAndGenerate(
        generationID: UUID,
        wholesalerID: UUID,
        formInput: WholesalerFormInput,
        note: String?
    ) async throws {
        try await requireLiveSession(matching: wholesalerID)

        let payload = FormUpdatePayload(
            wholesaler_form_json: formInput,
            note_text: note,
            status: ChamakStatus.generating.rawValue
        )

        _ = try await JewelNetwork.withRetry {
            try await db.from("chamak_generations")
                .update(payload)
                .eq("id", value: generationID.uuidString)
                .execute()
        }

        // Trigger backend pipeline endpoint for Stage 3 (Compilation) & Stage 4 (Fusion).
        // A non-2xx here used to be discarded entirely (`try?` on the whole
        // call), so a missing/failing backend route looked identical to a
        // slow one — the row sat at "generating" until the poller in
        // ChamakViewModel timed out on its own. Surfacing it here means the
        // real cause reaches the UI in seconds instead of ~100s.
        var request = URLRequest(url: AppConfig.aiPipelineURL.appending(path: "/api/chamak/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "generation_id": generationID.uuidString
        ])
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (detail?["detail"] as? String) ?? (detail?["message"] as? String)
                ?? "The fusion pipeline didn't accept this request."
            try? await updateStatus(generationID: generationID, status: .failed)
            throw ChamakError(message: message)
        }
    }

    // MARK: - Signed Storage URL

    /// Creates a 1-hour signed URL for private chamak output images
    static func getSignedURL(path: String) async -> URL? {
        // If already a full http signed url or external url, return directly
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            if path.contains("token=") || path.contains("supabase.co/storage") {
                return URL(string: path)
            }
        }

        // Clean relative path inside bucket
        let cleanPath = path.replacingOccurrences(of: "chamak-outputs/", with: "")
        do {
            let signedURL = try await db.storage
                .from("chamak-outputs")
                .createSignedURL(path: cleanPath, expiresIn: 3600)
            return signedURL
        } catch {
            return URL(string: path)
        }
    }

    // MARK: - Feedback

    static func submitFeedback(
        generationID: UUID,
        satisfied: Bool,
        whatWentWrong: String?
    ) async throws {
        let payload = ChamakFeedback(
            id: nil,
            chamakGenerationId: generationID,
            satisfied: satisfied,
            whatWentWrongText: whatWentWrong,
            createdAt: nil
        )

        _ = try await JewelNetwork.withRetry {
            try await db.from("chamak_feedback")
                .insert(payload)
                .execute()
        }
    }

    // MARK: - Gallery

    static func fetchWholesalerGallery(wholesalerID: UUID) async throws -> [ChamakGeneration] {
        let rows: [ChamakGeneration] = try await db.from("chamak_generations")
            .select()
            .eq("wholesaler_id", value: wholesalerID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }
}
