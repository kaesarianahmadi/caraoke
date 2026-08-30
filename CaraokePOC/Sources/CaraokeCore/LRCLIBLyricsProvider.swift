import Foundation

/// LRCLIB-backed `LyricsRepository` (https://lrclib.net — free, keyless, open
/// to all applications per its own API docs).
///
/// Etiquette required by LRCLIB (implemented here):
/// - descriptive `User-Agent` on every request,
/// - honor `429` + `Retry-After` (self-imposed backoff until then),
/// - cache aggressively — this provider is cache-first when fresh and never
///   re-fetches a fresh entry.
///
/// Lookup order:
/// 1. fresh disk cache (≤ TTL) → return without network,
/// 2. `GET /api/get` (exact match incl. ±2 s duration),
/// 3. `GET /api/search` fallback → `TrackMatcher.bestMatch` picks the synced
///    candidate whose normalized title matches and whose duration is within
///    ±3 s,
/// 4. network failure → serve any cached copy (even stale) — an offline ride
///    beats a fresh fetch,
/// 5. nothing anywhere → `nil` (no synced lyrics for this track).
///
/// The stored cache entry is the normalized single-track JSON, so reparsing
/// never depends on which endpoint produced it. Swap this class out via
/// `LyricsRepository` without touching the UI or the Live Activity pipeline.
final class LRCLIBLyricsProvider: LyricsRepository {

    struct TrackResponse: Codable, Equatable {
        let id: Int
        let trackName: String
        let artistName: String
        let albumName: String?
        /// Seconds, per LRCLIB's API.
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static let defaultBase = URL(string: "https://lrclib.net")!

    private let base: URL
    private let session: URLSession
    private let cache: LyricsDiskCache
    let userAgent: String
    /// Injectable clock — the backoff logic is deterministic under test.
    var now: () -> Date
    private var nextAllowedRequestAt: Date?

    init(session: URLSession = .shared,
         cache: LyricsDiskCache = LyricsDiskCache(directory: LyricsDiskCache.defaultDirectory()),
         base: URL = LRCLIBLyricsProvider.defaultBase,
         // TODO: point at the real repo/site once it exists (LRCLIB asks for
         // name + version + link/email in the User-Agent).
         userAgent: String = "Caraoke/0.1 (https://github.com/caraoke/caraoke)",
         now: @escaping () -> Date = { Date() }) {
        self.base = base
        self.session = session
        self.cache = cache
        self.userAgent = userAgent
        self.now = now
    }

    // MARK: LyricsRepository

    func lyrics(for track: TrackSignature) async throws -> LyricTrack? {
        let key = TrackMatcher.signature(
            title: track.title, artist: track.artist, durationMs: track.durationMs
        )

        // 1) fresh cache — no network at all
        if let entry = cache.retrieve(for: key), cache.isFresh(entry, now: now()) {
            return try Self.parseLyrics(from: entry.body)
        }

        // 2) rate-limit backoff — serve stale if we have it, else surface it
        if let until = nextAllowedRequestAt, now() < until {
            if let entry = cache.retrieve(for: key) {
                return try Self.parseLyrics(from: entry.body)
            }
            throw LyricsError.rateLimited(until: until)
        }

        // 3) network: exact endpoint, then search fallback
        do {
            if let body = try await fetchExact(track) {
                cache.store(body, for: key, at: now())
                return try Self.parseLyrics(from: body)
            }
            if let body = try await fetchSearch(track) {
                cache.store(body, for: key, at: now())
                return try Self.parseLyrics(from: body)
            }
            return nil
        } catch let error as LyricsError {
            // A 429 shouldn't blank a ride that has any cached copy.
            if case .rateLimited(let until) = error {
                nextAllowedRequestAt = until
                if let entry = cache.retrieve(for: key) {
                    return try Self.parseLyrics(from: entry.body)
                }
            }
            throw error
        } catch {
            // 4) transport failure — stale-serving keeps offline rides alive
            if let entry = cache.retrieve(for: key) {
                return try Self.parseLyrics(from: entry.body)
            }
            throw LyricsError.network(error)
        }
    }

    // MARK: - Endpoints

    private func fetchExact(_ track: TrackSignature) async throws -> Data? {
        var components = URLComponents(url: base.appendingPathComponent("api/get"),
                                       resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if let album = track.album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let ms = track.durationMs, ms > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int((Double(ms) / 1000).rounded()))))
        }
        components.queryItems = items
        return try await fetchOne(at: components.url!)
    }

    private func fetchSearch(_ track: TrackSignature) async throws -> Data? {
        var components = URLComponents(url: base.appendingPathComponent("api/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        let (data, http) = try await perform(components.url!)
        try Self.checkStatus(http, now: now())
        guard http.statusCode == 200,
              let list = try? JSONDecoder().decode([TrackResponse].self, from: data)
        else { return nil }

        let candidates = list.map { response in
            LyricsCandidate(
                title: response.trackName,
                durationMs: response.duration.map { Int($0 * 1000.0) },
                hasSyncedLyrics: !(response.syncedLyrics?.isEmpty ?? true)
            )
        }
        guard let best = TrackMatcher.bestMatch(
            from: candidates, title: track.title, durationMs: track.durationMs
        ) else { return nil }
        guard let index = candidates.firstIndex(of: best) else { return nil }
        return try JSONEncoder().encode(list[index])
    }

    /// GET one track object; `nil` means "no match" (404 or unusable body).
    private func fetchOne(at url: URL) async throws -> Data? {
        let (data, http) = try await perform(url)
        try Self.checkStatus(http, now: now())
        guard http.statusCode == 200,
              let object = try? JSONDecoder().decode(TrackResponse.self, from: data)
        else { return nil }
        return try JSONEncoder().encode(object)
    }

    private func perform(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LyricsError.networkUnderlying("LRCLIB returned a non-HTTP response")
        }
        return (data, http)
    }

    private static func checkStatus(_ http: HTTPURLResponse, now: Date) throws {
        switch http.statusCode {
        case 200, 404:
            return
        case 429:
            // Default 60 s when the header is missing — honor the header when
            // present, per LRCLIB's requirements.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) } ?? 60
            throw LyricsError.rateLimited(until: now.addingTimeInterval(retryAfter))
        default:
            throw LyricsError.networkUnderlying("LRCLIB HTTP \(http.statusCode)")
        }
    }

    // MARK: - Parsing

    /// Synced lines only, per PRD D4 — plain-only and instrumental tracks are
    /// "no lyrics" for Caraoke's purposes.
    static func parseLyrics(from body: Data) throws -> LyricTrack? {
        let object = try JSONDecoder().decode(TrackResponse.self, from: body)
        guard !(object.instrumental ?? false),
              let synced = object.syncedLyrics, !synced.isEmpty
        else { return nil }
        let lines = LRCParser.parse(synced).map { LyricLine(startMs: $0.timeMs, text: $0.text) }
        guard !lines.isEmpty else { return nil }
        return LyricTrack(lines: lines)
    }
}
