import SwiftUI
import WidgetKit

// MARK: - Shared lyric layout (design: design/screens/live-activity.html)

/// One view, every surface. Renders the "Night Podium" dark-glass lyric tile
/// from the final OpenDesign spec:
///
/// - **Lock Screen banner** (`.la-card`): header (title/artist + status
///   badge), hero line + next line, transport row (rewind/play-pause/skip via
///   App Intents), 3 px progress + tabular times `1:24 / -1:28`.
/// - **CarPlay small** (`.cp-tile`, read-only): hero line + next line only,
///   with progress + times — no header, no transport. Non-interactive by
///   design; Apple renders CarPlay Live Activities that way.
///
/// One `status` drives the 5 design states (playing / paused / no lyrics /
/// loading / stale) plus the Ride-Mode placeholder (idle). The tile is ALWAYS
/// dark glass (`activityBackgroundTint .black 0.7`) — never light mode, never
/// flat black. No album art, no translations, no third lyric line.
// MARK: - Palette (one layout, two surfaces)

/// Color set for the tile. The Live Activity is always dark glass (locked);
/// the Home player card uses the same layout but follows the app palette so
/// light mode looks like design/screens/home.html `.la-card`.
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
    /// CarPlay small layout is more compact than the Lock Screen banner.
    let isCarPlaySmall: Bool
    /// Colors. Locked LA glass by default; `.home(scheme)` for the app's
    /// player card.
    @Environment(\.colorScheme) private var scheme
    var palette: LyricTilePalette?

    private var colors: LyricTilePalette { palette ?? .activity }

    init(title: String, artist: String, currentLine: String, nextLine: String?,
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil, isCarPlaySmall: Bool = false,
         palette: LyricTilePalette? = nil) {
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
        self.palette = palette
    }

    var body: some View {
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
            transport
            if status != .stale {
                progressRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(colors.titleText)
                    .lineLimit(1)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundColor(colors.artistText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let badge = status.badge {
                HStack(spacing: 6) {
                    if status == .playing {
                        Circle().fill(colors.glow).frame(width: 7, height: 7)
                    }
                    if status == .paused {
                        pauseGlyph(size: 10)
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

    // MARK: - Shared lyric body (family-adaptive fonts/clamps)

    private enum Family { case banner, carPlay }

    @ViewBuilder
    private func lyricBody(_ family: Family) -> some View {
        let heroSize: CGFloat = family == .banner ? 20 : 21
        let nextSize: CGFloat = family == .banner ? 15 : 14
        let heroClamp: Int = family == .banner ? 3 : 2

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
                        .font(.system(size: family == .banner ? 17 : 17, weight: .bold))
                        .foregroundColor(colors.heroText)
                        .lineLimit(1)
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
                    .lineLimit(heroClamp)
                Text(family == .banner
                     ? "Ride ended — lyrics return when a song plays."
                     : "Ride ended")
                    .font(.system(size: 13))
                    .foregroundColor(colors.metaText)
            }
            .frame(minHeight: 52, alignment: .top)
            .padding(.top, 10)
        default: // playing, paused, idle
            VStack(alignment: .leading, spacing: 6) {
                Text(currentLine.isEmpty ? (title.isEmpty ? "Play a song to see lyrics" : title) : currentLine)
                    .font(.system(size: heroSize, weight: .bold))
                    .foregroundColor(colors.heroText)
                    .lineLimit(heroClamp)
                    .minimumScaleFactor(0.7)
                if let nextLine, !nextLine.isEmpty, status != .idle {
                    Text(nextLine)
                        .font(.system(size: nextSize, weight: .medium))
                        .foregroundColor(status == .paused
                                         ? colors.nextText.opacity(0.58)
                                         : colors.nextText)
                        .lineLimit(family == .banner ? 2 : 1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minHeight: 52, alignment: .top)
            .padding(.top, 10)
        }
    }

    // MARK: - Progress + times row (design `.la-foot`)

    private var progressRow: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.trackBackground)
                    Capsule().fill(colors.trackFill)
                        .frame(width: max(3, geo.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 3)
            .opacity(status == .loading ? 0.4 : 1)

            if durationMs != nil || status != .idle {
                HStack {
                    Text(timeText(positionMs))
                    Spacer()
                    if let durationMs {
                        Text("-" + timeText(max(0, durationMs - positionMs)))
                    }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(colors.metaText)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Transport (Lock Screen banner only; App Intents)

    @ViewBuilder
    private var transport: some View {
        if !isCarPlaySmall && status != .stale && status != .idle {
            HStack(spacing: 22) {
                Button(intent: RewindIntent()) {
                    transportIcon("backward.fill")
                }
                Button(intent: PausePlayIntent()) {
                    transportIcon(isPlaying ? "pause.fill" : "play.fill")
                }
                Button(intent: SkipIntent()) {
                    transportIcon("forward.fill")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }

    private func transportIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16))
            .foregroundColor(colors.heroText)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
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
        HStack(spacing: 3) {
            Rectangle().frame(width: size * 0.45, height: size)
            Rectangle().frame(width: size * 0.45, height: size)
        }
        .foregroundColor(colors.badgeText)
    }

    private func timeText(_ ms: Int) -> String {
        let s = max(0, ms / 1000)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}