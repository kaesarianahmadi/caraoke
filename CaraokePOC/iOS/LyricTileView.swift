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
            // Lock Screen banner mirrors the in-app card layout and padding.
            return LyricTileLayout(boxHeight: LyricSurface.lockBanner.blockHeight,
                                   headerCompact: true, padding: 16,
                                   chromeHeight: LyricSurface.lockBanner.chromeHeight)
        case .carPlaySmall:
            // CarPlay Stack / Dashboard mirror. Default renders at 14 pt with 6 pt
            // padding; pure lyrics stack can pass customFont (16 pt) and customPadding (4 pt).
            return LyricTileLayout(boxHeight: LyricSurface.carPlaySmall.blockHeight,
                                   headerCompact: true,
                                   padding: customPadding ?? 6,
                                   chromeHeight: LyricSurface.carPlaySmall.chromeHeight,
                                   font: customFont ?? LyricSurface.carPlaySmall.lyricFont)
        case .widgetSmall:
            // Apple's 158×158 grid. Compact 6 pt padding gives lyrics max width.
            return LyricTileLayout(boxHeight: LyricSurface.widgetSmall.blockHeight,
                                   headerCompact: true, padding: 6,
                                   chromeHeight: LyricSurface.widgetSmall.chromeHeight)
        case .widgetMedium:
            // 338×158: the vinyl/cover takes the right half, lyrics the left.
            return LyricTileLayout(boxHeight: LyricSurface.widgetMedium.blockHeight,
                                   headerCompact: true, padding: 14,
                                   chromeHeight: LyricSurface.widgetMedium.chromeHeight)
        case .widgetLarge:
            // 4x4 grid. Lyrics own the block, identity + transport move to the
            // bottom row. Build 40 asked for a 3-row hero plus 6 neighbours
            // (≈450 pt) against a 262 pt ceiling, then clipped whatever did not
            // fit.
            //
            // Build 54, in one place:
            // - ceiling 262 → 300: the old number left roughly a third of the
            //   379 pt canvas as dead space under the block;
            // - the block gets a vertical edge fade;
            // - the identity shows as a header during the intro, before the
            //   first lyric line lands;
            // - both gaps open up — 4 pt inside a wrapped line, 10 pt between
            //   lines, against the shared scale's 2 and 6. This is the surface
            //   the user compared against the competitor, and it is the only one
            //   with height to spend: raising either gap on the shared scale
            //   pushed the small widget, Lock Screen and in-app card past their
            //   boxes, which `layoutFits_*` fails on;
            // - and it renders one size up, at `LyricType.widgetLargeLyric`.
            return LyricTileLayout(
                boxHeight: nil, maxBoxHeight: 300,
                showsHeader: false, showsHeaderOnIntro: true,
                edgeFade: true, showsBottomBar: true,
                centersVertically: true, padding: 16,
                chromeHeight: LyricSurface.widgetLarge.chromeHeight,
                font: LyricSurface.widgetLarge.lyricFont,
                rowSpacing: 10, lineSpacing: 4)
        case .home:
            // The in-app player card — the Live Activity's in-app twin: same
            // compact one-line identity, same fixed box, same 167 pt total.
            return LyricTileLayout(
                boxHeight: LyricSurface.home.blockHeight,
                headerCompact: true, centersVertically: true, padding: 12,
                chromeHeight: LyricSurface.home.chromeHeight)
        }
    }

    /// The tile shows a progress bar unless disabled or in the terminal stale state.
    private var showsProgress: Bool { showsProgressBar && status != .stale }

    init(title: String, artist: String, currentLine: String,
         previousLines: [String] = [],
         nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool, progress: Double, status: LyricStatus = .playing,
         positionMs: Int = 0, durationMs: Int? = nil,
         surface: Surface, palette: LyricTilePalette? = nil, artworkData: Data? = nil,
         resyncPulse: Double = 1, needsResync: Bool = false,
         showsProgressBar: Bool = true, customBoxHeight: CGFloat? = nil) {
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
        func uniqueID(_ kind: String, _ text: String) -> String {
            let key = kind + "\u{1}" + text
            let count = seen[key, default: 0]
            seen[key] = count + 1
            return count == 0 ? "\(kind):\(text)" : "\(kind):\(text)#\(count)"
        }
        let hero: String
        if !currentLine.isEmpty {
            hero = currentLine
        } else if surface == .carPlaySmall {
            // CarPlay intro: the identity row above is already showing the
            // title and artist, so the body stays empty until the song's first
            // real line lands. (Without this the tile printed the identity
            // twice.)
            hero = ""
        } else if currentLine.isEmpty && layout.showsHeaderOnIntro {
            // Same rule for the 4x4 widget's intro header (build 54): the
            // identity is already in the header AND the bottom bar, so the
            // lyric body stays empty until the first real line arrives. The
            // song's upcoming lines still fill the block underneath.
            hero = ""
        } else if !previousLines.isEmpty && isPlaying {
            // Outro transition: current line cleared so previous line rolls off
            hero = ""
        } else if !title.isEmpty {
            hero = artist.isEmpty ? title : "\(title) — \(artist)"
        } else {
            hero = "Play a song to see lyrics"
        }

        // Dynamic eviction across surfaces:
        // If active hero line wraps to 2 lines, evict upcoming lines to preserve line 2 active anchor.
        // If active hero line wraps to 3 lines, evict both neighbors so hero gets full height without truncation.
        let heroLength = hero.count
        let evictUpcoming: Bool
        let evictPrevious: Bool
        switch surface {
        case .carPlaySmall:
            if let customFont, customFont >= 16 {
                evictUpcoming = heroLength > 30
                evictPrevious = heroLength > 56
            } else {
                evictUpcoming = heroLength > 38
                evictPrevious = heroLength > 68
            }
        case .widgetSmall, .widgetMedium:
            evictUpcoming = heroLength > 26
            evictPrevious = heroLength > 52
        case .lockBanner, .home:
            evictUpcoming = heroLength > 36
            evictPrevious = heroLength > 70
        case .widgetLarge:
            evictUpcoming = false
            evictPrevious = false
        }

        // Active lyric is ALWAYS in the second row or middle row unless standalone.
        // If there are no previous lines, evict upcoming so hero renders standalone.
        let hasPreviousLines = !previousLines.isEmpty && status != .idle
        let showPrevious = hasPreviousLines && !evictPrevious && budget.previousShown > 0
        // Normally the upcoming lines are context AROUND the active line, so they
        // only appear once there is one. The 4x4 widget's intro is the exception:
        // the active line is deliberately empty while the header holds the
        // identity, and the song's opening lines are exactly what the tile should
        // be showing underneath it.
        let introPreviewsUpcoming = hero.isEmpty && !displayUpcomingLines.isEmpty && status == .playing
        let showUpcoming = (showPrevious || introPreviewsUpcoming) && status != .idle
            && !evictUpcoming && budget.upcomingShown > 0

        var rows: [LyricRow] = []
        if showPrevious {
            for (idx, line) in previousLines.suffix(budget.previousShown).enumerated() {
                rows.append(LyricRow(id: uniqueID("p", line), text: line,
                                     kind: .previous, opacity: fade(previousIndex: idx)))
            }
        }
        if !hero.isEmpty {
            rows.append(LyricRow(id: uniqueID("h", hero), text: hero, kind: .hero, opacity: 1))
        }
        if showUpcoming {
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
        let allowance = row.kind == .hero ? budget.heroRows : budget.neighborRows
        Text(row.text)
            .font(LyricType.font(size: spec.font, weight: weight))
            .foregroundColor(row.kind == .hero ? colors.heroText : colors.nextText.opacity(row.opacity))
            .multilineTextAlignment(.center)
            .lineLimit(allowance)
            .lineSpacing(customLineSpacing ?? spec.lineSpacing)
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
private struct LyricEdgeFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.055),
                        .init(color: .black, location: 0.945),
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

private extension View {
    func lyricEdgeFade(active: Bool) -> some View {
        modifier(LyricEdgeFade(active: active))
    }
}
