import SwiftUI
import WidgetKit
import os

// MARK: - Timeline Entry

/// One rendered lyric state. Built by `WidgetTimelineBuilder` (CaraokeCore)
/// from the shared payload, so the widget advances line by line on its own
/// schedule without needing the app to poke it.
struct CaraokeWidgetEntry: TimelineEntry {
    let date: Date
    let lineIndex: Int?
    let currentLine: String
    let previousLines: [String]
    let nextLine: String?
    let upcomingLines: [String]
    let progress: Double
    let title: String
    let artist: String
    let isPlaying: Bool
    let status: LyricStatus
    let artworkData: Data?
    let artworkColorHex: String?
    /// Cover opacity for this entry — below 1 while a resync pulses.
    let resyncPulse: Double
    let settings: SharedWidgetSettings
}

// MARK: - Timeline Provider

struct CaraokeWidgetProvider: TimelineProvider {

    /// Boundary diagnostics. Readable on device with Console.app (or
    /// `log collect --predicate 'subsystem == "com.caraoke.poc"'`), which is
    /// the only way to tell "the app stopped reloading" apart from "the reload
    /// was throttled" — they look identical on screen and need different fixes.
    private static let log = Logger(subsystem: "com.caraoke.poc", category: "widget")

    func placeholder(in context: Context) -> CaraokeWidgetEntry {
        CaraokeWidgetEntry(
            date: Date(),
            lineIndex: nil,
            currentLine: "Play a song to see lyrics",
            previousLines: ["Sing along in real time"],
            nextLine: "Synced for CarPlay & Lock Screen",
            upcomingLines: [
                "Ultra-low latency lyric engine",
                "Works with Spotify and Apple Music"
            ],
            progress: 0.35,
            title: "Caraoke",
            artist: "Live Lyrics",
            isPlaying: false,
            status: .idle,
            artworkData: nil,
            artworkColorHex: nil,
            resyncPulse: 1,
            settings: SharedWidgetSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CaraokeWidgetEntry) -> Void) {
        guard let payload = SharedWidgetStore.read(), !payload.title.isEmpty else {
            completion(placeholder(in: context))
            return
        }
        let settings = SharedWidgetStore.readSettings()
        guard let built = WidgetTimelineBuilder.entries(for: payload, now: Date(), limit: 1).first else {
            completion(placeholder(in: context))
            return
        }
        completion(entry(from: built, payload: payload, settings: settings))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaraokeWidgetEntry>) -> Void) {
        guard let payload = SharedWidgetStore.read(), !payload.title.isEmpty else {
            completion(Timeline(entries: [placeholder(in: context)], policy: .atEnd))
            return
        }
        // A wake that finds the baked timeline already spent is the one moment
        // the extension can repair itself. Ask the player what is on now and
        // rebuild from the answer — this is what keeps the tile following the
        // music when the app itself has been suspended and cannot reload us.
        // Gated on expiry so an ordinary wake never costs a network round trip.
        guard WidgetTimelineBuilder.isExpired(payload: payload, now: Date()) else {
            Self.log.info("getTimeline direct: lines=\(payload.lines.count, privacy: .public) chain=\(payload.nextStartMs, privacy: .public)")
            completion(timeline(for: payload, in: context))
            return
        }
        Task {
            let started = Date()
            let refreshed = await WidgetResync.refreshNowPlaying(timeout: 6)
            Self.log.info("getTimeline self-fetch took=\(Date().timeIntervalSince(started), privacy: .public)s track=\((refreshed ?? payload).title, privacy: .public)")
            completion(timeline(for: refreshed ?? payload, in: context))
        }
    }

    /// Builds the timeline for a payload, choosing a reload policy that always
    /// leaves the widget a way back to correct lyrics.
    private func timeline(for payload: SharedWidgetPayload, in context: Context) -> Timeline<CaraokeWidgetEntry> {
        let settings = SharedWidgetStore.readSettings()
        let now = Date()
        let built = WidgetTimelineBuilder.entries(for: payload, now: now, includeOutro: true)
        let entries = built.map { entry(from: $0, payload: payload, settings: settings) }

        // "Covered" means this timeline actually reaches the last lyric line —
        // a chained tail counts, because it is in the same array. Deliberately
        // not `built.last`: the trailing outro and expired entries sit past the
        // final line and would make every timeline look complete.
        let covered = built.contains { $0.lineIndex == payload.lines.count - 1 }
        let policy: TimelineReloadPolicy
        if !payload.isPlaying || payload.lines.isEmpty {
            policy = .atEnd
        } else if covered {
            // A whole song fits in one timeline, so no periodic reload is
            // needed — reloading every few seconds is what exhausted
            // WidgetKit's budget and made the widget stop updating altogether.
            // But the timeline must still ask for a pass once the span it
            // covers runs out: `.never` here meant a single dropped reload left
            // the tile dead on the last line until the user tapped it.
            //
            // The date is deliberately *before* the span runs out. chronod
            // defers a background reload by up to ~160 s, so asking for one
            // after the last entry has already been consumed all but
            // guarantees the tile sits dead until someone taps it — the
            // deferred reload lands on a timeline that ran out minutes ago.
            // Asked with lead time, the same deferral is absorbed while the
            // song is still playing and the replacement is in place before
            // anything expires. One request per bake (~6 min for two songs),
            // so the extra earliness costs no meaningful budget.
            let lead: TimeInterval = 45
            let spanEnd = Date(timeIntervalSince1970: Double(payload.trackStartEpochMs + payload.chainedSpanMs) / 1000.0)
            policy = .after(max(spanEnd.addingTimeInterval(-lead), now.addingTimeInterval(30)))
        } else if let last = entries.last {
            policy = .after(last.date.addingTimeInterval(30))
        } else {
            policy = .atEnd
        }
        Self.log.info("timeline entries=\(entries.count, privacy: .public) covered=\(covered, privacy: .public) policy=\(String(describing: policy), privacy: .public)")
        return Timeline(entries: entries.isEmpty ? [placeholder(in: context)] : entries, policy: policy)
    }

    private func entry(from built: WidgetTimelineEntry,
                       payload: SharedWidgetPayload,
                       settings: SharedWidgetSettings) -> CaraokeWidgetEntry {
        // `expired` is per-entry, not per-payload: the payload is what the app
        // last knew, and this entry is the one dated past the end of it.
        let status: LyricStatus = built.isExpired
            ? .expired
            : (LyricStatus(raw: payload.status) ?? .playing)
        // A chained tail belongs to the next song, so the header follows the
        // lyrics across the boundary instead of naming the song that ended.
        let chained = built.isNextTrack
        // The baked tail carries the next song's lyrics, so it has to carry its
        // cover too — otherwise the header switches name at the boundary while
        // the art stays on the song that already ended.
        let cover = payload.cover(forChainedEntry: chained)
        return CaraokeWidgetEntry(
            date: built.date,
            lineIndex: built.lineIndex,
            currentLine: built.currentLine,
            previousLines: built.previousLines,
            nextLine: built.nextLine,
            upcomingLines: built.upcomingLines,
            progress: built.progress,
            title: chained && !payload.nextTitle.isEmpty ? payload.nextTitle : payload.title,
            artist: chained && !payload.nextArtist.isEmpty ? payload.nextArtist : payload.artist,
            isPlaying: payload.isPlaying,
            status: status,
            artworkData: cover.data,
            artworkColorHex: cover.hex,
            resyncPulse: built.resyncPulse,
            settings: settings
        )
    }
}

