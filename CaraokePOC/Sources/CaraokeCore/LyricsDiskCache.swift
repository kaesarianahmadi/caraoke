import Foundation

/// One cached lyrics record: the raw provider response for a track, stored
/// with a timestamp so freshness is decidable at read time.
struct CachedLyrics: Codable, Equatable {
    let storedAt: Date
    let body: Data
}

/// Disk cache for the lyrics layer. Design rules (all deliberate):
/// - **Cache-first when fresh** — replays and repeat rides never hit the
///   network (LRCLIB asks for considerate clients; freshness = faster UI).
/// - **Stale entries are served on network failure, never deleted** — the
///   "offline ride" case is more valuable than the 30-day TTL.
/// - The TTL only decides whether a fresh fetch is attempted.
final class LyricsDiskCache {
    let directory: URL
    let ttl: TimeInterval

    /// - Parameters:
    ///   - directory: injectable so tests use a temp dir; production uses the
    ///     app's Caches directory (OS may purge it under storage pressure —
    ///     acceptable, entries are refetchable).
    ///   - ttl: freshness window; 30 days follows the project's caching policy.
    init(directory: URL, ttl: TimeInterval = 30 * 24 * 3600) {
        self.directory = directory
        self.ttl = ttl
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Convenience: the production cache directory inside the app sandbox.
    static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("lyrics", isDirectory: true)
    }

    private func fileURL(for key: String) -> URL {
        // The signature contains "|" — percent-encode to a single safe token.
        let token = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return directory.appendingPathComponent("\(token).json")
    }

    func store(_ body: Data, for key: String, at date: Date = Date()) {
        let entry = CachedLyrics(storedAt: date, body: body)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func retrieve(for key: String) -> CachedLyrics? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(CachedLyrics.self, from: data)
        else { return nil }
        return entry
    }

    func isFresh(_ entry: CachedLyrics, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.storedAt) < ttl
    }

    /// Settings-screen action: drop every cached entry.
    func clearAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
