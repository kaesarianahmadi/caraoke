import CoreGraphics
import SwiftUI

// One type scale and one row budget for every surface that renders lyrics:
// the Home Screen widgets, the Lock Screen Live Activity, CarPlay, the in-app
// player card and the lyrics page.
//
// Build 40 shipped five separate lyric type scales (18/20/21 in the tile, 15/13
// in the vinyl widget, a 30→15 ViewThatFits ladder on the lyrics page) and
// shrank text with minimumScaleFactor when a line overran its box. The result
// was the reported defect: two lyric lines in the same widget rendered at
// different sizes, with the overflow truncated behind a "…".
//
// The rule now: a lyric line WRAPS, it never shrinks. When a surface runs out
// of room it shows fewer lines at the same size. `LyricType` holds the sizes;
// `LyricTileLayout` holds the budget math, and `Tests/main.swift` asserts every
// surface's budget actually fits the height Apple gives it.

enum LyricType {
    /// The shared scale: every lyric row on the surfaces that do not declare
    /// their own size, at every wrap level.
    ///
    /// Per-SURFACE sizing is the intent — CarPlay renders at 14 or 15 depending
    /// on which tile it is, the 4x4 widget at 20, the lyrics page at 28 — and
    /// each of those lives in `LyricSurface.lyricFont` so the budget math and the
    /// renderer read one number. What is forbidden is two sizes inside ONE tile at
    /// one instant: that was build 40's defect (`minimumScaleFactor` shrinking a
    /// line, and `ViewThatFits` dropping to a rung that carried a different font),
    /// and it is what `budget.font` on every rung and `layoutSingleFont_*` in
    /// `Tests/main.swift` exist to prevent.
    static let lyric: CGFloat = 18

    /// The lyric face, and only the lyric face.
    ///
    /// Standard San Francisco, which on iOS resolves to the Text optical size
    /// below 20 pt and the Display optical size above it — so the 28 pt lyrics
    /// page automatically renders in SF Pro Display while the widget rows render
    /// in SF Pro Text, with no separate handling. `LyricType.pageLyric` is what
    /// puts the page on the Display side of that switch.
    ///
    /// This is the face Apple Music's full-screen lyric panel uses. User
    /// direction chose it explicitly over the rounded alternative (see
    /// `design/font-comparison.html`), and it remains a system font, so Dynamic
    /// Type, the accessibility sizes and the system's own rasterisation all
    /// stay.
    ///
    /// Hero and neighbours share one weight deliberately: on these surfaces the
    /// hierarchy is opacity — the neighbour ladder runs 0.36 to 0.82 — so a
    /// second weight axis would only fight the fade.
    static let lyricDesign: Font.Design = .default
    /// The active line and any string standing in for one.
    static let lyricHeroWeight: Font.Weight = .bold
    /// Dimmed context lines above and below the active line. Equal to the hero
    /// weight on purpose; see above.
    static let lyricNeighborWeight: Font.Weight = .bold

