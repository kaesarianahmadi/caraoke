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
    /// Shows the header only while the song has not reached its first lyric yet
    /// (the 4x4 widget's intro). Distinct from `showsCarPlayIntroHeader`, which
    /// is a CarPlay-only rule with the opposite intent — see `showsIdentityHeader`.
    var showsHeaderOnIntro: Bool = false
    /// Fades the outermost lyric rows into the background instead of cutting
    /// them off at the frame edge.
    var edgeFade: Bool = false
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
    /// Size lyrics render at on this surface. Comes from `LyricSurface`, so it
    /// is the same number the budget math uses. Text is NEVER scaled below it.
    var font: CGFloat = LyricType.lyric
    /// Gap between two lyric rows on this surface. The default is the shared
    /// scale's; the 4x4 widget opens it up because it is the one surface with
    /// height to spare (see `case .widgetLarge` in `layout`).
    var rowSpacing: CGFloat = LyricType.lyricRowSpacing
    /// Gap between wrapped lines of one lyric. Same default-and-override story
    /// as `rowSpacing`.
    var lineSpacing: CGFloat = LyricType.lyricLineSpacing
    /// Maximum width of the lyric column. Enforces a slim, compact column so
    /// long lines wrap into 2-3 short, punchy lines rather than stretching horizontally.
    var maxLyricWidth: CGFloat? = nil
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
        cardBackground: .black,
        cardBorder: Color.white.opacity(0.07),
        titleText: Color.white.opacity(0.96),
        artistText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.48),
        badgeText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.62),
        heroText: .white,
        nextText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.75),
        metaText: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.4),
        trackBackground: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.18),
        // White, not the brand orange: the progress fill belongs to the lyric
        // block, not to the accent.
        trackFill: .white.opacity(0.92),
        glow: .white.opacity(0.7)
    )
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
    /// Whether the progress bar should be shown (CarPlay Stack 2 / Stack 3 can disable).
    var showsProgressBar: Bool = true
    /// Custom container height override (e.g. for hybrid widget embedded tiles).
    var customBoxHeight: CGFloat? = nil
    var customFont: CGFloat? = nil
    var customPadding: CGFloat? = nil
    var customRowSpacing: CGFloat? = nil
    var customLineSpacing: CGFloat? = nil

    private var colors: LyricTilePalette { palette ?? .activity }

    private var layout: LyricTileLayout {
        // Row budgets and heights come from `LyricSurface` in CaraokeCore, so
        // the numbers this view renders and the numbers `Tests/main.swift`
        // asserts are literally the same values.
        switch surface {
        case .lockBanner:
            // Lock Screen banner: intro header before first lyric, then
            // lyric rows own the tile during playback.
            return LyricTileLayout(boxHeight: LyricSurface.lockBanner.blockHeight,
                                   showsHeader: false, showsHeaderOnIntro: true,
                                   edgeFade: true,
                                   padding: customPadding ?? 16,
                                   chromeHeight: LyricSurface.lockBanner.chromeHeight,
                                   rowSpacing: customRowSpacing ?? 5,
                                   lineSpacing: customLineSpacing ?? 1.5,
                                   maxLyricWidth: 250)
        case .carPlaySmall:
            // CarPlay Stack / Dashboard mirror. Slim 135 pt column forces
            // long lines to wrap into 2-3 short, punchy lines without stretching.
            let isTextOnly = !showsProgressBar
            let defaultPadding: CGFloat = isTextOnly ? 8 : 8
            return LyricTileLayout(boxHeight: isTextOnly ? nil : (customBoxHeight ?? LyricSurface.carPlaySmall.blockHeight),
                                   maxBoxHeight: isTextOnly ? nil : (customBoxHeight ?? LyricSurface.carPlaySmall.blockHeight),
                                   headerCompact: true,
                                   edgeFade: true,
                                   padding: customPadding ?? defaultPadding,
                                   chromeHeight: LyricSurface.carPlaySmall.chromeHeight,
                                   font: customFont ?? LyricSurface.carPlaySmall.lyricFont,
                                   rowSpacing: customRowSpacing ?? 5,
                                   lineSpacing: customLineSpacing ?? 1.5,
                                   maxLyricWidth: 135)
        case .widgetSmall:
            // Apple's 158×158 grid. Slim 130 pt column wraps lines naturally.
            return LyricTileLayout(boxHeight: LyricSurface.widgetSmall.blockHeight,
                                   headerCompact: true,
                                   edgeFade: true,
                                   padding: customPadding ?? 10,
                                   chromeHeight: LyricSurface.widgetSmall.chromeHeight,
                                   rowSpacing: customRowSpacing ?? 4,
                                   lineSpacing: customLineSpacing ?? 1.5,
                                   maxLyricWidth: 130)
        case .widgetMedium:
            // 338×158: the vinyl/cover takes the right half, lyrics the left.
            return LyricTileLayout(boxHeight: LyricSurface.widgetMedium.blockHeight,
                                   headerCompact: true,
                                   edgeFade: true,
                                   padding: customPadding ?? 12,
                                   chromeHeight: LyricSurface.widgetMedium.chromeHeight,
                                   rowSpacing: customRowSpacing ?? 5,
                                   lineSpacing: customLineSpacing ?? 1.5,
                                   maxLyricWidth: 135)
        case .widgetLarge:
            // 4x4 grid. Slim 225 pt centered column leaves 80+ pt breathing room
            // for the bottom player bar and card corners.
            return LyricTileLayout(
                boxHeight: nil, maxBoxHeight: 240,
                showsHeader: false, showsHeaderOnIntro: true,
                edgeFade: true, showsBottomBar: true,
                centersVertically: true,
                padding: customPadding ?? 16,
                chromeHeight: LyricSurface.widgetLarge.chromeHeight,
                font: LyricSurface.widgetLarge.lyricFont,
                rowSpacing: customRowSpacing ?? 6,
                lineSpacing: customLineSpacing ?? 2,
                maxLyricWidth: 225)
        case .home:
            // The in-app player card — the Live Activity's in-app twin.
            return LyricTileLayout(
                boxHeight: LyricSurface.home.blockHeight,
                headerCompact: true,
                edgeFade: true,
                centersVertically: true,
                padding: customPadding ?? 14,
                chromeHeight: LyricSurface.home.chromeHeight,
                rowSpacing: customRowSpacing ?? 5,
                lineSpacing: customLineSpacing ?? 1.5,
                maxLyricWidth: 250)
        }
    }

    /// The tile shows a progress bar unless disabled or in a terminal state —
    /// there is no live position to report in either.
    private var showsProgress: Bool { showsProgressBar && status != .stale && status != .expired }

    init(title: String, artist: String, currentLine: String,
         previousLines: [String] = [],
         nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil,
         surface: Surface, palette: LyricTilePalette? = nil, artworkData: Data? = nil,
         resyncPulse: Double = 1, needsResync: Bool = false,
         showsProgressBar: Bool = true, customBoxHeight: CGFloat? = nil,
         customFont: CGFloat? = nil, customPadding: CGFloat? = nil,
         customRowSpacing: CGFloat? = nil, customLineSpacing: CGFloat? = nil) {
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
        self.showsProgressBar = showsProgressBar
        self.customBoxHeight = customBoxHeight
        self.customFont = customFont
        self.customPadding = customPadding
        self.customRowSpacing = customRowSpacing
        self.customLineSpacing = customLineSpacing
    }

    var body: some View {
        let spec = layout
        VStack(alignment: .leading, spacing: 0) {
            if showsIdentityHeader(spec: spec) {
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
        .background(cardShape(enabled: true))
        .overlay(cardStroke(enabled: true))
        .opacity(status == .stale ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }

    /// CarPlay's identity row is conditional, every other surface always shows
    /// it. On the dashboard tile the title and artist are an INTRO: they hold
    /// the tile from the moment the song starts until its first lyric line
    /// arrives, then give up the row so the lyrics own the whole tile and the
    /// active line stays centred. (User direction, build 46 — the identity was
    /// previously pinned at the top for the entire song.)
    private var showsCarPlayIntroHeader: Bool {
        surface != .carPlaySmall || currentLine.isEmpty
    }

    /// Whether the identity row renders at all.
    ///
    /// - CarPlay: always, except once real lyrics are on screen.
    /// - 4x4 widget: only during the intro, and that is a different motive than
    ///   CarPlay's. With no lyric playing the tile would otherwise open on its
    ///   title set as a 20 pt lyric (`rows(spec:budget:)` falls back to
    ///   "Title — Artist"), which is a big centred block of text with no
    ///   identity above it. User direction (build 54): show the song's title and
    ///   artist as a proper header while the song has not started, then hand the
    ///   tile to the lyrics the moment the first line lands. The bottom bar
    ///   keeps the compact identity either way, exactly as on other widgets.
    private func showsIdentityHeader(spec: LyricTileLayout) -> Bool {
        if spec.showsHeaderOnIntro { return currentLine.isEmpty }
        return spec.showsHeader && showsCarPlayIntroHeader
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

    /// Whether this render is the 4x4 widget's intro — true only while the
    /// header is on screen for the intro reason, so the header can pick the
    /// larger title/artist stack without the CarPlay path changing shape.
    private var showsLargeIntroHeader: Bool {
        layout.showsHeaderOnIntro && currentLine.isEmpty
    }

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if showsLargeIntroHeader {
            // 4x4 widget, before the first lyric: the identity is the whole
            // point of the row, so it gets its own stack at a larger size than
            // the compact one-liner other surfaces use.
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Live Lyrics" : title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.titleText)
                    .lineLimit(1)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundColor(colors.artistText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if compact {
            // Small/medium widget: one identity row, badge right — the height
            // the lyric block needs back comes from here.
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
            // Every text row in the tile renders at the surface's own lyric
            // size — build 40 shrank these stand-ins to 13, which is the same
            // inconsistency the lyric rows had.
            boxed(VStack(alignment: .center, spacing: LyricType.lyricRowSpacing) {
                HStack(spacing: 6) {
                    musicNoteGlyph(size: spec.font)
                    Text(currentLine.isEmpty ? title : currentLine)
                        .font(LyricType.font(size: spec.font, weight: LyricType.lyricHeroWeight))
                        .foregroundColor(colors.heroText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("No lyrics found for this song")
                    .font(LyricType.font(size: spec.font))
                    .foregroundColor(colors.metaText)
                    .multilineTextAlignment(.center)
            }, spec: spec, alignment: .center)
        case .stale:
            boxed(VStack(alignment: .center, spacing: LyricType.lyricRowSpacing) {
                Text(currentLine.isEmpty ? "Ride ended" : currentLine)
                    .font(LyricType.font(size: spec.font, weight: LyricType.lyricHeroWeight))
                    .foregroundColor(colors.heroText)
                    .opacity(0.32)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Lyrics return when a song plays")
                    .font(LyricType.font(size: spec.font))
                    .foregroundColor(colors.metaText)
                    .multilineTextAlignment(.center)
            }, spec: spec, alignment: .center)
        case .expired:
            // The payload outlived the song it describes — the app stopped
            // reloading and the baked timeline is spent. Saying so beats
            // freezing on a line that is no longer playing: the user gets a
            // signal and a way out instead of assuming the app is broken. The
            // cover is the resync button (`ResyncWidgetIntent`), which is what
            // `needsResync` already lights up.
            boxed(VStack(alignment: .center, spacing: LyricType.lyricRowSpacing) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: spec.font, weight: .bold))
                        .foregroundColor(colors.heroText)
                    Text("Out of date")
                        .font(LyricType.font(size: spec.font, weight: LyricType.lyricHeroWeight))
                        .foregroundColor(colors.heroText)
                        .lineLimit(1)
                }
                Text("Tap the cover to resync")
                    .font(LyricType.font(size: spec.font))
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
    ///
    /// Build 42: lock banner uses `minHeight:` (floor = boxHeight) so the tile
    /// never shrinks below its nominal size, fixing the "active line in first
    /// row instead of middle" defect. `maxHeight:` is removed for the lock
    /// banner too — the ceiling was letting the block collapse.
    @ViewBuilder
    private func boxed<V: View>(_ content: V, spec: LyricTileLayout, alignment: Alignment) -> some View {
        let boxH = customBoxHeight ?? spec.boxHeight
        // Build 54 — the 4x4 widget's edge fade. Text that runs past the block
        // dissolves into the background instead of stopping on a hard cut, which
        // is what the competitor's widget does and what the user asked for.
        // Applied to the BOX, not to a single state: it masks whatever the block
        // is rendering, so the skeleton and the no-lyrics placeholder fade the
        // same way and the tile does not change its edge treatment on a state
        // change.
        Group {
            if (surface == .lockBanner || surface == .carPlaySmall || surface == .home), let h = boxH {
                // Strict fixed height: never shrinks when lines drop to 2, never
                // expands when lines wrap. Prevents container jump across all surfaces.
                content.frame(maxWidth: .infinity,
                              minHeight: h,
                              maxHeight: h,
                              alignment: alignment)
            } else {
                content.frame(maxWidth: .infinity,
                              maxHeight: boxH ?? spec.maxBoxHeight ?? .infinity,
                              alignment: alignment)
            }
        }
        .lyricEdgeFade(active: spec.edgeFade)
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
        func uniqueID(_ text: String) -> String {
            let count = seen[text, default: 0]
            seen[text] = count + 1
            return count == 0 ? text : "\(text)#\(count)"
        }
        let hero: String
        if !currentLine.isEmpty {
            hero = currentLine
        } else if surface == .carPlaySmall || surface == .lockBanner || layout.showsHeaderOnIntro {
            // CarPlay, Lock Screen, and 4x4 intro: identity header shows title & artist,
            // so hero stays empty and opening lyrics preview underneath.
            hero = ""
        } else if !previousLines.isEmpty && isPlaying {
            // Outro transition: current line cleared so previous line rolls off
            hero = ""
        } else if !title.isEmpty {
            hero = artist.isEmpty ? title : "\(title) — \(artist)"
        } else {
            hero = "Play a song to see lyrics"
        }

        // Dynamic eviction removed: with edge fade active on all surfaces,
        // lines dissolve softly at vertical boundaries without character-count eviction.
        let evictUpcoming = false
        let evictPrevious = false

        let hasPreviousLines = !previousLines.isEmpty && status != .idle
        let showPrevious = hasPreviousLines && budget.previousShown > 0
        let isIntro = hero.isEmpty && !displayUpcomingLines.isEmpty && status == .playing
        let showUpcoming = (showPrevious || isIntro || !hasPreviousLines) && status != .idle
            && (budget.upcomingShown > 0 || isIntro)

        var rows: [LyricRow] = []
        if showPrevious {
            for (idx, line) in previousLines.suffix(budget.previousShown).enumerated() {
                rows.append(LyricRow(id: uniqueID(line), text: line,
                                     kind: .previous, opacity: fade(previousIndex: idx)))
            }
        }
        if !hero.isEmpty {
            rows.append(LyricRow(id: uniqueID(hero), text: hero, kind: .hero, opacity: 1))
        }
        if showUpcoming {
            let upcomingCount = isIntro ? max(budget.upcomingShown, 3) : max(budget.upcomingShown, 2)
            for (idx, line) in displayUpcomingLines.prefix(upcomingCount).enumerated() {
                rows.append(LyricRow(id: uniqueID(line), text: line,
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
        VStack(alignment: .center, spacing: customRowSpacing ?? spec.rowSpacing) {
            ForEach(items) { row in
                rowView(row, budget: budget, spec: spec)
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

    /// Active line: emphasis by weight, never by size. Build 40 used `.bold` in
    /// San Francisco and read as too heavy in that context; the face and weight
    /// have since been settled by the rendered comparison in
    /// `design/font-comparison.html`, which the user chose SF Pro bold from.
    /// The weight itself lives in `LyricType`, not here.
    ///
    /// Build 46 — the no-truncation rule. `minimumScaleFactor` is GONE from
    /// every row (it was the "fonts are too big, then shrink randomly" defect:
    /// the size changed per line depending on how long the line was), and so
    /// is `.truncationMode(.tail)`. A line that does not fit across the tile
    /// now carries onto the row below it, at the same size, for as many rows as
    /// the surface's budget allows.
    @ViewBuilder
    private func rowView(_ row: LyricRow, budget: LyricRowBudget, spec: LyricTileLayout) -> some View {
        let weight: Font.Weight = row.kind == .hero ? LyricType.lyricHeroWeight : LyricType.lyricNeighborWeight
        // Eliminate truncation: hero wraps up to 5 lines, neighbors up to 3 lines.
        let allowance = row.kind == .hero ? max(budget.heroRows, 5) : max(budget.neighborRows, 3)
        Text(row.text)
            .font(LyricType.font(size: spec.font, weight: weight))
            .foregroundColor(row.kind == .hero ? colors.heroText : colors.nextText.opacity(row.opacity))
            .multilineTextAlignment(.center)
            .lineLimit(allowance)
            .lineSpacing(customLineSpacing ?? spec.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: spec.maxLyricWidth ?? .infinity, alignment: .center)
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
        max(0.38, 0.70 - Double(previousIndex) * 0.16)
    }

    private func upcomingOpacity(index: Int) -> Double {
        let isPaused = (status == .paused)
        let base: Double
        switch index {
        case 0: base = 0.82
        case 1: base = 0.62
        case 2: base = 0.50
        case 3: base = 0.42
        default: base = 0.36
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

// MARK: - Edge fade

/// Vertical gradient used as a mask over the lyric block: opaque through the
/// middle, transparent at the very top and bottom, so the outermost lines
/// dissolve into the background instead of ending on a hard cut.
///
/// Ratios, not point values: the fade has to hold on the 4x4 widget and on a
/// wide Live Activity without a per-surface constant. The plateau keeps the
/// active line and its neighbours at full opacity; only the outermost ~5% of
/// each edge is touched.
///
/// `active: false` applies no mask at all, which is what lets the shared
/// `boxed(_:spec:alignment:)` path call this unconditionally without changing
/// any other surface's rendering.
struct LyricEdgeFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            content
        }
    }
}

extension View {
    func lyricEdgeFade(active: Bool) -> some View {
        modifier(LyricEdgeFade(active: active))
    }
}
