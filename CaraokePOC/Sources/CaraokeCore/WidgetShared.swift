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
    /// Wall-clock epoch (ms) until which the widget pulses its cover because a
    /// resync is in flight (0 = not resyncing).
    var resyncingUntilMs: Int
    /// Chained next-song continuation (0 = nothing chained). When the app can
    /// see what plays next it appends that track's lines to `lines`, offset
    /// from `trackStartEpochMs` like every other line, and records where the
    /// boundary sits — so one timeline carries the song change with no reload,
    /// no wake and no budget.
    var nextStartMs: Int
    var nextDurationMs: Int
    var nextTitle: String
    var nextArtist: String
    /// The chained song's own cover. Needed because the timeline is baked
    /// across the boundary: without this the entry's header switches to the
    /// next song while the art stays on the one that already ended.
    var nextArtworkData: Data?
    var nextArtworkColorHex: String?

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
         source: String = "appleMusic",
         resyncingUntilMs: Int = 0,
         nextStartMs: Int = 0,
         nextDurationMs: Int = 0,
         nextTitle: String = "",
         nextArtist: String = "",
         nextArtworkData: Data? = nil,
         nextArtworkColorHex: String? = nil) {
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
        self.resyncingUntilMs = resyncingUntilMs
        self.nextStartMs = nextStartMs
        self.nextDurationMs = nextDurationMs
        self.nextTitle = nextTitle
        self.nextArtist = nextArtist
        self.nextArtworkData = nextArtworkData
        self.nextArtworkColorHex = nextArtworkColorHex
    }

    /// Total span `lines` covers: one song, or two when the next one is chained.
    var chainedSpanMs: Int {
        nextStartMs > 0 && nextDurationMs > 0 ? nextStartMs + nextDurationMs : durationMs
    }

    /// Which cover an entry paints. A chained entry belongs to the next song
    /// and must show its art; when the queue entry carried no image the current
    /// song's cover is a better answer than a blank — the same degradation the
    /// tile had before chaining existed.
    func cover(forChainedEntry chained: Bool) -> (data: Data?, hex: String?) {
        guard chained else { return (artworkData, artworkColorHex) }
        return (nextArtworkData ?? artworkData, nextArtworkColorHex ?? artworkColorHex)
    }
}

// MARK: - Widget configuration (shared, not per-process UserDefaults)

/// Theme + cover style only. The show-lyrics / refresh / translation toggles
/// are gone: lyrics are the widget's whole point, the cover itself is the
/// resync button, and a translation rides along with its line.
struct SharedWidgetSettings: Codable, Sendable, Equatable {
    var theme: String
    var coverStyle: String

    init(theme: String = "artwork", coverStyle: String = "vinyl") {
        self.theme = theme
        self.coverStyle = coverStyle
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
    /// Cover opacity for this entry: 1 normally, lower while a resync pulses.
    var resyncPulse: Double = 1
    /// This entry belongs to the chained next song, so the header switches
    /// title/artist along with the lyrics.
    var isNextTrack: Bool = false
    /// Terminal "the timeline is spent" entry. The tile renders it as a resync
    /// affordance instead of lyrics.
    var isExpired: Bool = false
}

enum WidgetTimelineBuilder {
    /// WidgetKit caps a timeline at 100 entries; stay under it and let the
    /// `.after` policy refill before the tail runs out.
    static let maxEntries = 80
    static let upcomingShown = 6

    /// How long after the payload's span runs out the tile flips to its
    /// "out of date" resync affordance. Long enough that a gapless song change
    /// never flickers through it, short enough that a genuinely dead payload
    /// announces itself instead of looking like a frozen song.
    static let expiredSlackMs = 20_000

    /// Pulse cadence for an in-flight resync. WidgetKit renders static
    /// snapshots, so the fade in/out is emitted as alternating entries.
    static let resyncPulseStep: TimeInterval = 0.45
    static let resyncPulseLow = 0.3
    /// Longest pulse tail a single timeline carries.
    static let resyncPulseWindowMs = 20_000

