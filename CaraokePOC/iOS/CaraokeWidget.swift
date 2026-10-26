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
    /// Diagnostics burned into the rendered tile. Nil unless the tester turned
    /// on `SharedWidgetSettings.debugStamp`. Read it off the car screen to tell
    /// a short bake from a stalled CarPlay from reload churn — see the doc
    /// comment on `WidgetDebugStamp` for what each reading means.
    let debugStamp: WidgetDebugStamp?
}

/// Values captured at bake time, rendered into a corner of the tile.
///
/// Every field is computed when the timeline is *built*, never inside a view
/// body — a view body runs when the system archives the entry, not when it is
/// displayed, so a live clock there would read as permanently fresh.
struct WidgetDebugStamp {
    /// Position of this entry in the bake, 0-based.
    let index: Int
    let total: Int
    /// The entry's own schedule date — what WidgetKit compares against the
    /// clock to decide when to show it.
    let entryDate: Date
    /// When the timeline containing this entry was built.
    let builtAt: Date
    /// The playback anchor the bake was derived from, as epoch millis. The
    /// only field the screen does not show: it is for correlating against the
    /// app's log, not for reading in a photo.
    let anchorMs: Int
    /// How stale that anchor already was when the bake happened.
    let anchorAgeSec: TimeInterval

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// One line, legible in a photograph of the car screen: which entry of
    /// how many, when it was scheduled to appear, when the bake happened, and
    /// how old the anchor was. Wall-clock times, not epoch — a human reads
    /// this off a photo, and the sub-second correlation lives in the log.
    var line: String {
        "\(index + 1)/\(total) e\(Self.clock.string(from: entryDate)) b\(Self.clock.string(from: builtAt)) -\(Int(anchorAgeSec))s"
    }

