import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// Competitor-style medium widget: lyrics left, large record or cover right.
/// WidgetKit's timeline-entry transition supplies the lyric slide; this view
/// stays static so manual refresh never flashes through an animation reset.
struct VinylWidgetView: View {
    let entry: CaraokeWidgetEntry

    private var theme: WidgetTheme { WidgetTheme(rawValue: entry.settings.theme) ?? .artwork }
    private var coverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: entry.settings.coverStyle) ?? .vinyl }
    private var artwork: UIImage? { entry.artworkData.flatMap(UIImage.init(data:)) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                lyricsSection
                    .frame(width: geometry.size.width * 0.56, alignment: .leading)
                cover
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
        }
        .foregroundStyle(theme.textColor)
        .containerBackground(for: .widget) {
            WidgetArtworkBackground(theme: theme, artworkColorHex: entry.artworkColorHex)
        }
        .widgetURL(URL(string: "caraoke://lyrics"))
    }

    private var lyricsSection: some View {
        // Identity pinned to the top, transport pinned to the bottom, lyrics
        // centred in whatever is left. Build 40 stacked all three from the top
        // with a fixed 80 pt clip, which is why the block sat high with dead
        // space below it and lost its tail behind the clip.
        VStack(alignment: .leading, spacing: 0) {
            Text(identity)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.mutedTextColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            lyricBlock
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                intentButton("backward.fill", intent: PreviousTrackIntent(), label: "Previous song", size: 13)
                intentButton(entry.isPlaying ? "pause.fill" : "play.fill", intent: PlayPauseIntent(), label: entry.isPlaying ? "Pause" : "Play", size: 16)
                intentButton("forward.fill", intent: NextTrackIntent(), label: "Next song", size: 13)
            }
        }
    }

    /// Every row at the SAME 18 pt (`LyricType.lyric`). Emphasis on the active
    /// line is weight only — `.semibold`, not `.bold` (user direction: build
    /// 40's active line was too heavy). No `minimumScaleFactor`: a long line
    /// wraps into the two-row budget instead of shrinking. Keyed by line index
    /// so WidgetKit pushes each new line in from the bottom.
    private var lyricBlock: some View {
        VStack(alignment: .leading, spacing: LyricType.lyricRowSpacing) {
            if let previous = entry.previousLines.last, !previous.isEmpty {
                Text(previous)
                    .font(.system(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.42))
                    .lineLimit(1)
            }
            Text(entry.currentLine.isEmpty ? "Play a song to see lyrics" : entry.currentLine)
                .font(.system(size: LyricType.lyric, weight: LyricType.lyricWeight))
                .foregroundStyle(theme.textColor)
                .lineLimit(2)
                .lineSpacing(LyricType.lyricLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
            if let next = entry.nextLine, !next.isEmpty {
                Text(next)
                    .font(.system(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .id(entry.lineIndex)
        .transition(.push(from: .bottom))
    }

    /// The record/cover IS the resync button — tapping it refreshes the shared
    /// payload in place instead of opening the app. It pulses (timeline-driven,
    /// WidgetKit has no animation) while the resync is in flight, and shows a
    /// refresh glyph whenever the lyrics are out of sync so the tap is obvious.
    @ViewBuilder private var cover: some View {
        Button(intent: ResyncWidgetIntent()) {
            Group {
                if coverStyle == .vinyl {
                    vinyl
                } else {
                    Group {
                        if let artwork {
                            Image(uiImage: artwork).resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.white.opacity(0.1)).overlay(Image(systemName: "music.note").font(.title2))
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
                }
            }
            .overlay {
                if needsResync {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 4)
                }
            }
            .opacity(entry.resyncPulse)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resync lyrics")
    }

    private var needsResync: Bool {
        entry.status != .playing || entry.resyncPulse < 1
    }

    /// Record with the cover as its label. The label is 70 % of the disc
    /// diameter (user direction) so the artwork is readable at widget size.
    private var vinyl: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.black, Color(white: 0.16), .black], center: .center, startRadius: 8, endRadius: 65))
            ForEach(0..<7, id: \.self) { index in
                Circle().stroke(.white.opacity(0.07), lineWidth: 0.5)
                    .padding(CGFloat(index * 7 + 5))
            }
            Group {
                if let artwork {
                    Image(uiImage: artwork).resizable().scaledToFill()
                } else {
                    Circle().fill(.gray.opacity(0.35)).overlay(Image(systemName: "music.note"))
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.15)))
            Circle().fill(.white.opacity(0.55)).frame(width: 7, height: 7)
        }
        .frame(width: 126, height: 126)
        .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
    }

    private var identity: String {
        entry.artist.isEmpty ? entry.title : "\(entry.title) — \(entry.artist)"
    }

    private func intentButton<I: AppIntent>(_ name: String, intent: I, label: String, size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Widget background: the artwork's average colour when the theme follows the
/// cover, otherwise the flat theme colour.
struct WidgetArtworkBackground: View {
    let theme: WidgetTheme
    let artworkColorHex: String?

    var body: some View {
        if theme == .artwork, let hex = artworkColorHex, let color = Color(hexString: hex) {
            LinearGradient(
                colors: [color.opacity(0.92), color.opacity(0.52), .black.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            theme.backgroundColor
        }
    }
}
