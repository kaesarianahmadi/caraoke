import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Shared lyric layout (design: design/screens/live-activity.html)

/// One view, every surface: Lock Screen Live Activity banner, CarPlay mirror,
/// the persistent Home Screen widgets, and the in-app player card.
/// Renders the dark karaoke lyric block with static anti-flicker container.

/// Layout capacity per surface. Every lyric row renders at `LyricType.lyric`
/// (18 pt) on every surface — there is no per-surface font override, because
/// that is exactly what made build 40's widgets inconsistent.
///
/// The row budgets come from `LyricSurface` in CaraokeCore (one table, also
/// asserted by `Tests/main.swift`). The tile tries them richest-first and
/// renders the most generous set that fits, so a cramped surface shows fewer
/// lines instead of smaller ones.
struct LyricTileLayout {
    /// Fixed anti-flicker box height for surfaces that cannot reflow (Lock
    /// Screen banner, CarPlay, the in-app card). nil = size to content.
    var boxHeight: CGFloat? = 108
    /// Ceiling for content-sized surfaces (the large widget).
    var maxBoxHeight: CGFloat? = nil

    var headerCompact: Bool = false // one identity row instead of title+artist stack
    var showsHeader: Bool = true
    var showsBottomBar: Bool = false // large-widget cover/title/transport row
    /// Centres the lyric block and the whole stack in the surface. Every
    /// surface sets this now: build 40 pinned lyrics to the top for all but
    /// the large widget, which is the "placement is too high / not using the
    /// space" defect.
    var centersVertically: Bool = true
    var padding: CGFloat = 16
    /// Height the surface reserves for everything that is not the lyric block:
    /// padding, the header row, the progress bar, the large widget's player bar.
    var chromeHeight: CGFloat = 0
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
        // White, not the brand orange: the progress fill belongs to the lyric
        // block, not to the accent.
        trackFill: .white.opacity(0.92),
        glow: .white.opacity(0.7)
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
    let previousLines: [String]
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

