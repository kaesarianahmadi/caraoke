import Foundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Transport routing for every out-of-app surface (widget buttons + Live
/// Activity buttons). The buttons used to call `MPMusicPlayerController`
/// unconditionally, so pressing next while listening on Spotify skipped the
/// Apple Music queue instead. The active source is read from the shared store
/// the app writes on every snapshot.

enum TransportAction {
    case playPause
    case next
    case previous
}

enum TransportControl {

    /// `source` overrides the payload's source for in-app calls (the app knows
    /// the selected source even before a track is playing).
    static func perform(_ action: TransportAction, source: String? = nil, isPlaying: Bool? = nil) async {
        let payload = SharedWidgetStore.read()
        let resolved = source ?? payload?.source
        if resolved == "spotify" {
            await spotify(action, isPlaying: isPlaying ?? payload?.isPlaying ?? false)
        } else {
            appleMusic(action)
        }
    }

    // MARK: - Apple Music (MediaPlayer)

    private static func appleMusic(_ action: TransportAction) {
        #if canImport(MediaPlayer)
        let player = MPMusicPlayerController.systemMusicPlayer
        switch action {
        case .playPause:
            if player.playbackState == .playing {
                player.pause()
            } else {
                player.play()
            }
        case .next:
            player.skipToNextItem()
        case .previous:
            player.skipToPreviousItem()
        }
        #endif
    }

    // MARK: - Spotify (Web API player endpoints)

    private static func spotify(_ action: TransportAction, isPlaying: Bool) async {
        guard let token = await accessToken() else { return }
        let method: String
        let path: String
        switch action {
        case .playPause where isPlaying:
            method = "PUT"; path = "pause"
        case .playPause:
            method = "PUT"; path = "play"
        case .next:
            method = "POST"; path = "next"
        case .previous:
            method = "POST"; path = "previous"
        }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/\(path)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Refreshes the shared token when it is within the expiry margin; returns
    /// the current access token, or nil when the user must reconnect. Shared
    /// with `WidgetResync`, which talks to Spotify from the widget extension.
    static func accessToken() async -> String? {
        guard let token = SharedWidgetStore.readSpotifyToken() else { return nil }
        switch SpotifyTokenPolicy.action(for: token, now: Date()) {
        case .useCurrent:
            return token.accessToken
        case .reauthorize:
            return nil
        case .refresh:
            guard let clientID = SharedWidgetStore.readSpotifyClientID(),
                  let refreshed = try? await SpotifyTokenClient().refresh(token, clientID: clientID) else {
                return token.accessToken
            }
            SharedWidgetStore.writeSpotifyToken(refreshed)
            return refreshed.accessToken
        }
    }
}
