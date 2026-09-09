import Foundation
import Combine

// Ported from DriveVerse `Core/Sync/SyncEngine.swift` (MIT © 2026 Praveet
// Gupta, see THIRD_PARTY_NOTICES.md), adapted to Caraoke's NowPlayingState.
//
// Extrapolates playback position between source reports (Spotify only polls
// every ~5 s; Apple Music's MediaPlayer poll is 1 s) and maps position to the
// current LRC line index. The clock is injected so every path is testable.

struct LyricsPosition: Equatable {
    let positionMs: Int
    let lineIndex: Int?
    let currentLine: String?
    let previousLines: [String]
    let nextLine: String?
    let upcomingLines: [String]
    /// 0–1 through the current line's time window.
    let lineProgress: Double
    /// 0–1 through the whole track.
    let trackProgress: Double
    let isPlaying: Bool

    init(positionMs: Int,
         lineIndex: Int?,
         currentLine: String?,
         previousLines: [String] = [],
         nextLine: String?,
         upcomingLines: [String] = [],
         lineProgress: Double,
         trackProgress: Double,
         isPlaying: Bool) {
        self.positionMs = positionMs
        self.lineIndex = lineIndex
        self.currentLine = currentLine
        self.previousLines = previousLines
        self.nextLine = nextLine
        self.upcomingLines = upcomingLines.isEmpty ? (nextLine.map { [$0] } ?? []) : upcomingLines
        self.lineProgress = lineProgress
        self.trackProgress = trackProgress
        self.isPlaying = isPlaying
    }
}

final class SyncEngine {
    static let seekThresholdMs = 1000
    static let tickInterval: TimeInterval = 0.25

    var now: () -> Date
    private(set) var anchor: NowPlayingState?
    private(set) var lines: [LRCLine] = []
    let positionSubject = CurrentValueSubject<LyricsPosition?, Never>(nil)
    private var timer: AnyCancellable?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func setLyrics(_ lines: [LRCLine]) {
        self.lines = lines
        tick()
    }

    /// Adopts a new source report. Small deviations from the extrapolated
    /// position (≤ 2 s) are treated as polling jitter and ignored so the
    /// display doesn't stutter; anything larger is a seek and snaps.
    func apply(_ state: NowPlayingState?) {
        defer { tick() }
        guard let new = state else {
            anchor = nil
            return
        }
        if let current = anchor,
           current.isSameTrack(as: new),
           current.isPlaying == new.isPlaying,
           new.isPlaying {
            let expected = Self.extrapolatedPositionMs(anchor: current, at: new.capturedAt)
            if abs(expected - new.positionMs) <= Self.seekThresholdMs {
                return // within jitter tolerance — keep the smoother existing anchor
            }
        }
        anchor = new // new track, play/pause flip, or a real seek: snap
    }

    func startTicking() {
        timer = Timer.publish(every: Self.tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stopTicking() {
        timer = nil
    }

    func tick() {
        guard let anchor else {
            positionSubject.send(nil)
            return
        }
        let pos = Self.extrapolatedPositionMs(anchor: anchor, at: now())
        positionSubject.send(Self.position(
            atMs: pos, lines: lines,
            durationMs: anchor.durationMs, isPlaying: anchor.isPlaying
        ))
    }

    // MARK: - Pure helpers

    static func extrapolatedPositionMs(anchor: NowPlayingState, at date: Date) -> Int {
        guard anchor.isPlaying else { return anchor.positionMs }
        let elapsedMs = Int((date.timeIntervalSince(anchor.capturedAt) * 1000).rounded())
        let pos = max(0, anchor.positionMs + elapsedMs)
        if let duration = anchor.durationMs {
            return min(pos, duration)
        }
        return pos
    }

    /// Index of the last line with timestamp ≤ position (binary search);
    /// nil before the first line or when there are no lines.
    static func lineIndex(forPositionMs pos: Int, in lines: [LRCLine]) -> Int? {
        guard let first = lines.first, pos >= first.timeMs else { return nil }
        var lo = 0
        var hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].timeMs <= pos {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    static func position(atMs pos: Int, lines: [LRCLine], durationMs: Int?, isPlaying: Bool) -> LyricsPosition {
        let index = lineIndex(forPositionMs: pos, in: lines)
        let currentLine = index.map { lines[$0].text }
        let previous: [String]
        if let index, index > 0 {
            let prevStart = max(0, index - 2)
            previous = lines[prevStart..<index].map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            previous = []
        }
        let nextLine: String?
        if let index {
            nextLine = index + 1 < lines.count ? lines[index + 1].text : nil
        } else {
            nextLine = lines.first?.text
        }

        let upcoming: [String]
        if let index {
            let nextStart = index + 1
            if nextStart < lines.count {
                let end = min(nextStart + 8, lines.count)
                upcoming = lines[nextStart..<end].map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            } else {
                upcoming = []
            }
        } else {
            upcoming = lines.prefix(8).map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        var lineProgress = 0.0
        if let index {
            let start = lines[index].timeMs
            let end = index + 1 < lines.count ? lines[index + 1].timeMs : (durationMs ?? start + 5000)
            if end > start {
                lineProgress = min(1, max(0, Double(pos - start) / Double(end - start)))
            }
        }
        let trackProgress = durationMs.flatMap { dur in
            dur > 0 ? min(1, max(0, Double(pos) / Double(dur))) : nil
        } ?? 0

        return LyricsPosition(
            positionMs: pos, lineIndex: index,
            currentLine: currentLine,
            previousLines: previous,
            nextLine: nextLine,
            upcomingLines: upcoming,
            lineProgress: lineProgress, trackProgress: trackProgress,
            isPlaying: isPlaying
        )
    }
}
