import Foundation

/// Transport hardening for the Supabase client.
///
/// ## The failure this exists to stop
///
/// `*.supabase.co` responds with `alt-svc: h3=":443"; ma=86400`, so after the
/// first request iOS caches that advertisement for 24 hours and starts sending
/// subsequent requests over QUIC. When that QUIC connection stalls — common on
/// the Simulator, and on real networks behind middleboxes that mishandle UDP —
/// the symptoms are exactly:
///
///     _quic_packet_builder_calculate_size … none of those frames fit …
///     quic_conn_keepalive_handler … exceeding 2 outstanding keep-alives
///     nw_read_request_report [C1] Receive failed with "Operation timed out"
///     … 1 stalled, attempting fallback
///     HTTP load failed, 1257/0 bytes (error code: -1005)
///
/// which surfaces to the user as "The network connection was lost."
///
/// The endpoint itself is healthy throughout — the same request over TCP/HTTP-2
/// returns in ~200 ms. So this is a transport stall, not an outage, and the
/// correct response is to retry rather than to fail the write.
///
/// Retrying matters for correctness here, not just polish: the AI pipeline
/// creates the `products` row *before* the app claims it with `saveProduct`. If
/// that claim is lost, the row is left orphaned with a null `wholesaler_id` and
/// the wholesaler's upload silently disappears from their catalogue.
enum JewelNetwork {

    /// A session that does not share `URLSession.shared`'s connection and
    /// Alt-Svc caches, so a poisoned QUIC route cannot wedge every request in
    /// the app, and a stalled connection is abandoned rather than hung on.
    static let supabaseSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        // Prefer waiting briefly for connectivity over failing instantly when
        // the device is mid-handover.
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Errors that mean "the pipe broke", as opposed to "the server said no".
    /// Only these are worth retrying — a 4xx will fail identically every time.
    static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,      // -1005, the QUIC stall above
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .secureConnectionFailed,
             .badServerResponse:
            return true
        default:
            return false
        }
    }

    /// Runs `operation`, retrying transient transport failures with backoff.
    ///
    /// The delay gives the system time to give up on the stalled QUIC route and
    /// fall back to TCP, which is what makes the second attempt succeed.
    static func withRetry<T: Sendable>(
        attempts: Int = 3,
        initialDelay: Duration = .milliseconds(400),
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var delay = initialDelay
        var lastError: Error?

        for attempt in 1...max(1, attempts) {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard isTransient(error), attempt < attempts else { throw error }
                try? await Task.sleep(for: delay)
                delay = delay * 2
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}
