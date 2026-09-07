//
//  PromptConfig.swift
//  voila
//
//  Produces the stylist instruction string for OutfitAnalyzer, preferring the
//  copy served by the API so the prompt can change without an App Store release.
//  Every failure path falls back, so the app behaves exactly as it does today
//  when the server is unreachable.
//

import Foundation

/// The deployed prompt endpoint. The only place the host appears — point this at
/// a different server and nothing else in the app needs to change.
private let promptEndpoint = URL(string: "https://voila-api-production-ed88.up.railway.app/config/prompt")!

actor PromptConfig {
    static let shared = PromptConfig()

    /// The payload served by `GET /config/prompt`.
    private struct Payload: Codable {
        var version: Int
        var instructions: String
        var updatedAt: Date
    }

    private static let cacheKey = "promptConfig.payload"
    private static let fetchTimeout: TimeInterval = 3

    /// The best instruction text resolved so far, if any.
    private var payload: Payload?

    private init() {
        payload = Self.loadCached()
    }

    // MARK: - Reading

    /// The instructions to open a `LanguageModelSession` with.
    ///
    /// Returns immediately with whatever has been resolved: the fetched text if a
    /// refresh has landed, otherwise the last cached text, otherwise the copy
    /// compiled into the app. Deliberately never starts or waits on a fetch — the
    /// analyze path must not block on the network.
    func instructions() -> String {
        payload?.instructions ?? OutfitAnalyzer.instructions
    }

    // MARK: - Fetching

    /// Fetches the current prompt and caches it. Best effort: on any failure the
    /// previously resolved value stays in place and nothing is surfaced to the user.
    func refresh() async {
        var request = URLRequest(url: promptEndpoint)
        request.timeoutInterval = Self.fetchTimeout
        // We keep our own cache and want whatever the edge is serving now, so
        // URLSession's cache would only add a second layer of staleness.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let fetched = try decoder.decode(Payload.self, from: data)

            // A stale edge node can serve an older copy than the one already held;
            // don't let it overwrite newer text.
            guard fetched.version >= (payload?.version ?? Int.min) else { return }

            payload = fetched
            store(fetched)
        } catch {
            // Offline, timed out, non-200, or malformed: keep what we have.
        }
    }

    // MARK: - Cache

    // The cache is our own storage format, so it uses the default coding rather
    // than the snake-case/ISO-8601 decoder the wire payload needs. Encode and
    // decode here must stay a matched pair.

    private static func loadCached() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func store(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}
