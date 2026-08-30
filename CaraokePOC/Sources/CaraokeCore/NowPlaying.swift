import Foundation
import Combine

// Moved from iOS/NowPlayingSource.swift — the playback-source seam is
// platform-neutral (Combine exists on macOS too), so the Spotify polling
// source and its parser can be unit-tested on this machine. AppleMusicSource
// stays in iOS/ (MediaPlayer needs a device).

enum MusicSource: String, Codable, Equatable, CaseIterable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

struct NowPlayingState: Equatable {
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int?
    let positionMs: Int
    let isPlaying: Bool
    let source: MusicSource
    /// When `positionMs` was observed — the sync engine extrapolates from here.
    let capturedAt: Date

    func with(isPlaying: Bool) -> NowPlayingState {
        NowPlayingState(
            title: title, artist: artist, album: album,
            durationMs: durationMs, positionMs: positionMs,
            isPlaying: isPlaying, source: source, capturedAt: capturedAt
        )
    }

    /// Same logical track (ignoring position/playback flags).
    func isSameTrack(as other: NowPlayingState) -> Bool {
        title == other.title && artist == other.artist && source == other.source
    }
}

protocol NowPlayingSource {
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { get }
    func start()
    func stop()
}
