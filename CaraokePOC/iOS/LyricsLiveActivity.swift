import SwiftUI
import WidgetKit

/// The Live Activity widget. One `ActivityConfiguration` for the Lock Screen
/// banner plus the Dynamic Island; `.supplementalActivityFamilies([.small])`
/// is what makes the same view render as the CarPlay small-family tile
/// (iOS 17.2+ mirrors Lock Screen Live Activities onto CarPlay).
///
/// Design: design/screens/live-activity.html — 5 states × every family, one
/// status driver. Always dark glass; the tile itself carries its own glass
/// background, and `.activityBackgroundTint(.black.opacity(0.7))` supplies the
/// system-level tint the CarPlay mirror needs.
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
                    IslandLeadingGlyph(status: status(of: context.state))
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottom(context: context)
                }
            } compactLeading: {
                IslandLeadingGlyph(status: status(of: context.state))
            } compactTrailing: {
                Image(systemName: status(of: context.state) == .paused ? "pause.fill" : "play.fill")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            } minimal: {
                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Status derivation (one driver for every family)

/// Fallback derivation for relay pushes that carry no explicit status: an
/// empty hero line while playing = lyrics still loading; empty + not playing =
/// the pre-song Ride Mode placeholder.
func status(of state: LyricsActivityAttributes.ContentState) -> LyricStatus {
    if let explicit = LyricStatus(raw: state.status) {
        return explicit
    }
    if !state.currentLine.isEmpty {
        return state.isPlaying ? .playing : .paused
    }
    return state.isPlaying ? .loading : .idle
}

// MARK: - Family-adaptive host

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
            status: status(of: context.state),
            positionMs: context.state.positionMs ?? 0,
            durationMs: context.state.durationMs,
            isCarPlaySmall: activityFamily == .small
        )
    }
}

// MARK: - Dynamic Island regions

/// Leading glyph: the amber live dot when playing, the music note otherwise.
private struct IslandLeadingGlyph: View {
    let status: LyricStatus

    var body: some View {
        Group {
            if status == .playing {
                Circle()
                    .fill(Color(hex: 0xFF9845))
                    .frame(width: 7, height: 7)
            } else {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(minWidth: 24, minHeight: 24)
    }
}

/// Expanded center: the hero lyric line + next line (design `.ix-now` /
/// `.ix-next` with the 55 % neighbor fade).
private struct IslandCenter: View {
    let context: ActivityViewContext<LyricsActivityAttributes>

    var body: some View {
        switch status(of: context.state) {
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                skeletonBar(fraction: 0.84)
                skeletonBar(fraction: 0.55)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .noLyrics:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text("No lyrics found for this song")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .stale:
            Text("Ride ended")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.currentLine.isEmpty
                     ? "Play a song to see lyrics"
                     : context.state.currentLine)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let nextLine = context.state.nextLine, !nextLine.isEmpty {
                    Text(nextLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func skeletonBar(fraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.16))
            .frame(height: 12)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: geo.size.width * fraction)
                }
            }
    }
}

/// Expanded bottom: the source badge + inline progress (design `.ix-foot`).
private struct IslandBottom: View {
    let context: ActivityViewContext<LyricsActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            // Source badge — Apple Music in the current MVP (Spotify plays via
            // the system player too once connected).
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 8))
                Text("Apple Music")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.66))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white.opacity(0.75))
                        .frame(width: max(3, geo.size.width * CGFloat(context.state.progress)))
                }
            }
            .frame(height: 3)
        }
    }
}

private extension View {
    /// Render both sources' progress bars in preview canvases.
    func previewProgressBar() -> some View { self }
}