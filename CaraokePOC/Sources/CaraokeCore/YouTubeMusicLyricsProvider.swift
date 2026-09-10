import Foundation

/// YouTube Music (InnerTube API)-backed `LyricsRepository`.
/// Keyless, zero-cost, syndicates licensed Musixmatch and LyricFind lyrics.
/// 3-step retrieval pipeline:
/// 1. POST /youtubei/v1/search (find song videoId)
/// 2. POST /youtubei/v1/next (find lyrics browseId)
/// 3. POST /youtubei/v1/browse (extract timed lyrics cues)
final class YouTubeMusicLyricsProvider: LyricsRepository {
    private static let defaultAPIKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private static let defaultBaseURL = URL(string: "https://music.youtube.com/youtubei/v1")!

    private let session: URLSession
    private let cache: LyricsDiskCache?
    private let apiKey: String
    private let baseURL: URL

    init(session: URLSession = .shared,
         cache: LyricsDiskCache? = nil,
         apiKey: String = YouTubeMusicLyricsProvider.defaultAPIKey,
         baseURL: URL = YouTubeMusicLyricsProvider.defaultBaseURL) {
        self.session = session
        self.cache = cache
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func lyrics(for track: TrackSignature) async throws -> LyricTrack? {
        let key = TrackMatcher.signature(title: track.title, artist: track.artist, durationMs: track.durationMs)
        if let cache, let entry = cache.retrieve(for: key), cache.isFresh(entry) {
            if let lines = try? JSONDecoder().decode([LyricLine].self, from: entry.body), !lines.isEmpty {
                return LyricTrack(lines: lines)
            }
        }

        guard let videoId = await searchVideoId(for: track) else { return nil }
        guard let browseId = await fetchLyricsBrowseId(for: videoId) else { return nil }
        guard let lyricTrack = await fetchTimedLyrics(browseId: browseId) else { return nil }

        if let cache, let encoded = try? JSONEncoder().encode(lyricTrack.lines) {
            cache.store(encoded, for: key)
        }
        return lyricTrack
    }

    // MARK: - Step 1: Search

    private func searchVideoId(for track: TrackSignature) async -> String? {
        guard let url = URL(string: "\(baseURL.absoluteString)/search?key=\(apiKey)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240101.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": "\(track.title) \(track.artist)",
            "params": "Eg-KAQwIARAAGAAgACgAMABqChAEEAUQAxAKEAk="
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = bodyData

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let candidates = parseSearchCandidates(from: root)
        guard let match = TrackMatcher.bestMatch(from: candidates.map(\.candidate),
                                                 title: track.title,
                                                 durationMs: track.durationMs),
              let chosen = candidates.first(where: { $0.candidate == match })
        else { return nil }

        return chosen.videoId
    }

    private struct ParsedCandidate {
        let candidate: LyricsCandidate
        let videoId: String
    }

    private func parseSearchCandidates(from root: [String: Any]) -> [ParsedCandidate] {
        var results: [ParsedCandidate] = []
        guard let contents = root["contents"] as? [String: Any],
              let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
              let tabs = tabbed["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        for sec in sections {
            guard let shelf = sec["musicShelfRenderer"] as? [String: Any],
                  let items = shelf["contents"] as? [[String: Any]]
            else { continue }

            for item in items {
                guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }

                var videoId: String?
                if let overlay = renderer["overlay"] as? [String: Any],
                   let thumb = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                   let playContent = thumb["content"] as? [String: Any],
                   let btn = playContent["musicPlayButtonRenderer"] as? [String: Any],
                   let nav = btn["playNavigationEndpoint"] as? [String: Any],
                   let watch = nav["watchEndpoint"] as? [String: Any] {
                    videoId = watch["videoId"] as? String
                }
                if videoId == nil,
                   let nav = renderer["navigationEndpoint"] as? [String: Any],
                   let watch = nav["watchEndpoint"] as? [String: Any] {
                    videoId = watch["videoId"] as? String
                }
                guard let vId = videoId else { continue }

                guard let cols = renderer["flexColumns"] as? [[String: Any]], cols.count >= 2 else { continue }
                let col0 = cols[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                let titleRuns = (col0?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
                let title = titleRuns?.compactMap { $0["text"] as? String }.joined() ?? ""

                let col1 = cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                let subRuns = (col1?["text"] as? [String: Any])?["runs"] as? [[String: Any]]

                var durationMs: Int?
                if let lastText = subRuns?.last?["text"] as? String {
                    let parts = lastText.split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2 {
                        durationMs = (parts[0] * 60 + parts[1]) * 1000
                    } else if parts.count == 3 {
                        durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000
                    }
                }

                let candidate = LyricsCandidate(title: title, durationMs: durationMs, hasSyncedLyrics: true)
                results.append(ParsedCandidate(candidate: candidate, videoId: vId))
            }
        }
        return results
    }

    // MARK: - Step 2: Next (Find Lyrics Tab)

    private func fetchLyricsBrowseId(for videoId: String) async -> String? {
        guard let url = URL(string: "\(baseURL.absoluteString)/next?key=\(apiKey)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20240101.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = bodyData

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let contents = root["contents"] as? [String: Any],
              let singleCol = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbed = singleCol["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbed["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]]
        else { return nil }

        for tab in tabs {
            guard let tabRenderer = tab["tabRenderer"] as? [String: Any] else { continue }
            if let unsel = tabRenderer["unselectable"] as? Bool, unsel { continue }
            let title = tabRenderer["title"] as? String ?? ""
            if let endpoint = tabRenderer["endpoint"] as? [String: Any],
               let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                if browseId.hasPrefix("MPLY") ||
                   title.localizedCaseInsensitiveContains("lyrics") ||
                   title.localizedCaseInsensitiveContains("lirik") {
                    return browseId
                }
            }
        }
        return nil
    }

    // MARK: - Step 3: Browse (Timed Lyrics)

    private func fetchTimedLyrics(browseId: String) async -> LyricTrack? {
        guard let url = URL(string: "\(baseURL.absoluteString)/browse?key=\(apiKey)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID_MUSIC",
                    "clientVersion": "7.03.52",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "browseId": browseId
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = bodyData

        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let contents = root["contents"] as? [String: Any],
              let elementRenderer = contents["elementRenderer"] as? [String: Any],
              let newElement = elementRenderer["newElement"] as? [String: Any],
              let typeObj = newElement["type"] as? [String: Any],
              let componentType = typeObj["componentType"] as? [String: Any],
              let model = componentType["model"] as? [String: Any],
              let timedLyricsModel = model["timedLyricsModel"] as? [String: Any],
              let lyricsData = timedLyricsModel["lyricsData"] as? [String: Any],
              let timedLyricsData = lyricsData["timedLyricsData"] as? [[String: Any]]
        else { return nil }

        var rawLines: [LyricLine] = []
        for cue in timedLyricsData {
            let text = (cue["lyricLine"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !text.isEmpty else { continue }
            guard let cueRange = cue["cueRange"] as? [String: Any],
                  let startStr = cueRange["startTimeMilliseconds"] as? String,
                  let startMs = Int(startStr)
            else { continue }
            rawLines.append(LyricLine(startMs: startMs, text: text))
        }

        guard !rawLines.isEmpty else { return nil }

        rawLines.sort { $0.startMs < $1.startMs }
        var cleanLines: [LyricLine] = []
        var lastMs = -1
        for line in rawLines {
            var ms = line.startMs
            if ms <= lastMs {
                ms = lastMs + 1
            }
            cleanLines.append(LyricLine(startMs: ms, text: line.text))
            lastMs = ms
        }

        return LyricTrack(lines: cleanLines)
    }
}