    /// The one construction of a lyric font. Every lyric-adjacent string — the
    /// rows, the placeholder lines, "No lyrics found for this song" — goes
    /// through here, so a surface cannot quietly keep the wrong face. One entry
    /// point, the same reasoning as the single size scale.
    ///
    /// `design` stays overridable because chrome has its own opinion about the
    /// face; nothing in this enum currently asks for anything but the default.
    static func font(size: CGFloat, weight: Font.Weight = .regular,
                     design: Font.Design = lyricDesign) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    /// `Font.Weight` is not `Comparable`, so the hierarchy assertions need a
    /// rank instead of a `>` — the one that matters is that a lyric hero still
    /// outranks `.regular`, which is what separates the lyrics page's active
    /// line from the non-hero lines around it. Only the weights this scale uses
    /// are ranked; anything else returns 0 and fails that comparison loudly
    /// rather than passing by accident.
    static func rank(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 1
        case .thin: return 2
        case .light: return 3
        case .regular: return 4
        case .medium: return 5
        case .semibold: return 6
        case .bold: return 7
        case .heavy: return 8
        case .black: return 9
        default: return 0
        }
    }

    /// Line spacing inside one wrapped lyric line — the gap between two rows of
    /// the SAME lyric when it carries on past the tile's width.
    ///
    /// Stays at 2 for the fixed-box surfaces. The Lock Screen banner, the small
    /// widget and the in-app card are pinned to heights the budget math checks
    /// against (`layoutFits_*` in `Tests/main.swift`), and +2 pt there pushes
    /// their richest row set past the box — which is exactly what that check
    /// reported when this was briefly raised globally. The 4x4 widget, which has
    /// room to spend, overrides it upward in `LyricTileView.layout`.
    static let lyricLineSpacing: CGFloat = 2

    /// Vertical gap between two lyric rows — the space between two DIFFERENT
    /// lyric lines.
    ///
    /// Same story as `lyricLineSpacing`: the shared value is what the fixed-box
    /// surfaces can afford, and the 4x4 widget raises it in its own layout.
    static let lyricRowSpacing: CGFloat = 6

    /// The lyrics page is the one surface that scales UP: the whole window is
    /// lyrics, so it uses the Spotify/Apple Music scale instead of 18 pt. Its
    /// hero takes the shared weight — the hierarchy on that page comes from its
    /// non-hero lines dropping to `.regular`, not from the hero climbing.
    static let pageLyric: CGFloat = 28

    /// CarPlay's mirrored Live Activity tile. Scaled for dashboard readability
    /// from ~1 m in a moving car (14 pt).
    static let carPlayLyric: CGFloat = 14

    /// The CarPlay **Lyrics tile** — the standalone widget that is nothing but
    /// lyrics, sized for the widget stack.
    ///
    /// One point above the mirrored activity: this tile spends its whole box on
    /// lyrics (no progress bar, no cover, no transport) and the user tuned this
    /// value on the vehicle. Per-layer sizes are the intent — what is forbidden
    /// is two sizes inside one tile at one instant.
    static let carPlayLyricTile: CGFloat = 15

    /// The 4x4 Home Screen widget — the one surface that renders ABOVE the
    /// shared scale, and the second deliberate exception after CarPlay.
    ///
    /// User direction, build 54: the big square is the tile people look at from
    /// across a room, and 18 pt read as small and cramped against a competitor's
    /// 4x4 rendering the same song. It has the height to pay for the extra 2 pt
    /// (the block may use 300 of the 379 pt canvas), so it does.
    static let widgetLargeLyric: CGFloat = 20
}

/// How much vertical room a surface gives its lyric block, and how many rows
/// it may fill. Kept as pure arithmetic (no per-row font override) so the
/// budget is unit-testable without a simulator — see the `layoutBudget` checks
/// in `Tests/main.swift`.
struct LyricRowBudget {
    /// Rows of text the active line may wrap to.
    let heroRows: Int
    /// Dimmed context lines above the active line.
    let previousShown: Int
    /// Dimmed lines below the active line.
    let upcomingShown: Int
    /// Rows each dimmed line may wrap to.
    let neighborRows: Int
    let font: CGFloat
    let lineSpacing: CGFloat
    let rowSpacing: CGFloat

    init(heroRows: Int,
         previousShown: Int,
         upcomingShown: Int,
         neighborRows: Int = 2,
         font: CGFloat = LyricType.lyric,
         lineSpacing: CGFloat = LyricType.lyricLineSpacing,
         rowSpacing: CGFloat = LyricType.lyricRowSpacing) {
        self.heroRows = heroRows
        self.previousShown = previousShown
        self.upcomingShown = upcomingShown
        self.neighborRows = neighborRows
        self.font = font
        self.lineSpacing = lineSpacing
        self.rowSpacing = rowSpacing
    }

    var rowCount: Int { previousShown + 1 + upcomingShown }

