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
            // Tier geometry comes from `MediumWidgetTiers` (CaraokeCore) so the
            // widget, the in-app preview and the budget checks all read one
            // declaration. 12 pt padding gives clean widget margins while
            // preserving space for lyrics and disc.
            let inner = CGSize(width: geometry.size.width - MediumWidgetTiers.padding * 2,
                               height: geometry.size.height - MediumWidgetTiers.padding * 2)
            let lyricsWidth = inner.width * MediumWidgetTiers.lyricColumnFraction
            let disc = min(inner.height, inner.width - lyricsWidth - 8)

            HStack(spacing: 8) {
                lyricsSection
                    .frame(width: lyricsWidth, alignment: .leading)
                cover(diameter: disc)
                    .frame(width: disc, height: disc)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(MediumWidgetTiers.padding)
        }
        .foregroundStyle(theme.textColor)
        .containerBackground(for: .widget) {
            WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData)
        }
        .widgetURL(URL(string: "caraoke://lyrics"))
    }

    // MARK: - Rigid 3-tier layout
    //
    // The tiers, their heights and the wrap allowances all come from
    // `MediumWidgetTiers` (CaraokeCore) — see that type for the arithmetic. Fixed
    // heights mean the lyric block can never push the transport buttons off the
    // bottom: no Spacer, no flexible height, buttons permanently visible.

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tier 1: identity header
            Text(identity)
                .font(.system(size: MediumWidgetTiers.identityFont, weight: .semibold))
                .foregroundStyle(theme.mutedTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: MediumWidgetTiers.identityHeight, alignment: .leading)

            // Tier 2: lyric block — locked, edge-fade masks overflow
            lyricBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: MediumWidgetTiers.lyricHeight)
                .clipped()

            // Tier 3: transport — the clearance is part of the tier, not padding
            // on top of it: 18 + 82 + 34 is exactly the inner height, and a
            // separate bottom padding made the stack taller than the tile and
            // pushed the buttons into the rounded bottom edge it meant to clear.
            HStack(spacing: 14) {
                intentButton("backward.fill", intent: PreviousTrackIntent(),
                             label: "Previous song", size: MediumWidgetTiers.transportFont)
                intentButton(entry.isPlaying ? "pause.fill" : "play.fill",
                             intent: PlayPauseIntent(),
                             label: entry.isPlaying ? "Pause" : "Play",
                             size: MediumWidgetTiers.playGlyphFont)
                intentButton("forward.fill", intent: NextTrackIntent(),
                             label: "Next song", size: MediumWidgetTiers.transportFont)
            }
            .frame(height: MediumWidgetTiers.transportButtonRowHeight)
            .padding(.bottom, MediumWidgetTiers.transportClearance)
        }
    }

    private var lyricBlock: some View {
        let text = currentLyricText
        let next = entry.nextLine?.trimmingCharacters(in: .whitespaces)

        // No width cap on either row. At a 135 pt cap inside a ~188 pt column the
        // text wrapped roughly a quarter early, and that extra wrapping is what
        // pushed the block past its tier — the tier clips, so the bottom line was
        // cut. The column width IS the cap.
        return VStack(alignment: .leading, spacing: MediumWidgetTiers.rowSpacing) {
            if !text.isEmpty {
                Text(text)
                    .font(LyricType.font(size: MediumWidgetTiers.heroFont, weight: .bold))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(MediumWidgetTiers.heroRows)
                    .lineSpacing(MediumWidgetTiers.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next, !next.isEmpty {
                Text(next)
                    .font(LyricType.font(size: MediumWidgetTiers.neighborFont, weight: .regular))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.82))
                    .lineLimit(MediumWidgetTiers.neighborRows)
                    .lineSpacing(MediumWidgetTiers.lineSpacing)
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
