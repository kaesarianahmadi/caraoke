import Foundation

/// Fallback lyrics provider that cascades through multiple open providers:
/// 1. LRCLIB (primary synced library, fast & keyless)
/// 2. NetEase Open Endpoint (secondary fallback, zero cost, massive global & Asian pop coverage)
/// 3. Returns nil gracefully if unavailable anywhere
///
/// The fallback is strict on purpose: a wrong lyric is worse than no lyric.
/// NetEase ranks by its own relevance and serves covers, re-uploads and
/// Mandarin translations, so a candidate is accepted only when its title,
/// artist and duration all agree with the track that is actually playing.
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
                struct Artist: Decodable {
                    let name: String
                }
                let id: Int
                let name: String
                /// Milliseconds.
                let duration: Int?
                let artists: [Artist]?
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
              let songs = searchResult.result?.songs, !songs.isEmpty
        else { return nil }

        let candidates = songs.map {
            LyricsCandidate(title: $0.name, durationMs: $0.duration, hasSyncedLyrics: true)
        }
        guard let match = TrackMatcher.bestMatch(from: candidates, title: track.title,
                                                 durationMs: track.durationMs),
              let index = candidates.firstIndex(of: match),
              artistMatches(songs[index].artists?.map(\.name) ?? [], track.artist)
        else { return nil }
        let song = songs[index]

        guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(song.id)&lv=1&kv=1&tv=-1") else { return nil }
        var lyricReq = URLRequest(url: lyricURL)
        lyricReq.timeoutInterval = 6
        lyricReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (lyricData, lyricResp) = try? await session.data(for: lyricReq),
              (lyricResp as? HTTPURLResponse)?.statusCode == 200,
              let lyricObj = try? JSONDecoder().decode(NetEaseLyricResponse.self, from: lyricData),
              let rawLrc = lyricObj.lrc?.lyric, !rawLrc.isEmpty
        else { return nil }

        // NetEase opens every LRC with credit rows ("作词 : …", "作曲 : …") that
        // would otherwise render as lyric lines at 0.0 s.
        let parsedLines = LRCParser.parse(rawLrc)
            .filter { !isCredit($0.text) }
            .map { LyricLine(startMs: $0.timeMs, text: $0.text) }
        guard !parsedLines.isEmpty,
              !isScriptMismatch(title: track.title, artist: track.artist, lines: parsedLines)
        else { return nil }
        return LyricTrack(lines: parsedLines)
    }

    /// NetEase results carry a list of artists; at least one must be ours.
    private func artistMatches(_ names: [String], _ artist: String) -> Bool {
        let wanted = TrackMatcher.normalizeArtist(artist)
        guard !wanted.isEmpty else { return true }
        return names.contains { name in
            let candidate = TrackMatcher.normalizeArtist(name)
            guard !candidate.isEmpty else { return false }
            return candidate.contains(wanted) || wanted.contains(candidate)
        }
    }

    private static let creditPrefixes = [
        "作词", "作曲", "编曲", "制作人", "混音", "母带", "录音", "监制", "出品",
        "吉他", "贝斯", "鼓", "钢琴", "和声", "人声", "弦乐", "OP", "SP",
    ]

    private func isCredit(_ text: String) -> Bool {
        guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let head = text[text.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        return Self.creditPrefixes.contains { $0.caseInsensitiveCompare(head) == .orderedSame }
    }

    /// A Latin-script track must never be paired with mostly-CJK lyrics: that
    /// is a cover or a translation, not the song the user is playing.
    private func isScriptMismatch(title: String, artist: String, lines: [LyricLine]) -> Bool {
        guard !containsCJK(title + artist) else { return false }
        let scalars = lines.map(\.text).joined().unicodeScalars
        guard !scalars.isEmpty else { return false }
        let cjk = scalars.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) }
        return Double(cjk.count) / Double(scalars.count) > 0.4
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) }
    }
}