    /// Height of one text row holding `rows` wrapped lines.
    func height(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * font + CGFloat(rows - 1) * lineSpacing
    }

    /// Total height of the whole lyric block, worst case (every row wraps to
    /// its full allowance, which is why this is the check that matters).
    var worstCaseHeight: CGFloat {
        height(rows: heroRows)
            + CGFloat(previousShown + upcomingShown) * height(rows: neighborRows)
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
    }
}

/// The 2x4 Home Screen widget's rigid tier budget.
///
/// This widget does not render through `LyricTileView` — it is its own layout
/// (lyrics left, record right) — so its geometry had no home in the surface
/// table and lived as literals inside `VinylWidgetView`. That is how it drifted
/// out of sync with the in-app preview, and how a 3-line hero plus a 2-line next
/// line (95 pt) came to overflow an 82 pt tier that clips.
///
/// The numbers live here so three consumers read one declaration: the widget,
/// the in-app preview (`HomeWidgetPreview`, app target) and the budget checks in
/// `Tests/main.swift`. Both targets compile this file, which is what makes it
/// the single source.
enum MediumWidgetTiers {
    /// Apple's documented 2x4 grid size — the tile this budget is drawn against.
    static let hostWidth: CGFloat = 338
    static let hostHeight: CGFloat = 158
    static let padding: CGFloat = 12
    /// What is left for the three tiers after the outer padding.
    static var innerHeight: CGFloat { hostHeight - padding * 2 }

    /// The tiers, top to bottom. They sum to `innerHeight` exactly: no Spacer and
    /// no flexible height, so the transport row cannot be pushed off the tile.
    /// `transportHeight` is 26 pt of buttons plus the 8 pt bottom clearance —
    /// the clearance belongs to the tier, not on top of it.
    static let identityHeight: CGFloat = 18
    static let lyricHeight: CGFloat = 82
    static let transportButtonRowHeight: CGFloat = 26
    static let transportClearance: CGFloat = 8
    static var transportHeight: CGFloat { transportButtonRowHeight + transportClearance }
    static var declaredHeight: CGFloat { identityHeight + lyricHeight + transportHeight }

    /// The lyric column takes this share of the inner width. The remainder holds
    /// the record. Text is NOT capped below the column width, which is what made
    /// long lines wrap early and then overflow the lyric tier.
    static let lyricColumnFraction: CGFloat = 0.60

    static let identityFont: CGFloat = 12
    static let heroFont: CGFloat = 15
    static let neighborFont: CGFloat = 13
    static let transportFont: CGFloat = 13
    static let playGlyphFont: CGFloat = 16

    /// Wrap allowances. Two and two, not three and two: the worst case has to fit
    /// `lyricHeight`, and 3 hero rows + 2 next rows is 95 pt against 82. Two
    /// lines cover roughly 55 characters at the shared column width, and the
    /// read-ahead line keeps both of its rows — which matters more on this widget
    /// than a third row of the current line.
    static let heroRows: Int = 2
    static let neighborRows: Int = 2
    static let rowSpacing: CGFloat = 5
    static let lineSpacing: CGFloat = 1.5

    /// One text row holding `rows` wrapped lines — the same model as
    /// `LyricRowBudget.height`, so the two budgets are checked the same way.
    static func height(rows: Int, font: CGFloat) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * font + CGFloat(rows - 1) * lineSpacing
    }

    /// Worst case: the hero at its full allowance plus the next line at its own.
    static var lyricWorstCaseHeight: CGFloat {
        height(rows: heroRows, font: heroFont)
            + rowSpacing
            + height(rows: neighborRows, font: neighborFont)
    }
}

// MARK: - Per-surface budget table

