import Foundation

// Cross-process state shared by the app, the widget extension and the Live
// Activity: the now-playing payload, the widget configuration, and the pure
// timeline math that turns the payload into WidgetKit entries. Kept in
// CaraokeCore (Foundation only) so the timeline is unit-testable and the
// widget extension compiles it without the iOS layer.

// MARK: - Payload

struct SharedLyricLine: Codable, Hashable, Sendable {
    var timeMs: Int
    var text: String
    /// Optional translation of this line (only some providers supply one).
    var translation: String?

    init(timeMs: Int, text: String, translation: String? = nil) {
        self.timeMs = timeMs
        self.text = text
        self.translation = translation
    }
}

/// Everything a widget needs to render AND keep advancing without the app:
/// the full timed lyric list plus the track's wall-clock start, so the widget
/// extrapolates the current line itself instead of waiting for a reload.
struct SharedWidgetPayload: Codable, Sendable {
    var title: String
    var artist: String
    var currentLine: String
    var currentTranslation: String?
    var previousLines: [String]
    var nextLine: String?
    var upcomingLines: [String]
    var isPlaying: Bool
    var progress: Double
    var status: String
    /// Wall-clock epoch (ms) the track started at, or 0 when unknown.
    var trackStartEpochMs: Int
    var durationMs: Int
    var lines: [SharedLyricLine]
    var artworkData: Data?
    /// Average colour of the cover as `RRGGBB` — the large widget paints its
    /// background from this so it follows the song.
    var artworkColorHex: String?
    /// Which player the transport buttons must drive: `appleMusic` / `spotify`.
    var source: String

    init(title: String,
         artist: String,
         currentLine: String,
         currentTranslation: String? = nil,
         previousLines: [String] = [],
         nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool,
         progress: Double,
         status: String,
         trackStartEpochMs: Int = 0,
         durationMs: Int = 0,
         lines: [SharedLyricLine] = [],
         artworkData: Data? = nil,
         artworkColorHex: String? = nil,
         source: String = "appleMusic") {
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.currentTranslation = currentTranslation
        self.previousLines = previousLines
        self.nextLine = nextLine
        self.upcomingLines = upcomingLines.isEmpty ? (nextLine.map { [$0] } ?? []) : upcomingLines
        self.isPlaying = isPlaying
        self.progress = progress
        self.status = status
        self.trackStartEpochMs = trackStartEpochMs
        self.durationMs = durationMs
        self.lines = lines
        self.artworkData = artworkData
        self.artworkColorHex = artworkColorHex
        self.source = source
    }
}

// MARK: - Widget configuration (shared, not per-process UserDefaults)

struct SharedWidgetSettings: Codable, Sendable, Equatable {
    var theme: String
    var coverStyle: String
    var showLyrics: Bool
    var showRefresh: Bool
    var showTranslation: Bool

    init(theme: String = "artwork",
         coverStyle: String = "vinyl",
         showLyrics: Bool = true,
         showRefresh: Bool = true,
         showTranslation: Bool = false) {
        self.theme = theme
        self.coverStyle = coverStyle
        self.showLyrics = showLyrics
        self.showRefresh = showRefresh
        self.showTranslation = showTranslation
    }
}

// MARK: - Timeline

/// One lyric row-set the widget renders. `lineIndex` is the identity WidgetKit
/// uses to push the new line in from the bottom.
struct WidgetTimelineEntry: Equatable, Sendable {
    let date: Date
    let lineIndex: Int?
    let currentLine: String
    let currentTranslation: String?
    let previousLines: [String]
    let nextLine: String?
    let upcomingLines: [String]
    let progress: Double
}

enum WidgetTimelineBuilder {
    /// WidgetKit caps a timeline at 100 entries; stay under it and let the
    /// `.after` policy refill before the tail runs out.
    static let maxEntries = 80
    static let upcomingShown = 6

    /// Entries from `now` forward. Empty lyrics / paused / non-playing states
    /// produce a single static entry (nothing to advance).
    static func entries(for payload: SharedWidgetPayload,
                        now: Date,
                        limit: Int = maxEntries) -> [WidgetTimelineEntry] {
        let lines = payload.lines
        guard payload.isPlaying,
              payload.status == LyricStatus.playing.rawValue,
              !lines.isEmpty else {
            return [staticEntry(payload: payload, now: now)]
        }

        let startEpoch = Double(payload.trackStartEpochMs) / 1000.0
        guard startEpoch > 0 else {
            return [staticEntry(payload: payload, now: now)]
        }
        let positionMs = max(0, Int((now.timeIntervalSince1970 - startEpoch) * 1000.0))

        // The song has run past its own length and nothing updated the payload
        // (app suspended or killed) — stop advancing instead of drifting into
        // lines that are no longer playing.
        if payload.durationMs > 0, positionMs > payload.durationMs + 5_000 {
            return [staticEntry(payload: payload, now: now)]
        }

        var startIndex = 0
        for (index, line) in lines.enumerated() {
            if line.timeMs <= positionMs { startIndex = index } else { break }
        }

        let end = min(lines.count, startIndex + limit)
        var entries: [WidgetTimelineEntry] = []
        entries.reserveCapacity(end - startIndex)

        for index in startIndex..<end {
            let line = lines[index]
            let lineDate = Date(timeIntervalSince1970: startEpoch + Double(line.timeMs) / 1000.0)
            let previous = index > 0 ? Array(lines[max(0, index - 2)..<index].map(\.text)) : []
            let upcoming = Array(lines.dropFirst(index + 1).prefix(upcomingShown).map(\.text))
            let progress = payload.durationMs > 0
                ? min(1.0, Double(line.timeMs) / Double(payload.durationMs))
                : 0.0
            entries.append(WidgetTimelineEntry(
                date: max(lineDate, now),
                lineIndex: index,
                currentLine: line.text,
                currentTranslation: line.translation,
                previousLines: previous,
                nextLine: upcoming.first,
                upcomingLines: upcoming,
                progress: progress
            ))
        }
        return entries.isEmpty ? [staticEntry(payload: payload, now: now)] : entries
    }

    private static func staticEntry(payload: SharedWidgetPayload, now: Date) -> WidgetTimelineEntry {
        WidgetTimelineEntry(
            date: now,
            lineIndex: payload.lines.firstIndex { $0.text == payload.currentLine },
            currentLine: payload.currentLine,
            currentTranslation: payload.currentTranslation,
            previousLines: payload.previousLines,
            nextLine: payload.nextLine,
            upcomingLines: payload.upcomingLines,
            progress: payload.progress
        )
    }

    /// Position the widget believes playback is at — used to detect a stale
    /// payload (the app was killed mid-song) so the widget can stop advancing.
    static func positionMs(for payload: SharedWidgetPayload, now: Date) -> Int {
        guard payload.trackStartEpochMs > 0 else { return 0 }
        return max(0, Int(now.timeIntervalSince1970 * 1000) - payload.trackStartEpochMs)
    }
}
