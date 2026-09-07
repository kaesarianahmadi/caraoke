import SwiftUI
import WidgetKit

// MARK: - Shared lyric layout (design: design/screens/live-activity.html)

/// One view, every surface. Renders the "Night Podium" dark-glass lyric tile
/// with static fixed-height lyric container (anti-flicker) and seamless widget styling.
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

    /// Locked Live Activity glass (Night Podium, dark only).
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
    let isCarPlaySmall: Bool
    let isHome: Bool
    let isWidget: Bool
    var palette: LyricTilePalette?

    @Environment(\.colorScheme) private var scheme

    private var colors: LyricTilePalette { palette ?? .activity }

    init(title: String, artist: String, currentLine: String, nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil, isCarPlaySmall: Bool = false,
         isHome: Bool = false, isWidget: Bool = false, palette: LyricTilePalette? = nil) {
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
        self.isCarPlaySmall = isCarPlaySmall
        self.isHome = isHome
        self.isWidget = isWidget
        self.palette = palette
    }

    var body: some View {
        lockBanner
    }

    // MARK: - Unified Banner Layout

    private var lockBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            lyricBody
            if status != .stale {
                progressRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isWidget ? 12 : 14)
        .background(
            Group {
                if !isWidget {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(colors.cardBackground)
                }
            }
        )
        .overlay(
            Group {
                if !isWidget {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(colors.cardBorder, lineWidth: 1)
                }
            }
        )
        .opacity(status == .stale ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
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

    // MARK: - Shared lyric body (Slide-up, anti-flicker, fixed container height)

    @ViewBuilder
    private var lyricBody: some View {
        let fontSize16: CGFloat = 16.0
        let containerHeight: CGFloat = 118.0

        switch status {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                skeleton(widthFraction: 0.90)
                skeleton(widthFraction: 0.70)
                skeleton(widthFraction: 0.50)
            }
            .frame(height: containerHeight, alignment: .topLeading)
            .padding(.top, 6)
        case .noLyrics:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    musicNoteGlyph(size: 16)
                    Text(currentLine.isEmpty ? title : currentLine)
                        .font(.system(size: fontSize16, weight: .bold))
                        .foregroundColor(colors.heroText)
                        .lineLimit(1)
                }
                Text("No lyrics found for this song")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(height: containerHeight, alignment: .topLeading)
            .padding(.top, 6)
        case .stale:
            VStack(alignment: .leading, spacing: 6) {
                Text(currentLine.isEmpty ? "Ride ended" : currentLine)
                    .font(.system(size: fontSize16, weight: .bold))
                    .foregroundColor(colors.heroText)
                    .opacity(0.32)
                    .lineLimit(1)
                Text("Lyrics return when a song plays")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(height: containerHeight, alignment: .topLeading)
            .padding(.top, 6)
        default:
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    // Line 1: Current line (Bold 16pt, 100% opacity)
                    Text(currentLine.isEmpty ? (title.isEmpty ? "Play a song to see lyrics" : title) : currentLine)
                        .font(.system(size: fontSize16, weight: .bold))
                        .foregroundColor(colors.heroText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)

                    // Lines 2-4: Upcoming lyrics (Medium 16pt, descending opacity for karaoke sing-along)
                    if status != .idle {
                        let linesToShow = displayUpcomingLines
                        ForEach(Array(linesToShow.prefix(3).enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: fontSize16, weight: .medium))
                                .foregroundColor(colors.nextText.opacity(upcomingOpacity(index: idx)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
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
            .frame(height: containerHeight, alignment: .topLeading)
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

    // MARK: - Progress bar (3px capsule only)

    private var progressRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.trackBackground)
                Capsule().fill(colors.trackFill)
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 3)
        .padding(.top, 10)
        .opacity(status == .loading ? 0.4 : 1)
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
