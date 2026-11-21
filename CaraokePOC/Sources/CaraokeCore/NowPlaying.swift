import Foundation
import Combine

// Moved from iOS/NowPlayingSource.swift — the playback-source seam is
// platform-neutral (Combine exists on macOS too), so the Spotify polling
// source and its parser can be unit-tested on this machine. AppleMusicSource
// stays in iOS/ (MediaPlayer needs a device).

enum MusicSource: String, Codable, Equatable, CaseIterable, Sendable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

struct NowPlayingState: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int?
    let positionMs: Int
    let isPlaying: Bool
    let source: MusicSource
    /// When `positionMs` was observed — the sync engine extrapolates from here.
    let capturedAt: Date
    var artworkURL: String? = nil
    var artworkData: Data? = nil

    func with(isPlaying: Bool) -> NowPlayingState {
        NowPlayingState(
            title: title, artist: artist, album: album,
            durationMs: durationMs, positionMs: positionMs,
            isPlaying: isPlaying, source: source, capturedAt: capturedAt,
            artworkURL: artworkURL, artworkData: artworkData
        )
    }

    /// Same logical track (ignoring position/playback flags).
    func isSameTrack(as other: NowPlayingState) -> Bool {
        title == other.title && artist == other.artist && album == other.album && source == other.source
    }
}

enum SpotifyPlayback: Equatable, Sendable {
    case track(NowPlayingState)
    case idle
    case unavailable

    static func decode(_ data: Data, statusCode: Int, capturedAt: Date) throws -> Self {
        if statusCode == 204 { return .idle }
        guard statusCode == 200 else { return .unavailable }

        struct Payload: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Image: Decodable { let url: String }
                struct Album: Decodable {
                    let name: String?
                    let images: [Image]?
                }
                let name: String
                let duration_ms: Int?
                let artists: [Artist]?
                let album: Album?
            }
            let progress_ms: Int?
            let is_playing: Bool?
            let item: Item?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let item = payload.item else { return .idle }
        return .track(NowPlayingState(
            title: item.name,
            artist: item.artists?.first?.name ?? "",
            album: item.album?.name,
            durationMs: item.duration_ms,
            positionMs: payload.progress_ms ?? 0,
            isPlaying: payload.is_playing ?? false,
            source: .spotify,
            capturedAt: capturedAt,
            artworkURL: item.album?.images?.first?.url
        ))
    }
}

protocol NowPlayingSource {
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { get }
    func start()
    func stop()
}
