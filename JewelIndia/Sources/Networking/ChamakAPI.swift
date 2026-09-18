import Foundation
import Supabase

enum ChamakAPI {

    private static var db: SupabaseClient { SupabaseManager.client }

    struct ChamakError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct InsufficientCreditsError: LocalizedError {
        let required: Int
        let balance: Int
        let shortBy: Int
        var errorDescription: String? { "You need \(shortBy) more credits." }
    }

    /// Attaches the caller's Supabase session to a pipeline request.
    ///
    /// The pipeline verifies this token and refuses to spend credits without it.
    /// `requireLiveSession` already proves a session exists for the RLS writes —
    /// this is the same session, now also needed by the HTTP hop.
    private static func authorized(
        _ url: URL,
        idempotencyKey: String? = nil
    ) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let session = try? await SupabaseManager.client.auth.session else {
            throw ChamakError(message: """
                Your session isn't active on this device. \
                Please sign out and sign in again.
                """)
        }
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
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

    /// A retailer has no products of their own: their picker offers the
    /// designs they have gathered — the store's shortlist and everything on
    /// their customers' boards. RLS scopes both reads to the caller's store.
    static func fetchStoreProducts() async throws -> [Product] {
        struct Row: Decodable { let product_id: String }
        async let shortlist: [Row] = db.from("retailer_selections")
            .select("product_id").execute().value
        async let boards: [Row] = db.from("customer_board_items")
            .select("product_id").execute().value

        let ids = try await Set((shortlist + boards).map(\.product_id))
        guard !ids.isEmpty else { return [] }

        let rows: [Product] = try await db.from("products")
            .select()
            .eq("is_published", value: true)
            .in("id", values: Array(ids))
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.filter { product in
            let url = product.processedImageURL ?? product.imageURL ?? product.rawImageURL
            return !(url ?? "").isEmpty
        }
    }

    // MARK: - Direct Source Upload

    /// Uploads a custom user photo directly to storage for Chamak analysis.
    /// Path prefix matches the web app's own naming split (`chamak_...` vs
    /// `setcreation_...`, `lib/supabase/set-creation-queries.js`) so uploads
    /// stay distinguishable in the bucket regardless of which client wrote them.
    static func uploadSourceImage(
        wholesalerID: UUID,
        imageData: Data,
        slot: Int,
        mode: ChamakMode = .fusion
    ) async throws -> String {
        let uid = wholesalerID.uuidString.lowercased()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let prefix = mode == .setCreation ? "setcreation" : "chamak"
        let path = "raw/\(uid)/\(prefix)_\(slot)_\(stamp).jpg"
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
        let mode: String
    }

