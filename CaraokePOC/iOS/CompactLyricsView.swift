import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Only the Live Activity and the two lyric CarPlay tiles use this viewport.
/// Measure complete wrapped text before choosing context; never ellipsize a lyric.
struct CompactLyricsView: View {
    let currentLine: String
    let previousLines: [String]
    let upcomingLines: [String]
    let title: String
    let artist: String
    let status: LyricStatus
    var fontSize: CGFloat = 15
    var foreground: Color = .white
    var boldText: Bool = true
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            let height = max(1, geometry.size.height - 12)
            let hero = activeText
            let layout = fittedRows(hero: hero, width: width, height: height)
            VStack(spacing: 5) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                    Text(row.text)
                        .font(.system(size: layout.font, weight: boldText && legibilityWeight != .bold ? .semibold : .regular))
                        .foregroundStyle(foreground.opacity(row.opacity))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: width)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: currentLine)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activeText)
    }

    private var activeText: String {
        switch status {
        case .idle: return "Play a song to see lyrics"
        case .loading: return title.isEmpty ? "Finding lyrics…" : identity
        case .noLyrics: return title.isEmpty ? "No lyrics found" : identity
        case .stale, .expired: return currentLine.isEmpty ? "Tap to resume lyrics" : currentLine
        case .playing, .paused: return currentLine.isEmpty ? identity : currentLine
        }
    }

    private var identity: String {
        artist.isEmpty ? title : "\(title) - \(artist)"
    }

    private struct Row {
        let text: String
        let opacity: Double
    }

    private func fittedRows(hero: String, width: CGFloat, height: CGFloat) -> (font: CGFloat, rows: [Row]) {
        var font = fontSize
        // Preserve the complete hero even for unusually long lines. Context is
        // optional; the active lyric is not. All visible rows share one font.
        while measuredHeight(hero, width: width, font: font) > height, font > 1 {
            font -= 0.5
        }
        var rows = [Row(text: hero, opacity: 1)]
        var used = measuredHeight(hero, width: width, font: font)
        if let previous = previousLines.last, !previous.isEmpty {
            let amount = measuredHeight(previous, width: width, font: font) + 5
            if used + amount <= height * 0.7 {
                rows.insert(Row(text: previous, opacity: 0.35), at: 0)
                used += amount
            }
        }
        for (index, text) in upcomingLines.filter({ !$0.isEmpty }).prefix(3).enumerated() {
            let amount = measuredHeight(text, width: width, font: font) + 5
            guard used + amount <= height else { break }
            rows.append(Row(text: text, opacity: index == 0 ? 0.6 : 0.38))
            used += amount
        }
        return (font, rows)
    }

    private func measuredHeight(_ text: String, width: CGFloat, font: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let face = UIFont.systemFont(ofSize: font, weight: boldText && legibilityWeight != .bold ? .semibold : .regular)
#else
        let face = NSFont.systemFont(ofSize: font, weight: boldText && legibilityWeight != .bold ? .semibold : .regular)
#endif
        let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: face], context: nil)
        return ceil(bounds.height) + 2
    }
}
