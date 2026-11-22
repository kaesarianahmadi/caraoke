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
struct SharedWidgetPayload: Codable, Equatable, Sendable {
    static let spotifyIdle = Self(title: "", artist: "", currentLine: "", isPlaying: false,
                                  progress: 0, status: LyricStatus.idle.rawValue, source: "spotify")

    var title: String
    var artist: String
    var album: String?
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
    /// Monotonic generation + wall-clock observation epoch (ms) for CAS & pause expiry.
    var generation: UInt64 = 0
    var observedAtEpochMs: Int = 0

    init(title: String,
         artist: String,
         album: String? = nil,
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
         nextArtworkColorHex: String? = nil,
         generation: UInt64 = 0,
         observedAtEpochMs: Int = 0) {
        self.title = title
        self.artist = artist
        self.album = album
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
        self.generation = generation
        self.observedAtEpochMs = observedAtEpochMs
    }

    /// Total span `lines` covers: one song, or two when the next one is chained.
    var chainedSpanMs: Int {
        nextStartMs > 0 && nextDurationMs > 0 ? nextStartMs + nextDurationMs : durationMs
    }

    func hasSamePlayerTimeline(as other: Self) -> Bool {
        title == other.title && artist == other.artist && album == other.album
            && source == other.source && isPlaying == other.isPlaying && durationMs == other.durationMs
            && artworkData == other.artworkData && artworkColorHex == other.artworkColorHex
            && nextStartMs == other.nextStartMs && nextDurationMs == other.nextDurationMs
            && nextTitle == other.nextTitle && nextArtist == other.nextArtist
            && nextArtworkData == other.nextArtworkData && nextArtworkColorHex == other.nextArtworkColorHex
            && abs(trackStartEpochMs - other.trackStartEpochMs) <= 1000
    }

    /// A chained entry never borrows the previous song's cover.
    func cover(forChainedEntry chained: Bool) -> (data: Data?, hex: String?) {
        guard chained else { return (artworkData, artworkColorHex) }
        return (nextArtworkData, nextArtworkColorHex)
    }
}

// MARK: - Widget configuration (shared, not per-process UserDefaults)

/// Theme + cover style only. The show-lyrics / refresh / translation toggles
/// are gone: lyrics are the widget's whole point, the cover itself is the
/// resync button, and a translation rides along with its line.
struct SharedWidgetSettings: Codable, Sendable, Equatable {
    var theme: String
    var coverStyle: String
    /// Hero lyric weight: bold (default) or regular. Sourced from the
    /// appearance settings UI's `appearance.boldText` UserDefaults key.
    var boldText: Bool
    /// Enable bake detail in system logs. Diagnostic text is never painted
    /// over widgets, even when an older saved setting enables this flag.
    var debugStamp: Bool
    /// Global Bluetooth / CarPlay lyric timing offset in milliseconds.
    var lyricOffsetMs: Int

    init(theme: String = "artwork",
         coverStyle: String = "vinyl",
         boldText: Bool = true,
         debugStamp: Bool = false,
         lyricOffsetMs: Int = 0) {
        self.theme = theme
        self.coverStyle = coverStyle
        self.boldText = boldText
        self.debugStamp = debugStamp
        self.lyricOffsetMs = lyricOffsetMs
    }

    /// Hand-written so a settings blob written before a field existed still
    /// decodes. The synthesised initializer throws on a missing key, and
    /// `SharedWidgetStore.readSettings()` maps a throw to *defaults* — which
    /// would silently reset the user's theme and cover style, not just the new
    /// field. Every field added here must be read with `decodeIfPresent`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "artwork"
        coverStyle = try container.decodeIfPresent(String.self, forKey: .coverStyle) ?? "vinyl"
        boldText = try container.decodeIfPresent(Bool.self, forKey: .boldText) ?? true
        debugStamp = try container.decodeIfPresent(Bool.self, forKey: .debugStamp) ?? false
        lyricOffsetMs = try container.decodeIfPresent(Int.self, forKey: .lyricOffsetMs) ?? 0
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

    /// How long a *paused* payload may hold its tile before a wake treats it
    /// as dead. A red-light pause is minutes, not hours: when the app dies
    /// while paused, this cap is the only thing that lets the extension's
    /// Spotify self-fetch take over. Without it `isExpired` returned false for
    /// any paused payload forever, and device logs (2026-10-25) showed the
    /// result — a payload 21 h old, every bake one static entry, all three
    /// CarPlay tiles frozen on a line from the previous day while the app
    /// had not run at all. 60 s, not 600: build 75 drive logs (2026-10-26)
    /// showed a resume-by-car-controls case stranded an app-dead tile for the
    /// full ten-minute hold while the music had moved on — a wake costs one
    /// bounded self-fetch, so repair within a minute instead.
    static let pausedHoldMs = 60_000

