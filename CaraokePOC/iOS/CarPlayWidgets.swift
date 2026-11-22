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
    var buttonWidth: CGFloat = 44
    var buttonHeight: CGFloat = 44
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

/// The whole lyrics area requests repair; the glyph only marks proven expiry.
private struct CaraokeCarPlayResyncButton<Content: View>: View {
    let entry: CaraokeWidgetEntry
    let content: Content

    var body: some View {
        Button(intent: ResyncWidgetIntent()) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if entry.status == .expired {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .padding(4)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.currentLine.isEmpty ? "Resync lyrics" : "\(entry.currentLine). Tap to resync lyrics")
    }
}

/// Cover art, tapped to resync — the same contract the Home Screen widgets use.
private struct CaraokeCarPlayCover: View {
    let entry: CaraokeWidgetEntry
    let size: CGFloat
    var minTapTarget: CGFloat = 44
    var cornerRadius: CGFloat? = nil
    var hideResyncGlyph: Bool = false
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
                if !hideResyncGlyph && (entry.status != .playing || entry.resyncPulse < 1) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .opacity(entry.resyncPulse)
            .frame(minWidth: minTapTarget, minHeight: minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.currentLine.isEmpty ? "Resync lyrics" : "\(entry.currentLine). Tap to resync lyrics")
    }
}

private struct CaraokeCarPlayProgress: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                if progress > 0 {
                    Capsule().fill(tint.opacity(0.92))
                        .frame(width: geo.size.width * CGFloat(min(progress, 1)))
                }
            }
        }
        .frame(height: 2)
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
            Text(entry.title.isEmpty ? "Caraoke" : entry.title)
                .font(.system(size: titleSize,
                             weight: LyricType.chromeWeight(.semibold, boldText: bold)))
                .foregroundColor(titleColor)
                .lineLimit(2)
                .minimumScaleFactor(0.92)
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
                WidgetArtworkBackground(theme: entry.theme, artworkData: entry.artworkData)
            }
    }
}


// MARK: - Layer 1 — Player

private struct CaraokePlayerWidgetView: View {
    let entry: CaraokeWidgetEntry

    var body: some View {
        let t = entry.theme
        GeometryReader { geo in
            // Reserve two title lines, artist, progress, and the full control row.
            let cover = min(62, max(44, geo.size.height - 98))
            VStack(spacing: 2) {
                CaraokeCarPlayCover(entry: entry, size: cover)
                CaraokeCarPlayIdentity(entry: entry, titleColor: t.textColor,
                                       mutedColor: t.mutedTextColor, titleSize: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                CaraokeCarPlayProgress(progress: entry.progress, tint: t.textColor)
                    .frame(width: max(0, min(130, geo.size.width - 8)))
                CaraokeCarPlayTransport(entry: entry, tint: t.textColor, spacing: 2, buttonWidth: 44)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Layer 2 — Lyrics

private struct CaraokeCarPlayLyricsWidgetView: View {
    let entry: CaraokeWidgetEntry
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var foreground: Color {
        (!showsBackground && entry.theme == .ivoryWhite) ? .white : entry.theme.textColor
    }

    var body: some View {
        CaraokeCarPlayResyncButton(entry: entry, content:
            CompactLyricsView(currentLine: entry.currentLine,
                previousLines: entry.previousLines, upcomingLines: entry.upcomingLines,
                title: entry.title, artist: entry.artist, status: entry.status,
                fontSize: 15, foreground: foreground, boldText: entry.settings.boldText,
                 topInset: entry.status == .expired ? 30 : 0, slideTransitions: true))
    }
}

// MARK: - Layer 3 — Hybrid (the huge-square layout, folded into one tile)

private struct CaraokeCarPlayHybridWidgetView: View {
    let entry: CaraokeWidgetEntry
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var foreground: Color {
        (!showsBackground && entry.theme == .ivoryWhite) ? .white : entry.theme.textColor
    }

    var body: some View {
        let fg = foreground
        VStack(spacing: 2) {
            CaraokeCarPlayResyncButton(entry: entry, content:
                CompactLyricsView(currentLine: entry.currentLine,
                    previousLines: entry.previousLines, upcomingLines: entry.upcomingLines,
                    title: entry.title, artist: entry.artist, status: entry.status,
                    fontSize: 15, foreground: fg, boldText: entry.settings.boldText,
                     topInset: entry.status == .expired ? 30 : 0, slideTransitions: true))
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
            CaraokeCarPlayProgress(progress: entry.progress, tint: fg)
                .padding(.horizontal, 6)
            // Compact competitor-style strip: metadata gets one line each and
            // may ellipsize; it never steals rows from the lyrics.
            HStack(spacing: 6) {
                // The full lyrics area already provides a large resync target.
                CaraokeCarPlayCover(entry: entry, size: 28, minTapTarget: 28, hideResyncGlyph: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title.isEmpty ? "Caraoke" : entry.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(t.mutedTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CaraokeCarPlayTransport(entry: entry, tint: t.textColor, size: 12,
                    buttonWidth: 44, showPrevious: false)
            }
            .foregroundStyle(t.textColor)
            .frame(height: 44)
            .padding(.horizontal, 4)
        }
    }
}


// MARK: - Widget definitions

/// Layer 1. Cover + identity + progress + working transport buttons.
struct CaraokePlayerWidget: Widget {
    let kind = SharedWidgetStore.Kind.player.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider(playerOnly: true)) { entry in
            CaraokeCarPlayChrome(entry: entry) { CaraokePlayerWidgetView(entry: entry) }
        }
        .configurationDisplayName("Caraoke Player")
        .description("Cover, track and playback controls for the CarPlay widget stack.")
        .supportedFamilies([.systemSmall])
        .disfavoredLocations([.homeScreen, .lockScreen], for: [.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

/// Layer 2. Lyrics only — no cover, no controls.
struct CaraokeLyricsWidget: Widget {
    let kind = SharedWidgetStore.Kind.lyrics.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider()) { entry in
            CaraokeCarPlayChrome(entry: entry) { CaraokeCarPlayLyricsWidgetView(entry: entry) }
        }
        .configurationDisplayName("Caraoke CarPlay Lyrics")
        .description("Synced lyrics only, sized for the CarPlay widget stack.")
        .supportedFamilies([.systemSmall])
        .disfavoredLocations([.homeScreen, .lockScreen], for: [.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

/// Layer 3. The huge-square layout in one tile: lyrics on top, player bar under.
struct CaraokeHybridWidget: Widget {
    let kind = SharedWidgetStore.Kind.hybrid.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaraokeWidgetProvider()) { entry in
            CaraokeCarPlayChrome(entry: entry) { CaraokeCarPlayHybridWidgetView(entry: entry) }
        }
        .configurationDisplayName("Caraoke Hybrid")
        .description("Lyrics, cover and controls together for the CarPlay widget stack.")
        .supportedFamilies([.systemSmall])
        .disfavoredLocations([.homeScreen, .lockScreen], for: [.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}