// MARK: - Widget View

struct CaraokeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CaraokeWidgetEntry

    private var surface: LyricTileView.Surface {
        switch family {
        case .systemSmall:
            return .widgetSmall
        case .systemLarge:
            return .widgetLarge
        default:
            return .widgetMedium
        }
    }

    private var theme: WidgetTheme { WidgetTheme(rawValue: entry.settings.theme) ?? .artwork }

    private var widgetPalette: LyricTilePalette {
        LyricTilePalette(
            cardBackground: .clear,
            cardBorder: .clear,
            titleText: theme.textColor,
            artistText: theme.mutedTextColor,
            badgeText: theme.mutedTextColor,
            heroText: theme.textColor,
            nextText: theme.mutedTextColor,
            metaText: theme.mutedTextColor,
            trackBackground: theme.textColor.opacity(0.18),
            // White (theme ink), not the brand orange — the progress bar reads
            // as part of the lyric block, not as an accent.
            trackFill: theme.textColor.opacity(0.92),
            glow: theme.textColor.opacity(0.7)
        )
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                VinylWidgetView(entry: entry)
            } else {
                LyricTileView(
                    title: entry.title,
                    artist: entry.artist,
                    currentLine: entry.currentLine,
                    previousLines: entry.previousLines,
                    nextLine: entry.nextLine,
                    upcomingLines: entry.upcomingLines,
                    isPlaying: entry.isPlaying,
                    progress: entry.progress,
                    status: entry.status,
                    surface: surface,
                    palette: widgetPalette,
                    artworkData: entry.artworkData,
                    resyncPulse: entry.resyncPulse,
                    // Out of sync = anything but a playing, lyric-backed state.
                    needsResync: entry.status != .playing || entry.resyncPulse < 1
                )
                .widgetURL(URL(string: "caraoke://lyrics"))
                .containerBackground(for: .widget) {
                    WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData)
                }
            }
        }
    }
}

// MARK: - Widget Definition

struct CaraokeWidget: Widget {
    let kind: String = "CaraokeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider()) { entry in
            CaraokeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Caraoke Lyrics")
        .description("Synced lyrics widget for Home Screen and CarPlay dashboard.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        // StandBy and CarPlay drop the background and render the tile on
        // black; the widget palette is card-free so the content survives it.
        .containerBackgroundRemovable(true)
    }
}
