import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - CarPlay widget stack
//
// iOS 26 renders iPhone widgets on the CarPlay screen in one or more stacks
// (Settings → General → CarPlay → [car] → Customize → Widgets). Apple only
// ever renders the `systemSmall` family there — it scales that one family to
// the tile, regardless of what else the widget declares. So the three tiles
// Caraoke offers the car are all `.systemSmall`:
//
//   * Layer 1 — Player:    cover, title, artist, progress, transport buttons.
//   * Layer 2 — Lyrics:    the lyric tile alone, nothing else.
//   * Layer 3 — Hybrid:    the huge-square widget's layout, folded into one
//                          small tile: lyrics on top, player bar underneath.
//
// Widgets are non-interactive on head units without a touchscreen, and on
// touchscreen units a widget's buttons run their `AppIntent` directly — which
// is why the transport row here is real buttons and not a picture of one.
// Apple is explicit about that in "Adding StandBy and CarPlay support to your
// widget", and it is how other CarPlay lyric apps ship working skip/pause.

// MARK: - Transport row (shared by Layers 1 and 3)

private struct CaraokeCarPlayTransport: View {
    let entry: CaraokeWidgetEntry
    let tint: Color
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 2) {
            button("backward.fill", PreviousTrackIntent(), "Previous song", size)
            button(entry.isPlaying ? "pause.fill" : "play.fill",
                   PlayPauseIntent(), entry.isPlaying ? "Pause" : "Play", size + 2)
            button("forward.fill", NextTrackIntent(), "Next song", size)
        }
    }

    private func button<I: AppIntent>(_ name: String, _ intent: I,
                                      _ label: String, _ size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Cover art, tapped to resync — the same contract the Home Screen widgets use.
private struct CaraokeCarPlayCover: View {
    let entry: CaraokeWidgetEntry
    let size: CGFloat
    private var theme: WidgetTheme { WidgetTheme(rawValue: entry.settings.theme) ?? .artwork }

    var body: some View {
        Button(intent: ResyncWidgetIntent()) {
            Group {
                if let data = entry.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.34))
                            .foregroundColor(theme.mutedTextColor)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.textColor.opacity(0.12), lineWidth: 1))
            .overlay {
                if entry.status != .playing || entry.resyncPulse < 1 {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .opacity(entry.resyncPulse)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resync lyrics")
    }
}

private struct CaraokeCarPlayProgress: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule().fill(tint.opacity(0.92))
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 3)
    }
}

private struct CaraokeCarPlayIdentity: View {
    let entry: CaraokeWidgetEntry
    let titleColor: Color
    let mutedColor: Color
    let titleSize: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            Text(entry.title.isEmpty ? "Caraoke" : entry.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundColor(titleColor)
                .lineLimit(1)
            if !entry.artist.isEmpty {
                Text(entry.artist)
                    .font(.system(size: titleSize - 1.5))
                    .foregroundColor(mutedColor)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - Shared chrome

private extension CaraokeWidgetEntry {
    var theme: WidgetTheme { WidgetTheme(rawValue: settings.theme) ?? .artwork }

    var widgetPalette: LyricTilePalette {
        let t = theme
        return LyricTilePalette(
            cardBackground: .clear,
            cardBorder: .clear,
            titleText: t.textColor,
            artistText: t.mutedTextColor,
            badgeText: t.mutedTextColor,
            heroText: t.textColor,
            nextText: t.mutedTextColor,
            metaText: t.mutedTextColor,
            trackBackground: t.textColor.opacity(0.18),
            trackFill: t.textColor.opacity(0.92),
            glow: t.textColor.opacity(0.7)
        )
    }
}

private struct CaraokeCarPlayChrome<Content: View>: View {
    let entry: CaraokeWidgetEntry
    let content: Content

    init(entry: CaraokeWidgetEntry, @ViewBuilder content: () -> Content) {
        self.entry = entry
        self.content = content()
    }

    var body: some View {
        content
            .widgetURL(URL(string: "caraoke://lyrics"))
            .containerBackground(for: .widget) {
                WidgetArtworkBackground(theme: entry.theme, artworkColorHex: entry.artworkColorHex)
            }
    }
}

// MARK: - Layer 1 — Player

private struct CaraokePlayerWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
        let t = entry.theme
        GeometryReader { geo in
            let cover = min(geo.size.width, geo.size.height) * 0.46
            VStack(spacing: 0) {
                CaraokeCarPlayCover(entry: entry, size: cover)
                Spacer(minLength: 6)
                CaraokeCarPlayIdentity(entry: entry, titleColor: t.textColor,
                                       mutedColor: t.mutedTextColor, titleSize: 12.5)
                Spacer(minLength: 6)
                CaraokeCarPlayProgress(progress: entry.progress, tint: t.textColor)
                    .padding(.bottom, 6)
                CaraokeCarPlayTransport(entry: entry, tint: t.textColor)
            }
            .padding(12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Layer 2 — Lyrics

private struct CaraokeCarPlayLyricsWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
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
            surface: .carPlaySmall,
            palette: entry.widgetPalette,
            artworkData: entry.artworkData,
            resyncPulse: entry.resyncPulse,
            needsResync: entry.status != .playing || entry.resyncPulse < 1
        )
    }
}

// MARK: - Layer 3 — Hybrid (the huge-square layout, folded into one tile)

private struct CaraokeCarPlayHybridWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
        let t = entry.theme
        GeometryReader { geo in
            // Lyrics keep ~62% of the tile (the large widget gives them 75%,
            // but a small tile still has to fit the player bar underneath).
            // No explicit height: the tile's own budget decides how many rows
            // actually fit, and the bar takes what is left.
            VStack(spacing: 0) {
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
                    surface: .carPlaySmall,
                    palette: entry.widgetPalette,
                    artworkData: entry.artworkData,
                    resyncPulse: entry.resyncPulse,
                    needsResync: entry.status != .playing || entry.resyncPulse < 1
                )
                .frame(height: geo.size.height * 0.62)

                HStack(spacing: 8) {
                    CaraokeCarPlayCover(entry: entry, size: 34)
                    CaraokeCarPlayIdentity(entry: entry, titleColor: t.textColor,
                                           mutedColor: t.mutedTextColor, titleSize: 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CaraokeCarPlayTransport(entry: entry, tint: t.textColor, size: 13)
                }
                .padding(.top, 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Widget definitions

/// Layer 1. Cover + identity + progress + working transport buttons.
struct CaraokePlayerWidget: Widget {
    let kind: String = "CaraokePlayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider()) { entry in
            CaraokeCarPlayChrome(entry: entry) { CaraokePlayerWidgetView(entry: entry) }
        }
        .configurationDisplayName("Caraoke Player")
        .description("Cover, track and playback controls for the CarPlay widget stack.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

/// Layer 2. Lyrics only — no cover, no controls.
struct CaraokeLyricsWidget: Widget {
    let kind: String = "CaraokeLyricsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider()) { entry in
            CaraokeCarPlayChrome(entry: entry) { CaraokeCarPlayLyricsWidgetView(entry: entry) }
        }
        .configurationDisplayName("Caraoke Lyrics")
        .description("Synced lyrics only, sized for the CarPlay widget stack.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

/// Layer 3. The huge-square layout in one tile: lyrics on top, player bar under.
struct CaraokeHybridWidget: Widget {
    let kind: String = "CaraokeHybridWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider()) { entry in
            CaraokeCarPlayChrome(entry: entry) { CaraokeCarPlayHybridWidgetView(entry: entry) }
        }
        .configurationDisplayName("Caraoke Hybrid")
        .description("Lyrics, cover and controls together for the CarPlay widget stack.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}
