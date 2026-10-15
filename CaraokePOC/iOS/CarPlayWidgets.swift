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
    var spacing: CGFloat = 2
    var buttonWidth: CGFloat = 34
    var buttonHeight: CGFloat = 34
    /// The hybrid widget drops Previous so its title row gets the width back
    /// and renders un-truncated (user direction, build 66).
    var showPrevious: Bool = true
    @Environment(\.legibilityWeight) private var legibilityWeight
    private var bold: Bool { entry.settings.boldText && legibilityWeight != .bold }

    var body: some View {
        HStack(spacing: spacing) {
            if showPrevious {
                button("backward.fill", PreviousTrackIntent(), "Previous song", size)
            }
            button(entry.isPlaying ? "pause.fill" : "play.fill",
                   PlayPauseIntent(), entry.isPlaying ? "Pause" : "Play", size + 2)
            button("forward.fill", NextTrackIntent(), "Next song", size)
        }
    }

    private func button<I: AppIntent>(_ name: String, _ intent: I,
                                      _ label: String, _ size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: name)
                .font(.system(size: size, weight: LyricType.chromeWeight(.semibold, boldText: bold)))
                .foregroundColor(tint)
                .frame(width: buttonWidth, height: buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Always-visible refresh affordance. The cover is the canonical resync tap
/// target, but on the CarPlay tiles it renders small — user direction, build
/// 66: the button must appear on the lyric area too (and on the hybrid's
/// cover), never just as a cover-sized tap target.
private struct CaraokeCarPlayResyncButton: View {
    let entry: CaraokeWidgetEntry
    var glyphSize: CGFloat = 15
    /// Where the tile allows, keep the touch target at the 44 pt guideline.
    var hitTarget: CGFloat = 44
    @Environment(\.legibilityWeight) private var legibilityWeight
    private var bold: Bool { entry.settings.boldText && legibilityWeight != .bold }

    var body: some View {
        Button(intent: ResyncWidgetIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: glyphSize, weight: LyricType.chromeWeight(.semibold, boldText: bold)))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resync lyrics")
    }
}

/// Cover art, tapped to resync — the same contract the Home Screen widgets use.
private struct CaraokeCarPlayCover: View {
    let entry: CaraokeWidgetEntry
    let size: CGFloat
    var cornerRadius: CGFloat? = nil
    /// Always show the resync glyph on the cover (build 66 — the hybrid's cover
    /// is small enough that an invisible tap-only affordance missed it).
    var showsResyncGlyph: Bool = false
    private var radius: CGFloat { cornerRadius ?? max(4, size * 0.22) }
    private var theme: WidgetTheme { WidgetTheme(rawValue: entry.settings.theme) ?? .artwork }

