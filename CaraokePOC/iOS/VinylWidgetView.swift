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
                    .frame(width: geometry.size.width * 0.62, alignment: .leading)
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
        // Identity pinned to the top, transport elevated from the bottom, lyrics
        // centred in whatever is left.
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
            .padding(.bottom, 6)
        }
    }

    /// Every row at the SAME 18 pt (`LyricType.lyric`). Emphasis on the active
    /// line is weight only — `.semibold`, not `.bold`. Allows 2 wrapped rows with
    /// subtle scale factor fallback to avoid word clipping.
    private var lyricBlock: some View {
        VStack(alignment: .leading, spacing: LyricType.lyricRowSpacing) {
            if let previous = entry.previousLines.last, !previous.isEmpty {
                Text(previous)
                    .font(.system(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !currentLyricText.isEmpty {
                Text(currentLyricText)
                    .font(.system(size: LyricType.lyric, weight: LyricType.lyricWeight))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .lineSpacing(LyricType.lyricLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next = entry.nextLine, !next.isEmpty {
                Text(next)
                    .font(.system(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
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

    /// Record with the cover as its label. Uses shared VinylRecordView.
    private var vinyl: some View {
        VinylRecordView(artworkImage: artwork, diameter: 126, labelDiameter: 88)
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
