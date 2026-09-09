import Foundation

/// Builds the `LyricSnapshot` the UI and Live Activity render. Pure logic, no
/// timers — the caller feeds playback position.
struct LyricSnapshotBuilder {
    static func snapshot(track: LyricTrack,
                         title: String,
                         artist: String,
                         positionMs: Int,
                         isPlaying: Bool,
                         status: LyricStatus = .playing,
                         durationMs: Int? = nil) -> LyricSnapshot {
        LyricSnapshot(
            title: title,
            artist: artist,
            currentLine: track.line(at: positionMs)?.text ?? "",
            previousLines: track.previousLines(before: positionMs, limit: 2),
            nextLine: track.nextLine(after: positionMs)?.text,
            upcomingLines: track.upcomingLines(after: positionMs, limit: 8),
            isPlaying: isPlaying,
            progress: track.progress(at: positionMs),
            status: status,
            positionMs: positionMs,
            durationMs: durationMs ?? track.durationMs,
            lineIndex: track.lineIndex(at: positionMs)
        )
    }
}