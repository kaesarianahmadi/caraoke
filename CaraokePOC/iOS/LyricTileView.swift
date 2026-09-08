import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Shared lyric layout (design: design/screens/live-activity.html)

/// One view, every surface: Lock Screen Live Activity banner, CarPlay mirror,
/// the persistent Home Screen widgets, and the in-app home player card.
/// Renders the dark karaoke lyric block with static anti-flicker container.

/// Layout capacity knobs per surface. `lyricFont` is the user-mandated 18 pt
/// everywhere lyrics render (widgets + in-app + Live Activity).
struct LyricTileLayout {
    var lyricFont: CGFloat = 18
    var heroLines: Int = 2          // wrapping budget of the active line
    var upcomingShown: Int = 3      // dimmed follow-on lines (LA: hero+3 = 4-5 rows)
    var upcomingLines: Int = 2      // each dimmed line may re-wrap to 2 visual rows
    var boxHeight: CGFloat = 128    // fixed anti-flicker lyric container
    var headerCompact: Bool = false // one identity row instead of title+artist stack
    var showsHeader: Bool = true
    var showsBottomBar: Bool = false // large-widget cover/title/transport row
    var padding: CGFloat = 16
}

struct LyricTilePalette {
    let cardBackground: Color
    let cardBorder: Color
    let titleText: Color
    let artistText: Color
    let badgeText: Color
    let heroText: Color
    let nextText: Color
    let metaText: Color
    let trackBackground: Color
    let trackFill: Color
    let glow: Color

    /// Lock Screen Live Activity. NO opaque card (see `usesOwnCard`): the
    /// system renders the iOS 26 translucent glass behind the content, which
    /// is what makes it look native next to Spotify's player — our own solid
    /// black rounded rect used to paint right over that glass.
    static let activity = LyricTilePalette(
        cardBackground: Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255).opacity(0.68),
        cardBorder: Color.white.opacity(0.07),
        titleText: Color.white.opacity(0.96),
        artistText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.48),
        badgeText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.62),
        heroText: .white,
        nextText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.55),
        metaText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.4),
        trackBackground: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.18),
        trackFill: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.75),
        glow: Color(hex: 0xFF9845)
    )

    /// Home player card — follows the app theme (AppTheme tokens).
    static func home(_ scheme: ColorScheme) -> LyricTilePalette {
        LyricTilePalette(
            cardBackground: AppTheme.surface(scheme),
            cardBorder: AppTheme.border(scheme),
            titleText: AppTheme.fg(scheme),
            artistText: AppTheme.muted(scheme),
            badgeText: AppTheme.muted(scheme),
            heroText: AppTheme.fg(scheme),
            nextText: AppTheme.muted(scheme),
            metaText: AppTheme.muted(scheme),
            trackBackground: AppTheme.fg(scheme).opacity(0.16),
            trackFill: AppTheme.fg(scheme).opacity(0.75),
            glow: AppTheme.accent(scheme)
        )
    }
}

struct LyricTileView: View {
    let title: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    let upcomingLines: [String]
    let isPlaying: Bool
    let progress: Double
    let status: LyricStatus
    let positionMs: Int
    let durationMs: Int?
    /// The surface this tile renders on. Drives layout AND the background:
    /// the Lock Screen banner paints no card of its own so the iOS 26 glass
    /// shows through; CarPlay's small mirror has no system blur, so it keeps
    /// the dark card for contrast.
    enum Surface {
        case lockBanner       // Lock Screen Live Activity (system glass)
        case carPlaySmall     // CarPlay mirror of the activity (own card)
        case widgetSmall      // Home Screen 2x2
        case widgetMedium     // Home Screen 2x4 ("regular")
        case widgetLarge      // Home Screen 4x4 ("huge square")
        case home             // in-app player card (own card, theme palette)

        var isWidget: Bool { self == .widgetSmall || self == .widgetMedium || self == .widgetLarge }
    }
    let surface: Surface
    var palette: LyricTilePalette?
    var artworkData: Data? = nil

    @Environment(\.colorScheme) private var scheme

    private var colors: LyricTilePalette { palette ?? .activity }

