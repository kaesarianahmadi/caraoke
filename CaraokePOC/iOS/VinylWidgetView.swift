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
            // 12 pt padding gives clean widget margins while preserving space for lyrics and disc.
            let inner = CGSize(width: geometry.size.width - 24,
                               height: geometry.size.height - 24)
            let lyricsWidth = inner.width * 0.60
            let disc = min(inner.height, inner.width - lyricsWidth - 8)

            HStack(spacing: 8) {
                lyricsSection
                    .frame(width: lyricsWidth, alignment: .leading)
                cover(diameter: disc)
                    .frame(width: disc, height: disc)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
        }
        .foregroundStyle(theme.textColor)
        .containerBackground(for: .widget) {
            WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData)
        }
        .widgetURL(URL(string: "caraoke://lyrics"))
    }

    // MARK: - Rigid 3-tier layout
    //
    // The 2x4 widget is 338×158 pt. After 12 pt outer padding on each side the
    // usable height is 134 pt. Three tiers split that budget with FIXED heights
    // so the lyric block can never push the transport buttons off the bottom:
    //
    //   Tier 1 — Identity header:  18 pt
    //   Tier 2 — Lyric block:      82 pt (locked frame, edge-fade handles overflow)
    //   Tier 3 — Transport:        34 pt (26 pt buttons + 8 pt bottom clearance)
    //   Total:                    134 pt
    //
    // No Spacer. No flexible height. Buttons are permanently visible.

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tier 1: identity header — fixed 18 pt
            Text(identity)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.mutedTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 18, alignment: .leading)

            // Tier 2: lyric block — locked 82 pt, edge-fade masks overflow
            lyricBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 82)
                .clipped()

            // Tier 3: transport — 26 pt buttons + 8 pt clearance = 34 pt.
            // The clearance is part of the tier, not padding on top of it:
            // 18 + 82 + 34 is exactly the 134 pt the widget gives us, and a
            // separate `.padding(.bottom, 6)` made the stack 140 pt, pushing
            // the buttons into the rounded bottom edge it was meant to clear.
            HStack(spacing: 14) {
                intentButton("backward.fill", intent: PreviousTrackIntent(), label: "Previous song", size: 13)
                intentButton(entry.isPlaying ? "pause.fill" : "play.fill", intent: PlayPauseIntent(), label: entry.isPlaying ? "Pause" : "Play", size: 16)
                intentButton("forward.fill", intent: NextTrackIntent(), label: "Next song", size: 13)
            }
            .frame(height: 26)
            .padding(.bottom, 8)
        }
    }

    // ponytail: font sizes are hard-coded for the 82 pt lyric tier; if the
    // widget grid ever changes, recalculate from (tier height / max lines).
    private static let heroFont: CGFloat = 15
    private static let neighborFont: CGFloat = 13

    private var lyricBlock: some View {
        let text = currentLyricText
        let next = entry.nextLine?.trimmingCharacters(in: .whitespaces)

        return VStack(alignment: .leading, spacing: 5) {
            if !text.isEmpty {
                Text(text)
                    .font(LyricType.font(size: Self.heroFont, weight: .bold))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(3)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 135, alignment: .leading)
            }
            if let next, !next.isEmpty {
                Text(next)
                    .font(LyricType.font(size: Self.neighborFont, weight: .regular))
                    .foregroundStyle(theme.mutedTextColor.opacity(0.82))
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 135, alignment: .leading)
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
