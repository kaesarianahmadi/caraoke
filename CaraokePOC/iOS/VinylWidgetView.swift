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
            // Original vinyl disc proportions (60% lyrics width, 14 pt padding).
            let inner = CGSize(width: geometry.size.width - 28,
                               height: geometry.size.height - 28)
            let lyricsWidth = inner.width * 0.60
            let disc = min(inner.height, inner.width - lyricsWidth - 8)

            HStack(spacing: 8) {
                lyricsSection
                    .frame(width: lyricsWidth, alignment: .leading)
                cover(diameter: disc)
                    .frame(width: disc, height: disc)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
        }
        .foregroundStyle(theme.textColor)
        .containerBackground(for: .widget) {
            WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData)
        }
        .widgetURL(URL(string: "caraoke://lyrics"))
    }

    private var lyricsSection: some View {
        // Identity pinned to the top, transport elevated from the bottom, lyrics
        // centred in whatever is left.
        VStack(alignment: .leading, spacing: 0) {
            Text(identity)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.mutedTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            lyricBlock
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                intentButton("backward.fill", intent: PreviousTrackIntent(), label: "Previous song", size: 13)
                intentButton(entry.isPlaying ? "pause.fill" : "play.fill", intent: PlayPauseIntent(), label: entry.isPlaying ? "Pause" : "Play", size: 16)
                intentButton("forward.fill", intent: NextTrackIntent(), label: "Next song", size: 13)
            }
            .padding(.bottom, 6)
        }
    }

    /// Active lyric is anchored at the first row.
    /// When upcoming line exists, active line and upcoming line each take 1 row (2 lines total).
    /// If no upcoming line exists (e.g. final line of song), active line can wrap up to 2 rows.
    private var lyricBlock: some View {
        let text = currentLyricText
        let next = entry.nextLine?.trimmingCharacters(in: .whitespaces)
        let hasNext = next != nil && !next!.isEmpty

        return VStack(alignment: .leading, spacing: LyricType.lyricRowSpacing) {
            if !text.isEmpty {
                Text(text)
                    .font(LyricType.font(size: LyricType.lyric, weight: LyricType.lyricHeroWeight))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(hasNext ? 1 : 2)
                    .lineSpacing(LyricType.lyricLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next, !next.isEmpty {
                Text(next)
                    .font(LyricType.font(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.82))
                    .lineLimit(1)
                    .lineSpacing(LyricType.lyricLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lyricEdgeFade(active: true)
        .id(entry.lineIndex)
        .transition(.push(from: .bottom))
    }

    private var currentLyricText: String {
        if !entry.currentLine.isEmpty {
            return entry.currentLine
        }
        if !entry.previousLines.isEmpty && entry.isPlaying {
            return "" // outro transition
        }
        if !entry.title.isEmpty {
            return entry.artist.isEmpty ? entry.title : "\(entry.title) — \(entry.artist)"
        }
        return "Play a song to see lyrics"
    }

    /// The record/cover IS the resync button — tapping it refreshes the shared
    /// payload in place instead of opening the app. It pulses (timeline-driven,
    /// WidgetKit has no animation) while the resync is in flight, and shows a
    /// refresh glyph whenever the lyrics are out of sync so the tap is obvious.
    @ViewBuilder private func cover(diameter: CGFloat) -> some View {
        Button(intent: ResyncWidgetIntent()) {
            Group {
                if coverStyle == .vinyl {
                    vinyl(diameter: diameter)
                } else {
                    Group {
                        if let artwork {
                            Image(uiImage: artwork).resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.white.opacity(0.1)).overlay(Image(systemName: "music.note").font(.title2))
                        }
                    }
                    .frame(width: diameter, height: diameter)
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

    /// Record with the cover as its label. Uses shared VinylRecordView.
    private func vinyl(diameter: CGFloat) -> some View {
        VinylRecordView(artworkImage: artwork, diameter: diameter,
                        labelDiameter: diameter * 0.7)
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