    private var layout: LyricTileLayout {
        switch surface {
        case .lockBanner:
            return LyricTileLayout()  // 18pt, hero+3 upcoming, 128 box, 16 pad
        case .carPlaySmall:
            return LyricTileLayout(boxHeight: 128)
        case .widgetSmall:
            return LyricTileLayout(upcomingShown: 1, upcomingLines: 1,
                                   boxHeight: 76, padding: 14)
        case .widgetMedium:
            return LyricTileLayout(upcomingShown: 3, upcomingLines: 2,
                                   boxHeight: 104, headerCompact: true, padding: 16)
        case .widgetLarge:
            // Competitor blueprint: lyrics own the top, identity + transport
            // live in the bottom row — no header.
            return LyricTileLayout(upcomingShown: 4, boxHeight: 132, showsHeader: false,
                                   showsBottomBar: true, padding: 18)
        case .home:
            return LyricTileLayout(upcomingShown: 3, upcomingLines: 2, boxHeight: 128)
        }
    }

    init(title: String, artist: String, currentLine: String, nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil,
         surface: Surface, palette: LyricTilePalette? = nil, artworkData: Data? = nil) {
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.nextLine = nextLine
        self.upcomingLines = upcomingLines.isEmpty ? (nextLine.map { [$0] } ?? []) : upcomingLines
        self.isPlaying = isPlaying
        self.progress = progress
        self.status = status
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.surface = surface
        self.palette = palette
        self.artworkData = artworkData
    }

    var body: some View {
        let spec = layout
        VStack(alignment: .leading, spacing: 0) {
            if spec.showsHeader {
                header(compact: spec.headerCompact)
            }
            lyricBody(spec: spec)
            if spec.showsBottomBar {
                Spacer(minLength: 8)
            }
            if status != .stale {
                progressRow
            }
            if spec.showsBottomBar {
                bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(spec.padding)
        .background(cardShape(enabled: surface != .lockBanner))
        .overlay(cardStroke(enabled: surface != .lockBanner))
        .opacity(status == .stale ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Only non-glass surfaces paint their own card; the Lock Screen banner
    /// lets the system's iOS 26 translucent material be the background.
    @ViewBuilder
    private func cardShape(enabled: Bool) -> some View {
        if enabled {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colors.cardBackground)
        }
    }

    @ViewBuilder
    private func cardStroke(enabled: Bool) -> some View {
        if enabled {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            // Medium widget: one identity row, badge right — the height the
            // 18pt lyric block needs back comes from here.
            HStack(spacing: 6) {
                Text(identityInline)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(colors.titleText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let badge = status.badge {
                    HStack(spacing: 4) {
                        if status == .paused { pauseGlyph(size: 8) }
                        Text(badge)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.badgeText)
                    .layoutPriority(1)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "Live Lyrics" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.titleText)
                        .lineLimit(1)
                    if !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 11.5))
                            .foregroundColor(colors.artistText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let badge = status.badge {
                    HStack(spacing: 4) {
                        if status == .paused {
                            pauseGlyph(size: 9)
                        }
                        Text(badge)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.badgeText)
                }
            }
        }
    }

    private var identityInline: String {
        if artist.isEmpty { return title.isEmpty ? "Live Lyrics" : title }
        return title.isEmpty ? artist : "\(title) — \(artist)"
    }

    // MARK: - Lyric block (18pt throughout; long lines WRAP to 2 rows so the
    // whole line stays readable instead of running off a "…")

    @ViewBuilder
    private func lyricBody(spec: LyricTileLayout) -> some View {
        switch status {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                skeleton(widthFraction: 0.90)
                skeleton(widthFraction: 0.70)
                skeleton(widthFraction: 0.50)
            }
            .frame(height: spec.boxHeight, alignment: .topLeading)
            .padding(.top, 6)
        case .noLyrics:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    musicNoteGlyph(size: spec.lyricFont - 2)
                    Text(currentLine.isEmpty ? title : currentLine)
                        .font(.system(size: spec.lyricFont, weight: .bold))
                        .foregroundColor(colors.heroText)
                        .lineLimit(1)
                }
                Text("No lyrics found for this song")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(height: spec.boxHeight, alignment: .topLeading)
            .padding(.top, 6)
        case .stale:
            VStack(alignment: .leading, spacing: 6) {
                Text(currentLine.isEmpty ? "Ride ended" : currentLine)
                    .font(.system(size: spec.lyricFont, weight: .bold))
                    .foregroundColor(colors.heroText)
                    .opacity(0.32)
                    .lineLimit(1)
                Text("Lyrics return when a song plays")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(height: spec.boxHeight, alignment: .topLeading)
            .padding(.top, 6)
        default:
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentLine.isEmpty ? (title.isEmpty ? "Play a song to see lyrics" : title) : currentLine)
                        .font(.system(size: spec.lyricFont, weight: .bold))
                        .foregroundColor(colors.heroText)
                        .lineLimit(spec.heroLines)
                        .minimumScaleFactor(0.8)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)

                    if status != .idle {
                        let linesToShow = displayUpcomingLines
                        ForEach(Array(linesToShow.prefix(spec.upcomingShown).enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: spec.lyricFont, weight: .medium))
                                .foregroundColor(colors.nextText.opacity(upcomingOpacity(index: idx)))
                                // Wrap long lines onto the row below so the
                                // whole line is readable (user-mandated);
                                // still tail-truncates past the budget.
                                .lineLimit(spec.upcomingLines)
                                .lineSpacing(1)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .id(currentLine)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            .frame(height: spec.boxHeight, alignment: .topLeading)
            .clipped()
            .padding(.top, 6)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: currentLine)
        }
    }