    /// The Player tile has no lyrics. Bake coarse progress and a track boundary,
    /// independent of the number or spacing of lyric lines.
    static func playerEntries(for payload: SharedWidgetPayload, now: Date) -> [WidgetTimelineEntry] {
        let expired = isExpired(payload: payload, now: now)
        let position = positionMs(for: payload, now: now)
        func entry(at date: Date, position: Int) -> WidgetTimelineEntry {
            WidgetTimelineEntry(date: date, lineIndex: nil, currentLine: "", currentTranslation: nil,
                                previousLines: [], nextLine: nil, upcomingLines: [],
                                progress: payload.isPlaying && payload.durationMs > 0 && payload.trackStartEpochMs > 0
                                    ? progressFraction(for: position, payload: payload) : payload.progress,
                                isNextTrack: payload.isPlaying && payload.nextStartMs > 0 && position >= payload.nextStartMs,
                                isExpired: expired)
        }
        var entries = [entry(at: now, position: position)]
        guard !expired, payload.isPlaying, payload.trackStartEpochMs > 0 else { return entries }
        var offsets = (1...5).map { position + $0 * 30_000 }.filter { $0 <= payload.chainedSpanMs }
        if payload.nextStartMs > position, payload.nextStartMs <= position + 150_000 {
            offsets.append(payload.nextStartMs)
        }
        for offset in Set(offsets).sorted() {
            let date = Date(timeIntervalSince1970: Double(payload.trackStartEpochMs + offset) / 1000)
            if date > now { entries.append(entry(at: date, position: offset)) }
        }
        return entries
    }

    static func playerReloadDate(for payload: SharedWidgetPayload, now: Date) -> Date {
        guard payload.trackStartEpochMs > 0, payload.chainedSpanMs > 0 else { return now.addingTimeInterval(60) }
        if !payload.isPlaying { return now.addingTimeInterval(60) }
        let end = Date(timeIntervalSince1970: Double(payload.trackStartEpochMs + payload.chainedSpanMs) / 1000)
        return max(now.addingTimeInterval(30), min(end.addingTimeInterval(20), now.addingTimeInterval(150)))
    }

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

        // No span cap: the lines the payload carries are baked from here to
        // the end, whatever `chainedSpanMs` claims. A too-small span used to
        // collapse the whole bake to one static entry mid-song — the freeze
        // where the tile shows one picture and never slides. Staleness is
        // `isExpired`'s job (and the provider's self-fetch), not a reason to
        // refuse to advance.
        let nextTrackIndex = payload.nextStartMs > 0
            ? lines.firstIndex(where: { $0.timeMs >= payload.nextStartMs }) : nil
        let trackIndex = positionMs >= payload.nextStartMs ? (nextTrackIndex ?? 0) : 0
        var startIndex = trackIndex
        while startIndex + 1 < lines.count, lines[startIndex + 1].timeMs <= positionMs { startIndex += 1 }

        let end = min(lines.count, startIndex + limit)
        var entries: [WidgetTimelineEntry] = []
        entries.reserveCapacity(end - startIndex + 2)

        // Intro entry for track start before first lyric
        if positionMs < lines[trackIndex].timeMs {
            let trackEnd = trackIndex == 0 ? (nextTrackIndex ?? lines.count) : lines.count
            let introUpcoming = Array(lines[trackIndex..<trackEnd].prefix(upcomingShown).map(\.text))
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
                isNextTrack: trackIndex > 0
            ))
        }

        // Chained next-track intro entry before its first lyric
        if let nextTrackIndex, nextTrackIndex < end {
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
            let isNextTrack = nextTrackIndex.map { index >= $0 } ?? false
            let first = isNextTrack ? (nextTrackIndex ?? 0) : 0
            let last = isNextTrack ? lines.count : (nextTrackIndex ?? lines.count)
            let previous = Array(lines[max(first, index - 2)..<index].map(\.text))
            let upcoming = Array(lines[(index + 1)..<last].prefix(upcomingShown).map(\.text))
            entries.append(WidgetTimelineEntry(
                date: max(lineDate, now),
                lineIndex: index,
                currentLine: line.text,
                currentTranslation: line.translation,
                previousLines: previous,
                nextLine: upcoming.first,
                upcomingLines: upcoming,
                progress: progressFraction(for: line.timeMs, payload: payload),
                isNextTrack: isNextTrack
            ))
        }

        // Outro entries: after the final lyric line, shift it up into previous,
        // then clear all lines so the widget smoothly scrolls off and disappears.
        if includeOutro, end == lines.count, let lastLine = lines.last {
            if positionMs >= lastLine.timeMs + 10_000 {
                entries = [WidgetTimelineEntry(
                    date: now,
                    lineIndex: lines.count + 1,
                    currentLine: "",
                    currentTranslation: nil,
                    previousLines: [],
                    nextLine: nil,
                    upcomingLines: [],
                    progress: 1.0,
                    isNextTrack: nextTrackIndex != nil
                )]
            } else {
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
                        progress: progressFraction(for: lastLine.timeMs + 7000, payload: payload),
                        isNextTrack: nextTrackIndex != nil
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
                        progress: 1.0,
                        isNextTrack: nextTrackIndex != nil
                    ))
                }
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
                    isNextTrack: nextTrackIndex != nil,
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
    ///
    /// A *playing* payload expires when its span runs out (plus slack). A
    /// *paused* payload used to never expire at all, which stranded the tile
    /// forever when the app died while paused: the wake took the direct path,
    /// baked one static entry, and the Spotify self-fetch — the extension's
    /// only repair when the app is gone — stayed gated off. A pause now holds
    /// for `pausedHoldMs` past the span; after that the payload is treated as
    /// dead and the self-fetch runs.
    static func isExpired(payload: SharedWidgetPayload, now: Date) -> Bool {
        guard payload.chainedSpanMs > 0 else { return false }
        if payload.isPlaying {
            let age = positionMs(for: payload, now: now)
            return age > payload.chainedSpanMs + expiredSlackMs
        }
        if payload.observedAtEpochMs > 0 {
            let pausedAgeMs = Int(now.timeIntervalSince1970 * 1000) - payload.observedAtEpochMs
            return pausedAgeMs > pausedHoldMs
        }
        let age = positionMs(for: payload, now: now)
        return age > payload.chainedSpanMs + pausedHoldMs
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
