import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct CaraokeWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    let isPlaying: Bool
    let progress: Double
    let status: LyricStatus

    init(date: Date = Date(), title: String, artist: String, currentLine: String,
         nextLine: String? = nil, isPlaying: Bool = true, progress: Double = 0,
         status: LyricStatus = .playing) {
        self.date = date
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.nextLine = nextLine
        self.isPlaying = isPlaying
        self.progress = progress
        self.status = status
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
            isPlaying: false,
            progress: 0.35,
            status: .idle
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CaraokeWidgetEntry) -> Void) {
        completion(readSharedEntry() ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaraokeWidgetEntry>) -> Void) {
        let entry = readSharedEntry() ?? placeholder(in: context)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }

    private func readSharedEntry() -> CaraokeWidgetEntry? {
        let store = UserDefaults(suiteName: "group.app.caraoke") ?? UserDefaults.standard
        guard let title = store.string(forKey: "widget_title"), !title.isEmpty else {
            return nil
        }
        let artist = store.string(forKey: "widget_artist") ?? ""
        let currentLine = store.string(forKey: "widget_current_line") ?? ""
        let nextLine = store.string(forKey: "widget_next_line")
        let isPlaying = store.bool(forKey: "widget_is_playing")
        let progress = store.double(forKey: "widget_progress")
        let statusRaw = store.string(forKey: "widget_status") ?? "playing"
        let status = LyricStatus(raw: statusRaw) ?? .playing

        return CaraokeWidgetEntry(
            date: Date(),
            title: title,
            artist: artist,
            currentLine: currentLine,
            nextLine: nextLine,
            isPlaying: isPlaying,
            progress: progress,
            status: status
        )
    }
}

// MARK: - Widget View

struct CaraokeWidgetEntryView: View {
    var entry: CaraokeWidgetEntry
    @Environment(\.widgetFamily) private var family

    init(entry: CaraokeWidgetEntry) {
        self.entry = entry
    }

    var body: some View {
        LyricTileView(
            title: entry.title,
            artist: entry.artist,
            currentLine: entry.currentLine,
            nextLine: entry.nextLine,
            isPlaying: entry.isPlaying,
            progress: entry.progress,
            status: entry.status,
            isCarPlaySmall: family == .systemSmall
        )
        .containerBackground(for: .widget) {
            Color.black.opacity(0.85)
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
    }
}