    /// Entries from `now` forward. Empty lyrics / paused / non-playing states
    /// produce a single static entry (nothing to advance). A payload flagged
    /// as resyncing leads with the cover pulse, then hands back to the normal
    /// lyric entries so the widget recovers without another reload.
    static func entries(for payload: SharedWidgetPayload,
                        now: Date,
                        limit: Int = maxEntries,
                        includeOutro: Bool = false) -> [WidgetTimelineEntry] {
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        guard payload.resyncingUntilMs > nowMs else {
            return contentEntries(for: payload, now: now, limit: limit, includeOutro: includeOutro)
        }
        let endMs = min(payload.resyncingUntilMs, nowMs + resyncPulseWindowMs)
        var pulse: [WidgetTimelineEntry] = []
        var cursorMs = nowMs
        var index = 0
        while cursorMs < endMs, pulse.count < limit {
            let date = Date(timeIntervalSince1970: Double(cursorMs) / 1000)
            pulse.append(staticEntry(payload: payload, now: date,
                                     resyncPulse: index % 2 == 0 ? 1 : resyncPulseLow))
            cursorMs += Int(resyncPulseStep * 1000)
            index += 1
        }
        let tail = contentEntries(for: payload,
                                  now: Date(timeIntervalSince1970: Double(endMs) / 1000),
                                  limit: max(1, limit - pulse.count),
                                  includeOutro: includeOutro)
        return pulse + tail
    }

    /// The lyric timeline itself.
    static func contentEntries(for payload: SharedWidgetPayload,
                               now: Date,
                               limit: Int = maxEntries,
                               includeOutro: Bool = false) -> [WidgetTimelineEntry] {
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

        // The payload has run past the end of everything it describes and
        // nothing updated it (app suspended or killed) — stop advancing
        // instead of drifting into lines that are no longer playing.
        if payload.chainedSpanMs > 0, positionMs > payload.chainedSpanMs + 5_000 {
            return [staticEntry(payload: payload, now: now)]
        }

        var startIndex = 0
        for (index, line) in lines.enumerated() {
            if line.timeMs <= positionMs { startIndex = index } else { break }
        }

        let end = min(lines.count, startIndex + limit)
        var entries: [WidgetTimelineEntry] = []
        entries.reserveCapacity(end - startIndex + 2)

        // Intro entry for track start before first lyric
        if let firstLine = lines.first, positionMs < firstLine.timeMs {
            let introUpcoming = Array(lines.prefix(upcomingShown).map(\.text))
            entries.append(WidgetTimelineEntry(
                date: now,
                lineIndex: nil,
                currentLine: "",
                currentTranslation: nil,
                previousLines: [],
                nextLine: introUpcoming.first,
                upcomingLines: introUpcoming,
                // Elapsed fraction, not 0: a long instrumental intro otherwise
                // pins the bar at zero and then jumps when the first lyric lands.
                progress: progressFraction(for: positionMs, payload: payload),
                isNextTrack: false
            ))
        }

        // Chained next-track intro entry before its first lyric
        if payload.nextStartMs > 0,
           let nextTrackIndex = lines.firstIndex(where: { $0.timeMs >= payload.nextStartMs }) {
            let nextLine = lines[nextTrackIndex]
            if nextLine.timeMs > payload.nextStartMs {
                let nextStartDate = Date(timeIntervalSince1970: startEpoch + Double(payload.nextStartMs) / 1000.0)
                if nextStartDate > now {
                    let nextUpcoming = Array(lines.dropFirst(nextTrackIndex).prefix(upcomingShown).map(\.text))
                    entries.append(WidgetTimelineEntry(
                        date: nextStartDate,
                        lineIndex: nil,
                        currentLine: "",
                        currentTranslation: nil,
                        previousLines: [],
                        nextLine: nextUpcoming.first,
                        upcomingLines: nextUpcoming,
                        progress: 0.0,
                        isNextTrack: true
                    ))
                }
            }
        }

        for index in startIndex..<end {
            let line = lines[index]
            let lineDate = Date(timeIntervalSince1970: startEpoch + Double(line.timeMs) / 1000.0)
            let previous = index > 0 ? Array(lines[max(0, index - 2)..<index].map(\.text)) : []
            let upcoming = Array(lines.dropFirst(index + 1).prefix(upcomingShown).map(\.text))
            entries.append(WidgetTimelineEntry(
                date: max(lineDate, now),
                lineIndex: index,
                currentLine: line.text,
                currentTranslation: line.translation,
                previousLines: previous,
                nextLine: upcoming.first,
                upcomingLines: upcoming,
                progress: progressFraction(for: line.timeMs, payload: payload),
                isNextTrack: payload.nextStartMs > 0 && line.timeMs >= payload.nextStartMs
            ))
        }

        // Outro entries: after the final lyric line, shift it up into previous,
        // then clear all lines so the widget smoothly scrolls off and disappears.
        if includeOutro, end == lines.count, let lastLine = lines.last {
            let stage1Date = Date(timeIntervalSince1970: startEpoch + Double(lastLine.timeMs + 7000) / 1000.0)
            if stage1Date > now {
                entries.append(WidgetTimelineEntry(
                    date: stage1Date,
                    lineIndex: lines.count,
                    currentLine: "",
                    currentTranslation: nil,
                    previousLines: [lastLine.text],
                    nextLine: nil,
                    upcomingLines: [],
                    progress: progressFraction(for: lastLine.timeMs + 7000, payload: payload)
                ))
            }
            let stage2Date = Date(timeIntervalSince1970: startEpoch + Double(lastLine.timeMs + 10000) / 1000.0)
            if stage2Date > now {
                entries.append(WidgetTimelineEntry(
                    date: stage2Date,
                    lineIndex: lines.count + 1,
                    currentLine: "",
                    currentTranslation: nil,
                    previousLines: [],
                    nextLine: nil,
                    upcomingLines: [],
                    progress: 1.0
                ))
            }
            // Terminal entry: past the end of everything the payload covers, so
            // the tile flips itself to "tap to resync" with no reload and no
            // budget spend. Only appended when this timeline actually reaches
            // the end of `lines` — a timeline truncated by the entry cap is
            // refilled by the `.after` policy long before this date, and
            // claiming "out of date" mid-song would be a lie.
            let span = max(payload.chainedSpanMs, lastLine.timeMs)
            let expiredDate = Date(timeIntervalSince1970: startEpoch + Double(span + expiredSlackMs) / 1000.0)
            if expiredDate > now {
                entries.append(WidgetTimelineEntry(
                    date: expiredDate,
                    lineIndex: lines.count + 2,
                    currentLine: "",
                    currentTranslation: nil,
                    previousLines: [lastLine.text],
                    nextLine: nil,
                    upcomingLines: [],
                    progress: 1.0,
                    isExpired: true
                ))
            }
        }
        entries.sort { $0.date < $1.date }
        return entries.isEmpty ? [staticEntry(payload: payload, now: now)] : entries
    }

