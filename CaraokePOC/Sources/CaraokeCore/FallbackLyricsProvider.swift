import Foundation

/// Fallback lyrics provider that cascades through multiple open providers:
/// 1. LRCLIB (primary synced library, fast & keyless)
/// 2. NetEase Open Endpoint (secondary fallback, zero cost, massive global & Asian pop coverage)
/// 3. Returns nil gracefully if unavailable anywhere
final class FallbackLyricsProvider: LyricsRepository {
    private let lrclib: LRCLIBLyricsProvider
    private let session: URLSession

    init(session: URLSession = .shared, lrclib: LRCLIBLyricsProvider = LRCLIBLyricsProvider()) {
        self.session = session
        self.lrclib = lrclib
    }

    func lyrics(for track: TrackSignature) async throws -> LyricTrack? {
        // 1. Try primary LRCLIB
        do {
            if let result = try await lrclib.lyrics(for: track) {
                return result
            }
        } catch {
            // If LRCLIB fails with rate limit or network, proceed to fallback
        }

        // 2. Try secondary NetEase fallback
        if let fallback = await fetchNetEaseLyrics(for: track) {
            return fallback
        }

        return nil
    }

    // MARK: - NetEase Secondary Provider (Zero-cost, keyless open endpoint)

    private struct NetEaseSearchResponse: Decodable {
        struct Result: Decodable {
            struct Song: Decodable {
                let id: Int
                let name: String
            }
            let songs: [Song]?
        }
        let result: Result?
    }

    private struct NetEaseLyricResponse: Decodable {
        struct LyricData: Decodable {
            let lyric: String?
        }
        let lrc: LyricData?
        /// Translated lines, same LRC shape (empty when none exist).
        let tlyric: LyricData?
    }

    private func fetchNetEaseLyrics(for track: TrackSignature) async -> LyricTrack? {
        let query = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://music.163.com/api/search/get?s=\(encodedQuery)&type=1&offset=0&limit=3")
        else { return nil }

        var searchReq = URLRequest(url: searchURL)
        searchReq.timeoutInterval = 6
        searchReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (searchData, searchResp) = try? await session.data(for: searchReq),
              (searchResp as? HTTPURLResponse)?.statusCode == 200,
              let searchResult = try? JSONDecoder().decode(NetEaseSearchResponse.self, from: searchData),
              let firstSong = searchResult.result?.songs?.first
        else { return nil }

        guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(firstSong.id)&lv=1&kv=1&tv=-1") else { return nil }
        var lyricReq = URLRequest(url: lyricURL)
        lyricReq.timeoutInterval = 6
        lyricReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (lyricData, lyricResp) = try? await session.data(for: lyricReq),
              (lyricResp as? HTTPURLResponse)?.statusCode == 200,
              let lyricObj = try? JSONDecoder().decode(NetEaseLyricResponse.self, from: lyricData),
              let rawLrc = lyricObj.lrc?.lyric, !rawLrc.isEmpty
        else { return nil }

        // Translations arrive as a second LRC; key them by timestamp so each
        // line can carry its own.
        var translations: [Int: String] = [:]
        if let rawTranslation = lyricObj.tlyric?.lyric, !rawTranslation.isEmpty {
            for line in LRCParser.parse(rawTranslation) where !line.text.isEmpty {
                translations[line.timeMs] = line.text
            }
        }

        let parsedLines = LRCParser.parse(rawLrc).map {
            LyricLine(startMs: $0.timeMs, text: $0.text, translation: translations[$0.timeMs])
        }
        guard !parsedLines.isEmpty else { return nil }
        return LyricTrack(lines: parsedLines)
    }
}
