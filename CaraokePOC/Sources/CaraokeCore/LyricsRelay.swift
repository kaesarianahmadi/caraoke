import Foundation

/// JSON payload for the background lyric relay (mechanism #2, see
/// research/background-update-strategy.md). The app sends the FULL lyric
/// schedule + wall-clock start ONCE at session start; the relay schedules an
/// APNs live-activity push at every line boundary, so lyrics keep advancing
/// while the app process is suspended (the driving case).
///
/// This type is pure and lives in CaraokeCore so the encoder is unit-testable
/// on any platform.
struct LyricsRelayPayload: Equatable, Encodable {
    struct Line: Equatable, Encodable {
        /// Milliseconds from the start of the track.
        let t: Int
        let text: String
    }

    /// Hex-encoded APNs device token for this activity (activity.pushToken).
    /// Var because the client fills it in right before sending.
    var activityPushToken: String
    let trackTitle: String
    let trackArtist: String
    /// Wall-clock epoch ms when the track started (the relay adds line t to
    /// this to compute each push time).
    let startEpochMs: Int
    /// Full lyric schedule, strictly ascending by t.
    let lines: [Line]
    /// Wall-clock epoch ms when the session should end (track end or grace).
    let endAtEpochMs: Int
    /// False = playback paused: the relay pushes the frozen state once and
    /// stops scheduling until the client re-registers (isPlaying true).
    var isPlaying: Bool = true

    static func lines(from lyricLines: [LRCLine]) -> [Line] {
        lyricLines.map { Line(t: $0.timeMs, text: $0.text) }
    }
}

enum LyricsRelayPayloadEncoder {
    static func encode(_ payload: LyricsRelayPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}