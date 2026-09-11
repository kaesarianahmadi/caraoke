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
    /// Every lyric row on every surface, at every wrap level. There is no
    /// per-surface override and no minimumScaleFactor anywhere.
    static let lyric: CGFloat = 18

    /// The active line. Emphasis is WEIGHT ONLY — the size is identical to the
    /// dimmed neighbours, and `.semibold` rather than `.bold` (user direction:
    /// build 40's active line read as too heavy, but must stay clearly bolder
    /// than the rest).
    static let lyricWeight: Font.Weight = .semibold
    static let lyricNeighborWeight: Font.Weight = .regular

    /// Line spacing inside one wrapped lyric line.
    static let lyricLineSpacing: CGFloat = 2

    /// Vertical gap between two lyric rows.
    static let lyricRowSpacing: CGFloat = 6

    /// The lyrics page is the one surface that scales UP: the whole window is
    /// lyrics, so it uses the Spotify/Apple Music scale instead of 18 pt.
    static let pageLyric: CGFloat = 28
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
    case carPlaySmall
    case widgetSmall
    case widgetMedium
    case widgetLarge
    case home

    /// Everything that is not the lyric block, in points.
    var chromeHeight: CGFloat {
        switch self {
        case .lockBanner: return 53
        case .carPlaySmall: return 53
        case .widgetSmall: return 45
        case .widgetMedium: return 45
        case .widgetLarge: return 140.5
        case .home: return 91
        }
    }

    /// Space granted to the block itself. For fixed-box surfaces this is the
    /// anti-flicker height; for the large widget it is `maxBoxHeight` plus the
    /// padding the box sits inside.
    var blockHeight: CGFloat {
        switch self {
        case .lockBanner: return 132
        case .carPlaySmall: return 132
        case .widgetSmall: return 102
        case .widgetMedium: return 132
        // Content-sized: 16 pt ceiling padding either side of the 262 pt box.
        case .widgetLarge: return 262 + 32
        case .home: return 126
        }
    }

    /// Richest row set first; the tile picks the first one that fits via
    /// `ViewThatFits`, and the last entry is the guaranteed minimum.
    var budgets: [LyricRowBudget] {
        switch self {
        case .lockBanner, .carPlaySmall:
            // Build 42: active lyric is always in the MIDDLE row.
            // Best: 1 previous + 1 hero + 1 upcoming (active centered).
            // Minimum: 0 previous + 1 hero + 1 upcoming (hero at top).
            // NEVER show hero alone without at least one neighbor.
            return [
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 1, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 1, neighborRows: 1),
            ]
        case .widgetSmall:
            // Hero (2 rows) + two following lines = the "three or four lines"
            // the user asked for. Build 40 clipped the third.
            return [
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 2, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 1, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 0, neighborRows: 1),
            ]
        case .widgetMedium:
            return [
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 1, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 0, neighborRows: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 0, neighborRows: 1),
            ]
        case .widgetLarge:
            return [
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 3),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 2),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 1),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 0),
            ]
        case .home:
            return [
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 1),
                LyricRowBudget(heroRows: 2, previousShown: 1, upcomingShown: 0),
                LyricRowBudget(heroRows: 2, previousShown: 0, upcomingShown: 0),
            ]
        }
    }
}