        /// Which entry of the shared budget table drives this surface.
        var profile: LyricSurface {
            switch self {
            case .lockBanner: return .lockBanner
            case .carPlaySmall: return .carPlaySmall
            case .widgetSmall: return .widgetSmall
            case .widgetMedium: return .widgetMedium
            case .widgetLarge: return .widgetLarge
            case .home: return .home
            }
        }
    }
    let surface: Surface
    var palette: LyricTilePalette?
    var artworkData: Data? = nil
    /// Cover opacity for this render (widgets pulse it during a resync).
    var resyncPulse: Double = 1
    /// Shows the refresh glyph over the cover when the lyrics are out of sync.
    var needsResync: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var colors: LyricTilePalette { palette ?? .activity }

    private var layout: LyricTileLayout {
        // Row budgets and heights come from `LyricSurface` in CaraokeCore, so
        // the numbers this view renders and the numbers `Tests/main.swift`
        // asserts are literally the same values.
        switch surface {
        case .lockBanner:
            // Apple's Lock Screen banner is ~160 pt and the content sits in the
            // system's own gloss card inset, so the tile gets ~145 pt. Build 40
            // asked for a 100 pt block and pinned it to the top: two lines high
            // with dead space underneath.
            return LyricTileLayout(boxHeight: LyricSurface.lockBanner.blockHeight,
                                   headerCompact: true, padding: 12,
                                   chromeHeight: LyricSurface.lockBanner.chromeHeight)
        case .carPlaySmall:
            return LyricTileLayout(boxHeight: LyricSurface.carPlaySmall.blockHeight,
                                   headerCompact: true, padding: 12,
                                   chromeHeight: LyricSurface.carPlaySmall.chromeHeight)
        case .widgetSmall:
            // Apple's 158×158 grid, also the StandBy/CarPlay tile (the system
            // scales this up). One identity row, then hero (2 wrapped rows) plus
            // two following lines — the "three or four lines" the user asked
            // for. Build 40 gave this surface 96 pt for a 3-row hero + 2 lines
            // and clipped the overflow.
            return LyricTileLayout(boxHeight: LyricSurface.widgetSmall.blockHeight,
                                   headerCompact: true, padding: 14,
                                   chromeHeight: LyricSurface.widgetSmall.chromeHeight)
        case .widgetMedium:
            // 338×158: the vinyl/cover takes the right half, lyrics the left.
            return LyricTileLayout(boxHeight: LyricSurface.widgetMedium.blockHeight,
                                   headerCompact: true, padding: 14,
                                   chromeHeight: LyricSurface.widgetMedium.chromeHeight)
        case .widgetLarge:
            // 4x4 grid. Lyrics own the top, identity + transport move to the
            // bottom row, so there is no header here. Build 40 asked for a
            // 3-row hero plus 6 neighbours (≈450 pt) against a 250 pt ceiling,
            // then clipped whatever did not fit.
            return LyricTileLayout(
                boxHeight: nil, maxBoxHeight: 262,
                showsHeader: false, showsBottomBar: true,
                centersVertically: true, padding: 16,
                chromeHeight: LyricSurface.widgetLarge.chromeHeight)
        case .home:
            // The in-app player card. Same 18 pt type as everything else; the
            // block is wide enough for 4 rows of lyrics.
            return LyricTileLayout(
                boxHeight: LyricSurface.home.blockHeight,
                centersVertically: true, padding: 16,
                chromeHeight: LyricSurface.home.chromeHeight)
        }
    }

    /// The tile always shows a progress bar except in the terminal stale
    /// state. `LyricTileLayout.chromeHeight` is measured with it included, so
    /// a surface that hides it simply gains headroom.
    private var showsProgress: Bool { status != .stale }

    init(title: String, artist: String, currentLine: String,
         previousLines: [String] = [],
         nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil,
         surface: Surface, palette: LyricTilePalette? = nil, artworkData: Data? = nil,
         resyncPulse: Double = 1, needsResync: Bool = false) {
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.previousLines = previousLines
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
        self.resyncPulse = resyncPulse
        self.needsResync = needsResync
    }

    var body: some View {
        let spec = layout
        VStack(alignment: .leading, spacing: 0) {
            if spec.showsHeader {
                header(compact: spec.headerCompact)
            }
            lyricBody(spec: spec)
            if showsProgress {
                progressRow
            }
            if spec.showsBottomBar {
                bottomBar
            }
        }
        // Vertical centring is the fix for build 40's "placement is too high,
        // not using the space": every surface centres its lyric block now, so
        // three or four lines sit in the middle of the tile instead of clinging
        // to the top edge above dead space.
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: spec.centersVertically ? .center : .topLeading)
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
            // Small/medium widget: one identity row, badge right — the height
            // the 18pt lyric block needs back comes from here.
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

    // MARK: - Lyric block (18pt throughout; long lines WRAP to 3 rows so the
    // whole line stays readable instead of running off a "…")

    @ViewBuilder
    private func lyricBody(spec: LyricTileLayout) -> some View {
        switch status {
        case .loading:
            boxed(VStack(alignment: .center, spacing: 8) {
                skeleton(widthFraction: 0.90)
                skeleton(widthFraction: 0.70)
                skeleton(widthFraction: 0.50)
            }, spec: spec, alignment: .center)
        case .noLyrics:
            // Every text row in the tile is 18 pt, including these stand-ins —
            // build 40 shrank them to 13, which is the same inconsistency the
            // lyric rows had.
            boxed(VStack(alignment: .center, spacing: LyricType.lyricRowSpacing) {
                HStack(spacing: 6) {
                    musicNoteGlyph(size: LyricType.lyric)
                    Text(currentLine.isEmpty ? title : currentLine)
                        .font(.system(size: LyricType.lyric, weight: LyricType.lyricWeight))
                        .foregroundColor(colors.heroText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("No lyrics found for this song")
                    .font(.system(size: LyricType.lyric))
                    .foregroundColor(colors.metaText)
                    .multilineTextAlignment(.center)
            }, spec: spec, alignment: .center)
        case .stale:
            boxed(VStack(alignment: .center, spacing: LyricType.lyricRowSpacing) {
                Text(currentLine.isEmpty ? "Ride ended" : currentLine)
                    .font(.system(size: LyricType.lyric, weight: LyricType.lyricWeight))
                    .foregroundColor(colors.heroText)
                    .opacity(0.32)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Lyrics return when a song plays")
                    .font(.system(size: LyricType.lyric))
                    .foregroundColor(colors.metaText)
                    .multilineTextAlignment(.center)
            }, spec: spec, alignment: .center)
        default:
            boxed(lyricRows(spec: spec), spec: spec,
                  alignment: spec.centersVertically ? .center : .top)
        }
    }

    /// Fixed anti-flicker box where the surface cannot reflow (Lock Screen
    /// banner, CarPlay, the in-app card); content-sized where it can (the large
    /// widget).
    ///
    /// Deliberately NOT `.clipped()`: clipping is what hid build 40's overflow
    /// behind a cut-off line. The `ViewThatFits` ladder inside `lyricRows`
    /// picks a row set that fits, so anything reaching here already has room;
    /// a non-lyric state that still overruns is allowed to scale its own
    /// container rather than be silently amputated.
    /// Uses `maxHeight:` in BOTH cases rather than `height:`. The two-branch
    /// `if let` version that build 40 shipped failed to type-check on the iOS
    /// SDK once the branches diverged ("extra argument 'height'"), and the
    /// `height:` overload is iOS-only so it cannot be verified off-device.
    /// Passing nil means unbounded, which is exactly the large widget's
    /// content-sized case.
    private func boxed<V: View>(_ content: V, spec: LyricTileLayout, alignment: Alignment) -> some View {
        content.frame(maxWidth: .infinity,
                      maxHeight: spec.boxHeight ?? spec.maxBoxHeight ?? .infinity,
                      alignment: alignment)
    }

    /// One lyric row with a stable identity. Rows that survive a line change
    /// keep their view, so they slide up one slot while the outgoing row
    /// leaves through the top and the new one arrives from the bottom — the
    /// whole block never moves as a single unit.
    private struct LyricRow: Identifiable {
        enum Kind { case previous, hero, upcoming }
        let id: String
        let text: String
        let kind: Kind
        let opacity: Double
    }

    private func rows(spec: LyricTileLayout, budget: LyricRowBudget) -> [LyricRow] {
        var seen: [String: Int] = [:]
        func uniqueID(_ kind: String, _ text: String) -> String {
            let key = kind + "\u{1}" + text
            let count = seen[key, default: 0]
            seen[key] = count + 1
            return count == 0 ? "\(kind):\(text)" : "\(kind):\(text)#\(count)"
        }
        var rows: [LyricRow] = []
        if status != .idle {
            for (idx, line) in previousLines.suffix(budget.previousShown).enumerated() {
                rows.append(LyricRow(id: uniqueID("p", line), text: line,
                                     kind: .previous, opacity: fade(previousIndex: idx)))
            }
        }
        let hero = currentLine.isEmpty ? (title.isEmpty ? "Play a song to see lyrics" : title) : currentLine
        rows.append(LyricRow(id: uniqueID("h", hero), text: hero, kind: .hero, opacity: 1))
        if status != .idle {
            for (idx, line) in displayUpcomingLines.prefix(budget.upcomingShown).enumerated() {
                rows.append(LyricRow(id: uniqueID("u", line), text: line,
                                     kind: .upcoming, opacity: upcomingOpacity(index: idx)))
            }
        }
        return rows
    }

    /// The fit ladder. Richest row set first; `ViewThatFits` walks down to the
    /// first one that actually fits the surface. This is what replaced
    /// `minimumScaleFactor`: when space runs out the tile shows fewer lines at
    /// the SAME 18 pt, instead of squeezing four lines into a smaller font.
    @ViewBuilder
    private func lyricRows(spec: LyricTileLayout) -> some View {
        let budgets = surface.profile.budgets
        ViewThatFits(in: .vertical) {
            ForEach(Array(budgets.enumerated()), id: \.offset) { _, budget in
                rowsStack(spec: spec, budget: budget)
            }
        }
    }

    @ViewBuilder
    private func rowsStack(spec: LyricTileLayout, budget: LyricRowBudget) -> some View {
        let items = rows(spec: spec, budget: budget)
        VStack(alignment: .center, spacing: budget.rowSpacing) {
            ForEach(items) { row in
                rowView(row, budget: budget)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        // Fills the box and centres inside it: the box is now a ceiling rather
        // than an exact height, so without this the stack would shrink to its
        // content and the progress bar underneath would jump on every line.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.32), value: items.map(\.id))
    }

    /// Active line: 18 pt `.semibold` — emphasis by weight only. Build 40 used
    /// `.bold` and the user read it as too heavy. It still has to be visibly
    /// bolder than the dimmed neighbours, which `.semibold` is.
    @ViewBuilder
    private func rowView(_ row: LyricRow, budget: LyricRowBudget) -> some View {
        let weight: Font.Weight = row.kind == .hero ? LyricType.lyricWeight : LyricType.lyricNeighborWeight
        let allowance = row.kind == .hero ? budget.heroRows : budget.neighborRows
        Text(row.text)
            .font(.system(size: budget.font, weight: weight))
            .foregroundColor(row.kind == .hero ? colors.heroText : colors.nextText.opacity(row.opacity))
            .multilineTextAlignment(.center)
            // Wrap to the budget, then truncate. Never shrink.
            .lineLimit(allowance)
            .lineSpacing(budget.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
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

    private func fade(previousIndex: Int) -> Double {
        max(0.18, 0.5 - Double(previousIndex) * 0.16)
    }

    private func upcomingOpacity(index: Int) -> Double {
        let isPaused = (status == .paused)
        let base: Double
        switch index {
        case 0: base = 0.62
        case 1: base = 0.42
        case 2: base = 0.30
        case 3: base = 0.22
        default: base = 0.16
        }
        return isPaused ? base * 0.7 : base
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
        .padding(.top, 6)
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

    /// Rounded-square cover (user direction: the huge square widget's mark was
    /// circular; it should match the app's rounded-square icon).
    @ViewBuilder
    private var artwork: some View {
        Button(intent: ResyncWidgetIntent()) {
            Group {
                if let data = artworkData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black)
                        Circle().stroke(Color.white.opacity(0.25), lineWidth: 1).frame(width: 22, height: 22)
                        Circle().fill(colors.glow).frame(width: 9, height: 9)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1))
            .overlay {
                if needsResync {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            // The pulse is timeline-driven: WidgetKit has no animation.
            .opacity(resyncPulse)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resync lyrics")
    }

    private var transportButtons: some View {
        HStack(spacing: 6) {
            widgetIntentButton("backward.fill", intent: PreviousTrackIntent(), label: "Previous song", size: 16)
            widgetIntentButton(isPlaying ? "pause.fill" : "play.fill",
                               intent: PlayPauseIntent(),
                               label: isPlaying ? "Pause" : "Play", size: 19)
            widgetIntentButton("forward.fill", intent: NextTrackIntent(), label: "Next song", size: 16)
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