    private var displayUpcomingLines: [String] {
        if !upcomingLines.isEmpty {
            return upcomingLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if let nextLine, !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
            return [nextLine]
        }
        return []
    }

    private func upcomingOpacity(index: Int) -> Double {
        let isPaused = (status == .paused)
        switch index {
        case 0: return isPaused ? 0.45 : 0.65
        case 1: return isPaused ? 0.28 : 0.42
        default: return isPaused ? 0.16 : 0.24
        }
    }

    // MARK: - Progress bar (3px capsule)

    private var progressRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.trackBackground)
                Capsule().fill(colors.trackFill)
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 3)
        .padding(.top, 8)
        .opacity(status == .loading ? 0.4 : 1)
    }

    // MARK: - Large-widget bottom row: cover | title/artist | transport

    private var bottomBar: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? "Live Lyrics" : title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.titleText)
                    .lineLimit(1)
                Text(artist.isEmpty ? status.badge ?? " " : artist)
                    .font(.system(size: 11.5))
                    .foregroundColor(colors.artistText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            transportButtons
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let data = artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    colors.trackBackground
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.metaText)
                }
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var transportButtons: some View {
        HStack(spacing: 6) {
            widgetIntentButton("backward.fill", intent: RewindIntent(), label: "Previous song", size: 16)
            widgetIntentButton(isPlaying ? "pause.fill" : "play.fill",
                               intent: PausePlayIntent(),
                               label: isPlaying ? "Pause" : "Play", size: 19)
            widgetIntentButton("forward.fill", intent: SkipIntent(), label: "Next song", size: 16)
        }
        .foregroundColor(colors.heroText)
    }

    private func widgetIntentButton<I: AppIntent>(_ name: String, intent: I,
                                                  label: String, size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(colors.heroText)
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Tiny shared bits

    private func skeleton(widthFraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(colors.trackBackground)
            .frame(height: 15)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(colors.trackFill.opacity(0.55))
                        .frame(width: geo.size.width * widthFraction)
                }
            }
    }

    private func musicNoteGlyph(size: CGFloat) -> some View {
        Image(systemName: "music.note")
            .font(.system(size: size))
            .foregroundColor(colors.nextText)
            .frame(width: size + 2, height: size + 2)
    }

    private func pauseGlyph(size: CGFloat) -> some View {
        HStack(spacing: 2) {
            Rectangle().frame(width: size * 0.4, height: size)
            Rectangle().frame(width: size * 0.4, height: size)
        }
        .foregroundColor(colors.badgeText)
    }
}