    var body: some View {
        Button(intent: ResyncWidgetIntent()) {
            Group {
                if let data = entry.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.34))
                            .foregroundColor(theme.mutedTextColor)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(theme.textColor.opacity(0.12), lineWidth: 1))
            .overlay {
                if showsResyncGlyph || entry.status != .playing || entry.resyncPulse < 1 {
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
    @Environment(\.legibilityWeight) private var legibilityWeight
    private var bold: Bool { entry.settings.boldText && legibilityWeight != .bold }

    var body: some View {
        VStack(spacing: 1) {
            // Build 66: `minimumScaleFactor(0.85)` is GONE (spec §2.3 — nothing
            // scales at render time). The title wraps to its 2 lines instead of
            // shrinking or ellipsizing mid-word.
            Text(entry.title.isEmpty ? "Caraoke" : entry.title)
                .font(.system(size: titleSize,
                             weight: LyricType.chromeWeight(.semibold, boldText: bold)))
                .foregroundColor(titleColor)
                .lineLimit(2)
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
            .overlay(alignment: .bottomLeading) { WidgetDebugStampView(stamp: entry.debugStamp) }
            .widgetURL(URL(string: "caraoke://lyrics"))
            .containerBackground(for: .widget) {
                WidgetArtworkBackground(theme: entry.theme, artworkData: entry.artworkData)
            }
    }
}

/// The bake stamp, rendered small in a corner of the tile.
///
/// Present on every CarPlay tile and on the Home Screen widget. Nil — and so
/// invisible — unless `SharedWidgetSettings.debugStamp` is on, which is
/// currently the default for test builds. Read it off the car screen when the
/// tile freezes: see `WidgetDebugStamp` for what each field means and
/// `rea/findings-carplay-lyric-sync.md` §9 for the three readings.
struct WidgetDebugStampView: View {
    let stamp: WidgetDebugStamp?

    var body: some View {
        if let stamp {
            Text(stamp.line)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(2)
                .accessibilityLabel("Timeline \(stamp.index + 1) of \(stamp.total)")
        }
    }
}

// MARK: - Layer 1 — Player

private struct CaraokePlayerWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
        let t = entry.theme
        GeometryReader { geo in
            let cover = min(geo.size.width, geo.size.height) * 0.52
            VStack(spacing: 0) {
                CaraokeCarPlayCover(entry: entry, size: cover)
                    .padding(.top, 6)
                Spacer(minLength: 2)
                CaraokeCarPlayIdentity(entry: entry, titleColor: t.textColor,
                                       mutedColor: t.mutedTextColor, titleSize: 13)
                Spacer(minLength: 4)
                CaraokeCarPlayProgress(progress: entry.progress, tint: t.textColor)
                    .frame(width: 130)
                    .padding(.bottom, 6)
                CaraokeCarPlayTransport(entry: entry, tint: t.textColor, spacing: 10, buttonWidth: 38, buttonHeight: 32)
                    .padding(.bottom, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Layer 2 — Lyrics

private struct CaraokeCarPlayLyricsWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                surface: .carPlayLyrics,
                palette: entry.widgetPalette,
                artworkData: entry.artworkData,
                resyncPulse: entry.resyncPulse,
                needsResync: entry.status != .playing || entry.resyncPulse < 1,
                showsProgressBar: false,
                boldText: entry.settings.boldText
            )
            // No cover on this tile to tap, so the resync button lives on the
            // lyric area itself (user direction, build 66).
            CaraokeCarPlayResyncButton(entry: entry)
                .padding(2)
        }
    }
}

// MARK: - Layer 3 — Hybrid (the huge-square layout, folded into one tile)

private struct CaraokeCarPlayHybridWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
        let t = entry.theme
        GeometryReader { geo in
            // Lyrics allocate 65% of the tile height.
            let lyricHeight = geo.size.height * 0.65
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
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
                        needsResync: entry.status != .playing || entry.resyncPulse < 1,
                        showsProgressBar: false,
                        customBoxHeight: lyricHeight,
                        customPadding: 8,
                        boldText: entry.settings.boldText
                    )
                    // User direction, build 66: the resync button appears on
                    // BOTH the cover and the lyric lines — the cover is too
                    // small to be the only tap target.
                    CaraokeCarPlayResyncButton(entry: entry, glyphSize: 12)
                        .padding(2)
                }
                .frame(height: lyricHeight)

                HStack(spacing: 6) {
                    CaraokeCarPlayCover(entry: entry, size: 24, showsResyncGlyph: true)
                    CaraokeCarPlayIdentity(entry: entry, titleColor: t.textColor,
                                           mutedColor: t.mutedTextColor, titleSize: 11.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Build 66: no Previous button on the hybrid — the space it
                    // took is what truncated the title ("Wa…"). Play/pause +
                    // Next stay; the reclaimed width flows to the title above.
                    CaraokeCarPlayTransport(entry: entry, tint: t.textColor, size: 12,
                                           buttonWidth: 26, buttonHeight: 28,
                                           showPrevious: false)
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 4)
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