    /// Millisecond-precision form for log lines, where the stamp has to line
    /// up with the app's reload requests.
    var logLine: String {
        let entryMs = Int(entryDate.timeIntervalSince1970 * 1000)
        let builtMs = Int(builtAt.timeIntervalSince1970 * 1000)
        return "\(index + 1)/\(total) entryMs=\(entryMs) builtMs=\(builtMs) anchorMs=\(anchorMs) anchorAgeSec=\(Int(anchorAgeSec))"
    }
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
            settings: SharedWidgetSettings(),
            debugStamp: nil
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
            Self.log.notice("getTimeline direct: lines=\(payload.lines.count, privacy: .public) chain=\(payload.nextStartMs, privacy: .public)")
            completion(timeline(for: payload, in: context))
            return
        }
        Task {
            let started = Date()
            let refreshed = await WidgetResync.refreshNowPlaying(timeout: 6)
            Self.log.notice("getTimeline self-fetch took=\(Date().timeIntervalSince(started), privacy: .public)s track=\((refreshed ?? payload).title, privacy: .public)")
            completion(timeline(for: refreshed ?? payload, in: context))
        }
    }

    /// Builds the timeline for a payload, choosing a reload policy that always
    /// leaves the widget a way back to correct lyrics.
    private func timeline(for payload: SharedWidgetPayload, in context: Context) -> Timeline<CaraokeWidgetEntry> {
        let settings = SharedWidgetStore.readSettings()
        let now = Date()
        // Live-loop mode: when the surface repaints only on reloads (every
        // systemSmall placement — the CarPlay tiles; a small tile on the
        // phone's Home Screen rides along, which TimelineProvider cannot
        // distinguish), bake exactly ONE entry. The competitor's CarPlay
        // timeline archives hold entry count 1, and chronod re-requests a
        // spent timeline promptly while deferring timelines that still have
        // future entries (device logs 2026-10-26: our 6–82-entry bakes got
        // 85 s cooldowns; a single spent entry is the shape that produced
        // their ~1.6 s bake cadence).
        let looping = context.family == .systemSmall
            && payload.isPlaying
            && payload.chainedSpanMs > 0
        let built = WidgetTimelineBuilder.entries(for: payload,
                                                  now: now,
                                                  limit: looping ? 1 : WidgetTimelineBuilder.maxEntries,
                                                  includeOutro: true)
        // Read from the shared keychain settings, never UserDefaults: the
        // extension cannot see the app's `.standard` domain without an App
        // Group, which this project deliberately does not use.
        let debug = settings.debugStamp
        // Anchor age is measured once, when the bake happens: how stale the
        // playback reference already was when we derived from it. A value that
        // climbs across bakes is the signature of a reload landing on a payload
        // the app never refreshed.
        let anchorAge = now.timeIntervalSince1970 - Double(payload.trackStartEpochMs) / 1000.0
        let stamp = debug ? WidgetDebugStamp(index: 0,
                                             total: built.count,
                                             entryDate: now,
                                             builtAt: now,
                                             anchorMs: payload.trackStartEpochMs,
                                             anchorAgeSec: anchorAge) : nil
        if let stamp {
            // Millisecond precision here, not on the tile: this line is what
            // lines a bake up against the app's reload requests.
            Self.log.notice("timeline baked entries=\(built.count, privacy: .public) covered=\(built.contains { $0.lineIndex == payload.lines.count - 1 }, privacy: .public) \(stamp.logLine, privacy: .public)")
        }
        let entries = built.enumerated().map { index, item in
            entry(from: item,
                  payload: payload,
                  settings: settings,
                  debug: stamp.map { s in
                      WidgetDebugStamp(index: index,
                                        total: s.total,
                                        entryDate: item.date,
                                        builtAt: s.builtAt,
                                        anchorMs: s.anchorMs,
                                        anchorAgeSec: s.anchorAgeSec)
                  })
        }

        // "Covered" means this timeline actually reaches the last lyric line —
        // a chained tail counts, because it is in the same array. Deliberately
        // not `built.last`: the trailing outro and expired entries sit past the
        // final line and would make every timeline look complete.
        let covered = built.contains { $0.lineIndex == payload.lines.count - 1 }
        let policy: TimelineReloadPolicy
        if !payload.isPlaying || payload.lines.isEmpty {
            policy = .atEnd
        } else if context.family == .systemSmall {
            // Single spent entry (see `looping` above): the car tile declares
            // it has nothing left. chronod treats that as an immediate refresh
            // request and re-wakes the extension promptly — the mechanism the
            // competitor's single-entry archives ride. The old short
            // `.after(now + 4 s)` dates were deferred ~86 s on device
            // (2026-10-26 log), so the date is not worth asking for.
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
        Self.log.notice("timeline entries=\(entries.count, privacy: .public) covered=\(covered, privacy: .public) policy=\(String(describing: policy), privacy: .public)")

        // Wakes for the car tiles are now scheduled by the short reload-policy
        // date above: chronod re-requests on that date and every bake hands it
        // a fresh snapshot of the current line. The previous belt-and-braces
        // `WidgetCenter.reloadAllTimelines()` loop is deliberately gone — it is
        // the budget-metered path (drive logs 2026-10-26: 6–16 s bursts then
        // 60–90 s starvations), and firing it alongside policy wakes would let
        // it eat the very budget the policy dates draw from.
        return Timeline(entries: entries.isEmpty ? [placeholder(in: context)] : entries, policy: policy)
    }

    private func entry(from built: WidgetTimelineEntry,
                       payload: SharedWidgetPayload,
                       settings: SharedWidgetSettings,
                       debug: WidgetDebugStamp? = nil) -> CaraokeWidgetEntry {
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
            settings: settings,
            debugStamp: debug
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
                    needsResync: entry.status != .playing || entry.resyncPulse < 1,
                    boldText: entry.settings.boldText
                )
                .widgetURL(URL(string: "caraoke://lyrics"))
                .containerBackground(for: .widget) {
                    WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData)
                }
            }
        }
        // Same stamp as the CarPlay tiles — this is the surface to compare
        // against, since it shares the provider, the bake and the payload.
        .overlay(alignment: .bottomLeading) { WidgetDebugStampView(stamp: entry.debugStamp) }
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
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
        // StandBy and CarPlay drop the background and render the tile on
        // black; the widget palette is card-free so the content survives it.
        .containerBackgroundRemovable(true)
    }
}
