import Foundation

/// Builds the `LyricSnapshot` the UI and Live Activity render. Pure logic, no
/// timers — the caller feeds playback position.
struct LyricSnapshotBuilder {
    static func snapshot(track: LyricTrack,
                         title: String,
                         artist: String,
                         positionMs: Int,
                         isPlaying: Bool) -> LyricSnapshot {
        LyricSnapshot(
            title: title,
            artist: artist,
            currentLine: track.line(at: positionMs)?.text ?? "",
            nextLine: track.nextLine(after: positionMs)?.text,
            isPlaying: isPlaying,
            progress: track.progress(at: positionMs),
            lineIndex: track.lineIndex(at: positionMs)
        )
    }
}
