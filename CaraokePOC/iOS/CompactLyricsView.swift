import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Only the Live Activity and the two lyric CarPlay tiles use this viewport.
/// Fit wrapped lyrics before adding neighboring rows. Never shrink below 12 pt.
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
    var topInset: CGFloat = 0
    var slideTransitions = false
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var bold: Bool { boldText || legibilityWeight == .bold }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            let height = max(1, geometry.size.height - 12 - topInset)
            let layout = fittedRows(hero: activeText, width: width, height: height)
            VStack(spacing: 5) {
                ForEach(layout.rows) { row in
                    Text(row.text)
                        .font(.system(size: layout.font, weight: bold ? .semibold : .regular))
                        .foregroundStyle(foreground.opacity(row.opacity))
                        .multilineTextAlignment(.center)
                        .lineLimit(row.lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: width)
                        .transition(slideTransitions ? .move(edge: .bottom).combined(with: .opacity) : .opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: slideTransitions ? 0.35 : 0.2), value: layout.rows)
            .frame(width: geometry.size.width, height: max(0, geometry.size.height - topInset), alignment: .center)
            .padding(.top, topInset)
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
        case .stale, .expired: return "Lyrics out of date · Open Caraoke"
        case .playing, .paused: return currentLine.isEmpty ? identity : currentLine
        }
    }

    private var identity: String {
        artist.isEmpty ? title : "\(title) - \(artist)"
    }

    private struct Row: Identifiable, Equatable {
        let id: String
        let text: String
        let opacity: Double
        let lineLimit: Int
    }

    private func fittedRows(hero: String, width: CGFloat, height: CGFloat) -> (font: CGFloat, rows: [Row]) {
        let font = fittedFont(hero: hero, width: width, height: height)
        let heroSize = measure(hero, width: width, font: font)
        let heroLimit = max(1, min(4, Int((height - 2) / heroSize.lineHeight)))
        var rows = [Row(id: hero, text: hero, opacity: 1, lineLimit: heroLimit)]
        guard status == .playing || status == .paused else { return (font, rows) }
        var used = heroSize.height
        var lines = max(1, heroSize.lines)
        func add(_ text: String, opacity: Double, before: Bool = false) {
            let size = measure(text, width: width, font: font)
            let amount = size.height + 5
            guard lines + size.lines <= 4, used + amount <= height else { return }
            let row = Row(id: text, text: text, opacity: opacity, lineLimit: size.lines)
            if before { rows.insert(row, at: 0) } else { rows.append(row) }
            lines += size.lines
            used += amount
        }
        let upcoming = upcomingLines.filter { !$0.isEmpty }
        if let next = upcoming.first { add(next, opacity: 0.75) }
        if let previous = previousLines.last, !previous.isEmpty { add(previous, opacity: 0.6, before: true) }
        for text in upcoming.dropFirst().prefix(2) {
            let rowCount = rows.count
            add(text, opacity: 0.6)
            if rows.count == rowCount { break }
        }
        var seen: [String: Int] = [:]
        let uniqueRows = rows.map { row in
            let occurrence = seen[row.id, default: 0]
            seen[row.id] = occurrence + 1
            return Row(id: "\(row.id)\u{0}\(occurrence)", text: row.text, opacity: row.opacity, lineLimit: row.lineLimit)
        }
        return (font, uniqueRows)
    }

    /// Bounded search avoids repeatedly measuring in half-point increments.
    private func fittedFont(hero: String, width: CGFloat, height: CGFloat) -> CGFloat {
        func fits(_ font: CGFloat) -> Bool {
            let size = measure(hero, width: width, font: font)
            return size.height <= height && size.lines <= 4
        }
        var high = max(12, fontSize)
        if fits(high) { return high }
        var low: CGFloat = 12
        while high - low > 0.5 {
            let candidate = (low + high) / 2
            if fits(candidate) {
                low = candidate
            } else {
                high = candidate
            }
        }
        return low
    }

    private func measure(_ text: String, width: CGFloat, font: CGFloat) -> (height: CGFloat, lineHeight: CGFloat, lines: Int) {
#if canImport(UIKit)
        let face = UIFont.systemFont(ofSize: font, weight: bold ? .semibold : .regular)
        let lineHeight = face.lineHeight
#else
        let face = NSFont.systemFont(ofSize: font, weight: bold ? .semibold : .regular)
        let lineHeight = face.ascender - face.descender + face.leading
#endif
        let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: face], context: nil)
        return (ceil(bounds.height) + 2, lineHeight, max(1, Int(ceil(bounds.height / lineHeight))))
    }
}
