import SwiftUI
import WidgetKit

/// The Live Activity widget. One `ActivityConfiguration` for the Lock Screen
/// banner plus the Dynamic Island; `.supplementalActivityFamilies([.small])`
/// is what makes the same view render as the CarPlay small-family tile
/// (iOS 17.2+ mirrors Lock Screen Live Activities onto CarPlay).
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            // The CarPlay small family is exposed via the environment, not
            // on the context (ActivityFamily reads only work inside a View).
            FamilyAdaptiveTile(context: context)
                .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.currentLine)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if let nextLine = context.state.nextLine {
                            Text(nextLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.accentColor)
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
            } minimal: {
                Image(systemName: "music.note")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Reads the presentation family from the environment inside a real View,
/// then adapts the shared tile: CarPlay / Watch Smart Stack get the compact
/// small-family layout, everything else the full Lock Screen banner.
private struct FamilyAdaptiveTile: View {
    let context: ActivityViewContext<LyricsActivityAttributes>
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        LyricTileView(
            title: context.state.title,
            artist: context.state.artist,
            currentLine: context.state.currentLine,
            nextLine: context.state.nextLine,
            isPlaying: context.state.isPlaying,
            progress: context.state.progress,
            isCarPlaySmall: activityFamily == .small
        )
    }
}
