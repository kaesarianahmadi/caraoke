import SwiftUI
import WidgetKit

// MARK: - Shared lyric layout (design: design/screens/live-activity.html)

/// One view, every surface. Renders the "Night Podium" dark-glass lyric tile
/// without transport controls or timestamp numbers (per user direction).
///
/// - **Lock Screen banner** (`.la-card`): header (title/artist + status text),
///   hero line + next line with smooth slide-down animation, 3 px progress bar.
/// - **CarPlay small** (`.cp-tile`, read-only): hero line (up to 3 lines) + next line,
///   with 3 px progress bar — no transport, no numbers.
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
    let isPlaying: Bool
    let progress: Double
    let status: LyricStatus
    let positionMs: Int
    let durationMs: Int?
    let isCarPlaySmall: Bool
    let isHome: Bool
    var palette: LyricTilePalette?

    @Environment(\.colorScheme) private var scheme

    private var colors: LyricTilePalette { palette ?? .activity }

    init(title: String, artist: String, currentLine: String, nextLine: String?,
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil, isCarPlaySmall: Bool = false,
         isHome: Bool = false, palette: LyricTilePalette? = nil) {
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.nextLine = nextLine
        self.isPlaying = isPlaying
        self.progress = progress
        self.status = status
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.isCarPlaySmall = isCarPlaySmall
        self.isHome = isHome
        self.palette = palette
    }

    public var body: some View {
        Group {
            if isCarPlaySmall {
                carPlayTile
            } else {
                lockBanner
            }
        }
    }

    // MARK: - Lock Screen banner

    private var lockBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            lyricBody(.banner)
            if status != .stale {
                progressRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(colors.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(colors.cardBorder, lineWidth: 1))
        .opacity(status == .stale ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "No Song Playing" : title)
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

    // MARK: - CarPlay small

    private var carPlayTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            lyricBody(.carPlay)
            if status != .stale {
                progressRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(colors.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(colors.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared lyric body

    private enum Family { case banner, carPlay }

    @ViewBuilder
    private func lyricBody(_ family: Family) -> some View {
        let heroSize: CGFloat = isHome ? 19 : (family == .banner ? 20 : 21)
        let nextSize: CGFloat = isHome ? 14.5 : (family == .banner ? 15 : 14)

        switch status {
        case .loading:
            VStack(alignment: .leading, spacing: 9) {
                skeleton(widthFraction: family == .banner ? 0.88 : 0.90)
                skeleton(widthFraction: family == .banner ? 0.60 : 0.64)
            }
            .frame(minHeight: 52, alignment: .top)
            .padding(.top, 10)
        case .noLyrics:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    musicNoteGlyph(size: family == .banner ? 16 : 15)
                    Text(currentLine.isEmpty ? title : currentLine)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(colors.heroText)
                        .lineLimit(2)
                }
                Text("No lyrics found for this song")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(minHeight: 52, alignment: .top)
            .padding(.top, 10)
        case .stale:
            VStack(alignment: .leading, spacing: 7) {
                Text(currentLine.isEmpty ? "Ride ended" : currentLine)
                    .font(.system(size: heroSize - 1, weight: .bold))
                    .foregroundColor(colors.heroText)
                    .opacity(0.32)
                    .lineLimit(3)
                Text(family == .banner
                     ? "Ride ended — lyrics return when a song plays."
                     : "Ride ended")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(minHeight: 52, alignment: .top)
            .padding(.top, 10)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(currentLine.isEmpty ? (title.isEmpty ? "Play a song to see lyrics" : title) : currentLine)
                    .font(.system(size: heroSize, weight: .bold))
                    .foregroundColor(colors.heroText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id("hero-\(currentLine)")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -8)),
                        removal: .opacity.combined(with: .offset(y: 8))
                    ))

                if let nextLine, !nextLine.isEmpty, status != .idle {
                    Text(nextLine)
                        .font(.system(size: nextSize, weight: .medium))
                        .foregroundColor(status == .paused
                                         ? colors.nextText.opacity(0.58)
                                         : colors.nextText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("next-\(nextLine)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -6)),
                            removal: .opacity.combined(with: .offset(y: 6))
                        ))
                }
            }
            .frame(minHeight: 52, alignment: .top)
            .padding(.top, 10)
            .animation(.easeInOut(duration: 0.35), value: currentLine)
        }
    }

    // MARK: - Progress bar (no timestamp numbers per user direction)

    private var progressRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.trackBackground)
                Capsule().fill(colors.trackFill)
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 3)
        .padding(.top, 12)
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