    /// Progress within the *currently playing* song: a chained next song
    /// restarts the bar at its own boundary instead of pinning it at 100 %.
    static func progressFraction(for timeMs: Int, payload: SharedWidgetPayload) -> Double {
        if payload.nextStartMs > 0, timeMs >= payload.nextStartMs {
            guard payload.nextDurationMs > 0 else { return 0 }
            return min(1.0, Double(timeMs - payload.nextStartMs) / Double(payload.nextDurationMs))
        }
        guard payload.durationMs > 0 else { return 0 }
        return min(1.0, Double(timeMs) / Double(payload.durationMs))
    }

    /// True when the payload describes playback that has already run out — the
    /// baked timeline is spent and the app never came back to replace it. The
    /// widget provider gates its self-repair on this, so a wake only costs a
    /// network round trip when it might actually change what is on screen.
    static func isExpired(payload: SharedWidgetPayload, now: Date) -> Bool {
        guard payload.isPlaying, payload.chainedSpanMs > 0 else { return false }
        return positionMs(for: payload, now: now) > payload.chainedSpanMs + expiredSlackMs
    }

    private static func staticEntry(payload: SharedWidgetPayload, now: Date,
                                    resyncPulse: Double = 1) -> WidgetTimelineEntry {
        WidgetTimelineEntry(
            date: now,
            lineIndex: payload.lines.firstIndex { $0.text == payload.currentLine },
            currentLine: payload.currentLine,
            currentTranslation: payload.currentTranslation,
            previousLines: payload.previousLines,
            nextLine: payload.nextLine,
            upcomingLines: payload.upcomingLines,
            progress: payload.progress,
            resyncPulse: resyncPulse
        )
    }

    /// Position the widget believes playback is at — used to detect a stale
    /// payload (the app was killed mid-song) so the widget can stop advancing.
    static func positionMs(for payload: SharedWidgetPayload, now: Date) -> Int {
        guard payload.trackStartEpochMs > 0 else { return 0 }
        return max(0, Int(now.timeIntervalSince1970 * 1000) - payload.trackStartEpochMs)
    }
}