    /// Inserts the initial row into `chamak_generations`
    static func createGeneration(
        wholesalerID: UUID,
        source1URL: String,
        source2URL: String,
        mode: ChamakMode = .fusion
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
            prompt_version: "v1.0-chamak",
            mode: mode.rawValue
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
    static func triggerStage1Analysis(
        generationID: UUID,
        idempotencyKey: String? = nil
    ) async throws {
        var request = try await authorized(
            AppConfig.aiPipelineURL.appending(path: "/api/chamak/analyze"),
            idempotencyKey: idempotencyKey
        )
        request.httpMethod = "POST"
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

        guard let http = response as? HTTPURLResponse else {
            try? await updateStatus(generationID: generationID, status: .failed)
            throw ChamakError(message: "The analysis service didn't accept this request.")
        }

        if (200..<300).contains(http.statusCode) {
            return
        }

        if http.statusCode == 402 {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["detail"] as? [String: Any]
            let required = detail?["required"] as? Int ?? 0
            let balance = detail?["balance"] as? Int ?? 0
            let shortBy = detail?["short_by"] as? Int ?? max(0, required - balance)
            // DO NOT update status to .failed on 402!
            throw InsufficientCreditsError(required: required, balance: balance, shortBy: shortBy)
        }

        if http.statusCode == 401 {
            throw ChamakError(message: "Your session has expired. Please sign out and sign in again.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message: String
        if let detailStr = json?["detail"] as? String {
            message = detailStr
        } else if let detailObj = json?["detail"] as? [String: Any], let msg = detailObj["message"] as? String {
            message = msg
        } else if let msg = json?["message"] as? String {
            message = msg
        } else {
            message = "The analysis service didn't accept this request."
        }

        try? await updateStatus(generationID: generationID, status: .failed)
        throw ChamakError(message: message)
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
        note: String?,
        idempotencyKey: String? = nil
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
        //
        // `generate-v2` renders on OpenAI and receives BOTH source designs.
        // The original `generate` route sends only `source_image_1_url`, so
        // Design 2 never reached the image model there — it survived only as
        // text in the compiled prompt, which is why those fusions tracked
        // Design 1 no matter where the sliders sat. The web dashboard moved
        // to this route first; this keeps iOS on the same renderer rather
        // than quietly shipping two different products.
        var request = try await authorized(
            AppConfig.aiPipelineURL.appending(path: "/api/chamak/generate-v2"),
            idempotencyKey: idempotencyKey
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "generation_id": generationID.uuidString
        ])
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            try? await updateStatus(generationID: generationID, status: .failed)
            throw ChamakError(message: "The fusion pipeline didn't accept this request.")
        }

        if (200..<300).contains(http.statusCode) {
            return
        }

        if http.statusCode == 402 {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["detail"] as? [String: Any]
            let required = detail?["required"] as? Int ?? 0
            let balance = detail?["balance"] as? Int ?? 0
            let shortBy = detail?["short_by"] as? Int ?? max(0, required - balance)
            // DO NOT update status to .failed on 402!
            throw InsufficientCreditsError(required: required, balance: balance, shortBy: shortBy)
        }

        if http.statusCode == 401 {
            throw ChamakError(message: "Your session has expired. Please sign out and sign in again.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message: String
        if let detailStr = json?["detail"] as? String {
            message = detailStr
        } else if let detailObj = json?["detail"] as? [String: Any], let msg = detailObj["message"] as? String {
            message = msg
        } else if let msg = json?["message"] as? String {
            message = msg
        } else {
            message = "The fusion pipeline didn't accept this request."
        }

        try? await updateStatus(generationID: generationID, status: .failed)
        throw ChamakError(message: message)
    }

    // MARK: - Set Creation: Submit Styling and Generate

    struct SetFormUpdatePayload: Encodable {
        let wholesaler_form_json: SetCreationInput
        let note_text: String?
        let set_backdrop: String
        let status: String
    }

    /// Set Creation's counterpart to `submitFormAndGenerate` — mirrors its
    /// update-row-then-call-pipeline shape and identical 402/401 handling,
    /// but hits its own dedicated endpoint. Confirmed directly against the
    /// pipeline source (`ai-pipeline/app/main.py`,
    /// `POST /api/set-creation/generate`) rather than assumed: unlike Fusion,
    /// this is not a branch inside `/api/chamak/generate-v2` — it's a
    /// separate route, though it shares the same `chamak_generations` table,
    /// the same polling endpoint, and the same credit-charge machinery.
    static func submitSetAndGenerate(
        generationID: UUID,
        wholesalerID: UUID,
        backdrop: SetBackdrop,
        note: String?,
        idempotencyKey: String? = nil
    ) async throws {
        try await requireLiveSession(matching: wholesalerID)

        let payload = SetFormUpdatePayload(
            wholesaler_form_json: SetCreationInput(backdrop: backdrop, note: note),
            note_text: note,
            set_backdrop: backdrop.rawValue,
            status: ChamakStatus.generating.rawValue
        )

        _ = try await JewelNetwork.withRetry {
            try await db.from("chamak_generations")
                .update(payload)
                .eq("id", value: generationID.uuidString)
                .execute()
        }

        var request = try await authorized(
            AppConfig.aiPipelineURL.appending(path: "/api/set-creation/generate"),
            idempotencyKey: idempotencyKey
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "generation_id": generationID.uuidString
        ])
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            try? await updateStatus(generationID: generationID, status: .failed)
            throw ChamakError(message: "The set creation pipeline didn't accept this request.")
        }

        if (200..<300).contains(http.statusCode) {
            return
        }

        if http.statusCode == 402 {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["detail"] as? [String: Any]
            let required = detail?["required"] as? Int ?? 0
            let balance = detail?["balance"] as? Int ?? 0
            let shortBy = detail?["short_by"] as? Int ?? max(0, required - balance)
            // DO NOT update status to .failed on 402!
            throw InsufficientCreditsError(required: required, balance: balance, shortBy: shortBy)
        }

        if http.statusCode == 401 {
            throw ChamakError(message: "Your session has expired. Please sign out and sign in again.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message: String
        if let detailStr = json?["detail"] as? String {
            message = detailStr
        } else if let detailObj = json?["detail"] as? [String: Any], let msg = detailObj["message"] as? String {
            message = msg
        } else if let msg = json?["message"] as? String {
            message = msg
        } else {
            message = "The set creation pipeline didn't accept this request."
        }

        try? await updateStatus(generationID: generationID, status: .failed)
        throw ChamakError(message: message)
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

    /// Signs many output paths in one request, keyed by the path as stored.
    ///
    /// The pipeline writes `output_image_url` as a bare path inside the private
    /// `chamak-outputs` bucket (`{wholesaler_id}/{generation_id}.png`), so
    /// `URL(string:)` on it yields a relative URL no loader can fetch — which is
    /// why every gallery tile stayed blank. A path that fails to sign is simply
    /// absent from the result; the tile shows its placeholder.
    static func getSignedURLs(paths: [String]) async -> [String: URL] {
        var urls: [String: URL] = [:]
        var toSign: [String: String] = [:]  // bucket-relative path → stored path

        for path in Set(paths) {
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                if let url = URL(string: path) { urls[path] = url }
            } else {
                toSign[path.replacingOccurrences(of: "chamak-outputs/", with: "")] = path
            }
        }
        guard !toSign.isEmpty else { return urls }

        do {
            let results = try await db.storage
                .from("chamak-outputs")
                .createSignedURLs(paths: Array(toSign.keys), expiresIn: 3600)
            for case let .success(signedPath, signedURL) in results {
                if let stored = toSign[signedPath] { urls[stored] = signedURL }
            }
        } catch {
            // Leave the tiles on their placeholder rather than failing the gallery.
        }
        return urls
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

        // An empty result is ambiguous in a way an error is not, and the
        // ambiguity is the whole bug.
        //
        // `SELECT` is gated by `auth.uid() = wholesaler_id`. When the SDK has
        // no session attached, the request goes out as `anon`, `auth.uid()` is
        // null, the policy matches nothing — and PostgREST answers 200 with
        // `[]`. Not an error. Nothing throws. The gallery renders "no
        // generations yet" to a wholesaler whose generations are sitting right
        // there in the table, and every layer reports success. Verified on the
        // simulator: a peek with no session shows the empty state, not a
        // failure.
        //
        // So an empty result has to be interrogated rather than trusted: with
        // no live session matching this id, the emptiness is an auth failure
        // wearing an empty table's clothes, and it gets said out loud.
        if rows.isEmpty {
            let session = try? await SupabaseManager.client.auth.session
            guard let session, session.user.id == wholesalerID else {
                throw ChamakError(message: "Your session isn't active on this device, so your gallery can't be read. Please sign out and sign in again.")
            }
        }

        return rows
    }
}