/// One lyric-rendering surface and the height its host actually grants.
///
/// `availableHeight` is the room left for the lyric block after the surface's
/// own chrome (padding, identity row, progress bar, the large widget's player
/// bar). The numbers come from Apple's documented grid sizes — 158 pt small,
/// 338×158 medium, 375 large, ~160 pt Lock Screen banner — and are asserted in
/// `Tests/main.swift` so a future type-scale change cannot silently overflow a
/// surface the way build 40 did.
enum LyricSurface: String, CaseIterable, Sendable {
    case lockBanner
    /// The mirrored small Live Activity — CarPlay dashboard and the Watch Smart
    /// Stack. Carries a progress bar and an identity row.
    case carPlaySmall
    /// The CarPlay **Lyrics tile**: the standalone widget in the CarPlay stack
    /// (kind `CaraokeLyricsWidget`). Separate from `carPlaySmall` because it is a
    /// different host — a widget tile that spends its entire box on lyrics, with
    /// no progress bar, no cover and no transport.
    case carPlayLyrics
    case widgetSmall
    case widgetMedium
    case widgetLarge
    case home

    /// The height of the host surface, where that height is a documented size.
    /// `nil` means the host sizes the view itself and there is nothing to assert.
    ///
    /// Replaces a `chromeHeight` field that was set on all six surfaces and read
    /// by none, and that did not add up where it could be checked: CarPlay and the
    /// Lock Screen banner each claimed 119 + 53 = 172 pt against a 158 pt tile.
    /// `layoutBlockFitsHost_*` in `Tests/main.swift` asserts the block against
    /// these, so a block that outgrows its surface cannot ship unnoticed again.
    var hostHeight: CGFloat? {
        switch self {
        case .lockBanner: return 167      // the height the banner tile is tuned to
        case .carPlaySmall: return nil    // the activity's small box is system-sized
        case .carPlayLyrics: return MediumWidgetTiers.hostHeight
        case .widgetSmall: return MediumWidgetTiers.hostHeight
        case .widgetMedium: return MediumWidgetTiers.hostHeight
        case .widgetLarge: return 379     // the 4x4 canvas
        case .home: return 167
        }
    }

    /// The size lyrics render at on this surface. One size per surface, never
    /// per row and never shrunk at render time. Two surfaces leave the shared
    /// scale: CarPlay drops to `carPlayLyric` because its mirrored tile is the
    /// smallest, and the 4x4 widget rises to `widgetLargeLyric` because it is
    /// the largest and has the height for it.
    var lyricFont: CGFloat {
        switch self {
        case .carPlaySmall: return LyricType.carPlayLyric
        case .carPlayLyrics: return LyricType.carPlayLyricTile
        case .widgetLarge: return LyricType.widgetLargeLyric
        default: return LyricType.lyric
        }
    }

    /// Space granted to the block itself. For fixed-box surfaces this is the
    /// anti-flicker height; for the large widget it is `maxBoxHeight` plus the
    /// padding the box sits inside.
    ///
    /// Build 45: the Lock Screen banner and the in-app card use 119 pt, which
    /// makes the whole tile measure 167 pt — the exact height of Spotify's
    /// now-playing Live Activity on the same Lock Screen. Build 44's 132 pt
    /// block made the tile 180 pt and the user read it as "too long".
    ///
    /// Build 54 left this table alone: the 4x4 widget's extra room lives in its
    /// own `LyricTileView.layout` ceiling, not here, so the budget checks that
    /// pin the fixed-box surfaces stay meaningful.
    var blockHeight: CGFloat {
        switch self {
        case .lockBanner: return 135
        case .carPlaySmall: return 119
        // The CarPlay Lyrics tile: the whole padded tile, with nothing else in it.
        // 158 pt (Apple's documented small grid) − 8 pt padding top and bottom.
        // It is NOT the banner's 119: that number was inherited when this tile
        // shared a table row with the Lock Screen banner, and it left 23 pt of the
        // car's tile unused. `layoutCarPlayTileFillsHost` pins the derivation.
        case .carPlayLyrics: return MediumWidgetTiers.hostHeight - 16
        case .widgetSmall: return 115
        case .widgetMedium: return 132
        // Content-sized. Build 54 moved it to 300 + 32: the 4x4 canvas is
        // 360x379, and at 262 the block was using roughly two thirds of it — the
        // rest sat as dead space under the lyric block, which is the same
        // under-use the user read as "squeezed". The ceiling is the usable
        // interior (379 − 32 padding − 10 gap − 3 progress − 42 bottom bar − 10
        // gap ≈ 300), so `ViewThatFits` can now pick a richer row set when a
        // song has one, and the extra room becomes air between rows.
        case .widgetLarge: return 300 + 32
        case .home: return 135
        }
    }

