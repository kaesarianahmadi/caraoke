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
            nextLine: track.nextLine(after: positionMs)?.text,
            isPlaying: isPlaying,
            progress: track.progress(at: positionMs),
            status: status,
            positionMs: positionMs,
            durationMs: durationMs ?? track.durationMs,
            lineIndex: track.lineIndex(at: positionMs)
        )
    }
}