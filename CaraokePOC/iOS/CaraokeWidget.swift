import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct CaraokeWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let currentLine: String
    let previousLines: [String]
    let nextLine: String?
    let upcomingLines: [String]
    let isPlaying: Bool
    let progress: Double
    let status: LyricStatus
    let artworkData: Data?

    init(date: Date = Date(),
         title: String,
         artist: String,
         currentLine: String,
         previousLines: [String] = [],
         nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool = true,
         progress: Double = 0,
         status: LyricStatus = .playing,
         artworkData: Data? = nil) {
        self.date = date
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.previousLines = previousLines
        self.nextLine = nextLine
        self.upcomingLines = upcomingLines.isEmpty ? (nextLine.map { [$0] } ?? []) : upcomingLines
        self.isPlaying = isPlaying
        self.progress = progress
        self.status = status
        self.artworkData = artworkData
    }
}

// MARK: - Timeline Provider

struct CaraokeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaraokeWidgetEntry {
        CaraokeWidgetEntry(
            date: Date(),
            title: "Caraoke",
            artist: "Live Lyrics",
            currentLine: "Play a song to see lyrics",
            nextLine: "Next line will appear here",
            upcomingLines: [
                "Sing along in real time",
                "Synced for CarPlay & Lock Screen",
                "Ultra-low latency lyric engine",
                "Works seamlessly with Spotify",
                "Live Activity on Lock Screen",
                "Full catalog coverage"
            ],
            isPlaying: false,
            progress: 0.35,
            status: .idle
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CaraokeWidgetEntry) -> Void) {
        if let payload = SharedWidgetStore.read(), !payload.title.isEmpty {
            let status = LyricStatus(raw: payload.status) ?? .playing
            let entry = CaraokeWidgetEntry(
                date: Date(),
                title: payload.title,
                artist: payload.artist,
                currentLine: payload.currentLine,
                previousLines: payload.previousLines,
                nextLine: payload.nextLine,
                upcomingLines: payload.upcomingLines,
                isPlaying: payload.isPlaying,
                progress: payload.progress,
                status: status,
                artworkData: payload.artworkData
            )
            completion(entry)
        } else {
            completion(placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaraokeWidgetEntry>) -> Void) {
        guard let payload = SharedWidgetStore.read(), !payload.title.isEmpty else {
            let entry = placeholder(in: context)
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }

        let status = LyricStatus(raw: payload.status) ?? .playing
        let now = Date()

        // If not playing, or no timed lines available, or not in playing state: single static entry
        if !payload.isPlaying || payload.lines.isEmpty || status != .playing {
            let entry = CaraokeWidgetEntry(
                date: now,
                title: payload.title,
                artist: payload.artist,
                currentLine: payload.currentLine,
                previousLines: payload.previousLines,
                nextLine: payload.nextLine,
                upcomingLines: payload.upcomingLines,
                isPlaying: payload.isPlaying,
                progress: payload.progress,
                status: status,
                artworkData: payload.artworkData
            )
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }

        // GENERATE MULTI-ENTRY TIMELINE FOR REAL-TIME LYRIC SYNCHRONIZATION
        var entries: [CaraokeWidgetEntry] = []
        let trackStartEpoch = Double(payload.trackStartEpochMs) / 1000.0
        let nowEpoch = now.timeIntervalSince1970
        let currentPosMs = max(0, Int((nowEpoch - trackStartEpoch) * 1000.0))

        let lines = payload.lines
        var startIndex = 0
        for (i, line) in lines.enumerated() {
            if line.timeMs <= currentPosMs {
                startIndex = i
            } else {
                break
            }
        }

        // Schedule up to 60 subsequent lines for automatic timeline transitions
        let sliceLimit = min(lines.count, startIndex + 60)
        let slice = lines[startIndex..<sliceLimit]

        for (offset, line) in slice.enumerated() {
            let globalIndex = startIndex + offset
            let lineEpoch = trackStartEpoch + (Double(line.timeMs) / 1000.0)
            let entryDate = (offset == 0) ? now : Date(timeIntervalSince1970: lineEpoch)

            let nextLineText = (globalIndex + 1 < lines.count) ? lines[globalIndex + 1].text : nil
            let upcoming = lines.dropFirst(globalIndex + 1).prefix(8).map(\.text)
            let previous: [String] = globalIndex > 0
                ? lines[max(0, globalIndex - 2)..<globalIndex].map(\.text)
                : []
            let progress = payload.durationMs > 0 ? min(1.0, Double(line.timeMs) / Double(payload.durationMs)) : 0.0

            entries.append(CaraokeWidgetEntry(
                date: max(entryDate, now),
                title: payload.title,
                artist: payload.artist,
                currentLine: line.text,
                previousLines: Array(previous),
                nextLine: nextLineText,
                upcomingLines: Array(upcoming),
                isPlaying: true,
                progress: progress,
                status: .playing,
                artworkData: payload.artworkData
            ))
        }

        let reloadPolicy: TimelineReloadPolicy
        if let last = entries.last {
            reloadPolicy = .after(last.date.addingTimeInterval(4))
        } else {
            reloadPolicy = .atEnd
        }

        completion(Timeline(entries: entries.isEmpty ? [placeholder(in: context)] : entries, policy: reloadPolicy))
    }
}

// MARK: - Widget View

struct CaraokeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CaraokeWidgetEntry

    init(entry: CaraokeWidgetEntry) {
        self.entry = entry
    }

    private var surface: LyricTileView.Surface {
        switch family {
        case .systemSmall:
            return .widgetSmall
        case .systemMedium:
            return .widgetMedium
        case .systemLarge:
            return .widgetLarge
        default:
            return .widgetMedium
        }
    }

    @AppStorage("widget_selected_theme", store: UserDefaults(suiteName: "group.app.caraoke")) private var savedTheme: String = WidgetTheme.artwork.rawValue

    private var theme: WidgetTheme {
        WidgetTheme(rawValue: savedTheme) ?? .artwork
    }

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
            trackFill: theme.textColor.opacity(0.75),
            glow: .white
        )
    }

    var body: some View {
        // Use vinyl widget for medium size, standard tile for others
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
                artworkData: entry.artworkData
            )
            .widgetURL(URL(string: "caraoke://lyrics"))
            .containerBackground(for: .widget) {
                WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData)
            }
            // Refresh swaps the entry date: fade the card out and back in
            // instead of blinking through an empty frame.
            .id(entry.date)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.45), value: entry.date)
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
    }
}