    /// Richest row set first; the tile picks the first one that fits via
    /// `ViewThatFits`, and the last entry is the guaranteed minimum.
    var budgets: [LyricRowBudget] {
        switch self {
        case .lockBanner, .home:
            // Active line anchored in row 2 / middle row unless standalone.
            // Allows up to 4 rap lines for hero.
            return [
                LyricRowBudget(heroRows: 4, previousShown: 1, upcomingShown: 1, neighborRows: 1),
                LyricRowBudget(heroRows: 4, previousShown: 1, upcomingShown: 0, neighborRows: 1),
                LyricRowBudget(heroRows: 4, previousShown: 0, upcomingShown: 0, neighborRows: 1),
            ]
        case .carPlaySmall:
            let font = LyricType.carPlayLyric
            return [
                LyricRowBudget(heroRows: 3, previousShown: 1, upcomingShown: 1,
                               neighborRows: 1, font: font),
                LyricRowBudget(heroRows: 3, previousShown: 1, upcomingShown: 0,
                               neighborRows: 1, font: font),
                LyricRowBudget(heroRows: 3, previousShown: 0, upcomingShown: 0,
                               neighborRows: 1, font: font),
            ]
        case .carPlayLyrics:
            // The CarPlay Lyrics tile. Same three-row shape as the banner — the
            // active line with a neighbour above or below — at this tile's own
            // size, inside the whole padded tile. `spacing` matches the layout
            // case in `LyricTileView` so the budget model is the render model:
            // 89 pt worst case against 142 pt of box.
            let font = LyricType.carPlayLyricTile
            func rung(previous: Int, upcoming: Int) -> LyricRowBudget {
                LyricRowBudget(heroRows: 3, previousShown: previous, upcomingShown: upcoming,
                               neighborRows: 1, font: font, lineSpacing: 2, rowSpacing: 5)
            }
            return [rung(previous: 1, upcoming: 1),
                    rung(previous: 1, upcoming: 0),
                    rung(previous: 0, upcoming: 0)]
        case .widgetSmall:
            // Centred active line (1 previous + 1 hero + 1 upcoming) with 3-line wrap allowance.
            return [
                LyricRowBudget(heroRows: 3, previousShown: 1, upcomingShown: 1, neighborRows: 1),
                LyricRowBudget(heroRows: 3, previousShown: 1, upcomingShown: 0, neighborRows: 1),
                LyricRowBudget(heroRows: 3, previousShown: 0, upcomingShown: 0, neighborRows: 1),
            ]
        case .widgetMedium:
            return [
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 1, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 0, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 0, neighborRows: 1),
            ]
        case .widgetLarge:
            // Same rows as before, at `LyricType.widgetLargeLyric` (20 pt) rather
            // than the shared 18: the richest set is 234 pt against the 300 pt
            // ceiling, so the extra 2 pt per row is already paid for.
            //
            // Every entry carries the size, not just the richest one. When only
            // the first entry did, `ViewThatFits` could drop to a fallback rung
            // and render the SAME tile at 18 pt in a tighter moment — the
            // per-row size inconsistency build 40 shipped, arriving through the
            // budget ladder instead of through `minimumScaleFactor`.
            let font = LyricType.widgetLargeLyric
            return [
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 3, font: font),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 2, font: font),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 1, font: font),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 1, font: font),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 0, font: font),
            ]
        }
    }
}
