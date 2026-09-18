import SwiftUI
import WidgetKit

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
        let settings = SharedWidgetStore.readSettings()
        let now = Date()
        let built = WidgetTimelineBuilder.entries(for: payload, now: now, includeOutro: true)
        let entries = built.map { entry(from: $0, payload: payload, settings: settings) }

        // A whole song fits in one timeline, so no periodic reload is needed —
        // reloading every few seconds is what exhausted WidgetKit's budget and
        // made the widget stop updating altogether. Only a truncated timeline
        // asks for a follow-up pass.
        let covered = (built.last?.lineIndex ?? -1) >= payload.lines.count - 1
        let policy: TimelineReloadPolicy
        if !payload.isPlaying || payload.lines.isEmpty {
            policy = .atEnd
        } else if covered {
            policy = .never
        } else if let last = entries.last {
            policy = .after(last.date.addingTimeInterval(30))
        } else {
            policy = .atEnd
        }
        completion(Timeline(entries: entries.isEmpty ? [placeholder(in: context)] : entries, policy: policy))
    }

    private func entry(from built: WidgetTimelineEntry,
                       payload: SharedWidgetPayload,
                       settings: SharedWidgetSettings) -> CaraokeWidgetEntry {
        CaraokeWidgetEntry(
            date: built.date,
            lineIndex: built.lineIndex,
            currentLine: built.currentLine,
            previousLines: built.previousLines,
            nextLine: built.nextLine,
            upcomingLines: built.upcomingLines,
            progress: built.progress,
            title: payload.title,
            artist: payload.artist,
            isPlaying: payload.isPlaying,
            status: LyricStatus(raw: payload.status) ?? .playing,
            artworkData: payload.artworkData,
            artworkColorHex: payload.artworkColorHex,
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
