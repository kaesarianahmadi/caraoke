import Foundation
import os
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Transport routing for every out-of-app surface (widget buttons) and the
/// in-app transport.
///
/// Three defects from build 40, all fixed here:
///
/// 1. The source fell back to Apple Music whenever the shared payload was
///    missing, so tapping next while listening on Spotify skipped the *Apple
///    Music* queue — the reported "it always routes to Apple Music".
/// 2. The Spotify branch returned silently when the token needed a
///    reauthorize, so the buttons became inert with no signal at all.
/// 3. The Spotify player endpoints were called without `device_id`. The Web
///    API refuses `/me/player/next` etc. with 404 when no device is named and
///    the app is not the *active* client — which is exactly the case on a
///    phone listening through the Spotify app. That is "the buttons don't work
///    at all".
///

enum TransportAction {
    case playPause
    case next
    case previous
}

/// Outcome of a transport request, so callers can tell the difference between
/// "done" and "there was nothing to drive".
enum TransportOutcome: Equatable {
    case performed(String)
    case noActivePlayer(String)
    case failed(String)
}

enum TransportControl {

    /// `source` overrides the shared payload for in-app calls (the app knows
    /// the selected source even before a track is playing).
    @discardableResult
    static func perform(_ action: TransportAction, source: String? = nil, isPlaying: Bool? = nil) async -> TransportOutcome {
        let payload = SharedWidgetStore.read()
        let resolved = resolvedSource(payload: payload?.source, override: source)
        log("perform \(action) source=\(resolved ?? "none") payload=\(payload?.title ?? "-")")

        if resolved == "spotify" {
            return await spotify(action, isPlaying: isPlaying ?? payload?.isPlaying ?? false)
        }
        if resolved == "appleMusic" {
            return appleMusic(action)
        }
        return .noActivePlayer("No active player")
    }

    /// A valid `MusicSource` raw value, or nil. Nothing else is ever treated as
    /// a source, so a nil/unknown value can never silently become Apple Music
    /// the way build 40's `else` branch did.
    private static func knownSource(_ raw: String?) -> String? {
        guard let raw, MusicSource(rawValue: raw) != nil else { return nil }
        return raw
    }

    private static func resolvedSource(payload: String?, override: String?) -> String? {
        knownSource(payload) ?? knownSource(override) ?? audibleSource()
    }

    /// Which player is audibly running, independent of our shared payload.
    /// `MPMusicPlayerController` reports Apple Music's own state; when it is
    /// idle we assume the user is on Spotify, whose state we cannot read
    /// without a round trip.
    private static func audibleSource() -> String? {
        #if canImport(MediaPlayer)
        switch MPMusicPlayerController.systemMusicPlayer.playbackState {
        case .playing, .paused, .interrupted:
            return "appleMusic"
        default:
            break
        }
        #endif
        return SharedWidgetStore.readSpotifyToken() != nil ? "spotify" : nil
    }

    // MARK: - Apple Music (MediaPlayer)

    private static func appleMusic(_ action: TransportAction) -> TransportOutcome {
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
        log("appleMusic \(action) ok")
        return .performed("Apple Music")
        #else
        return .failed("MediaPlayer unavailable")
        #endif
    }

    // MARK: - Spotify (Web API player endpoints)

    private static func spotify(_ action: TransportAction, isPlaying: Bool) async -> TransportOutcome {
        var token = await accessToken()
        if token == nil {
            token = await accessToken(forceRefresh: true)
        }
        guard var activeToken = token else {
            log("spotify \(action) aborted: no token")
            return .noActivePlayer("Reconnect Spotify in Settings")
        }

        var player = await fetchPlayerState(token: activeToken)
        var deviceID = player?.deviceID
        if deviceID == nil {
            deviceID = await fetchAvailableDevice(token: activeToken)
        }

        if player == nil && deviceID == nil {
            // Might have failed due to expired token; force refresh and retry device lookup
            if let refreshed = await accessToken(forceRefresh: true) {
                activeToken = refreshed
                player = await fetchPlayerState(token: activeToken)
                deviceID = player?.deviceID
                if deviceID == nil {
                    deviceID = await fetchAvailableDevice(token: activeToken)
                }
            }
        }

        guard let targetDevice = deviceID else {
            log("spotify \(action) aborted: no active device")
            return .noActivePlayer("Open Spotify on this phone first")
        }

        var res = await sendAction(action, token: activeToken, deviceID: targetDevice, isPlaying: player?.isPlaying ?? isPlaying)
        if case .failure(let fail) = res, fail.statusCode == 401 {
            // Token expired mid-session; refresh and retry player command once
            log("spotify \(action) got 401, refreshing token and retrying...")
            if let refreshed = await accessToken(forceRefresh: true) {
                activeToken = refreshed
                res = await sendAction(action, token: activeToken, deviceID: targetDevice, isPlaying: player?.isPlaying ?? isPlaying)
            }
        }

        switch res {
        case .success:
            log("spotify \(action) ok device=\(targetDevice)")
            return .performed("Spotify")
        case .failure(let failure):
            log("spotify \(action) failed: \(failure.message)")
            return .failed(failure.message)
        }
    }

    private static func sendAction(_ action: TransportAction, token: String, deviceID: String, isPlaying: Bool) async -> Result<Void, TransportFailure> {
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

        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/\(path)")
        components?.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        guard let url = components?.url else { return .failure(.init("Bad player URL")) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method == "PUT", path == "play" {
            request.httpBody = Data()
        }
        request.timeoutInterval = 8
        return await send(request)
    }

    /// A Spotify transport failure with HTTP status code.
    private struct TransportFailure: Error {
        let message: String
        let statusCode: Int?
        init(_ message: String, statusCode: Int? = nil) {
            self.message = message
            self.statusCode = statusCode
        }
    }

    private struct SpotifyPlayer {
        let deviceID: String?
        let isPlaying: Bool
    }

    /// One call that answers both questions the transport needs: which device
    /// to target, and whether we should play or pause.
    private static func fetchPlayerState(token: String) async -> SpotifyPlayer? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let device = json["device"] as? [String: Any]
        return SpotifyPlayer(deviceID: device?["id"] as? String,
                             isPlaying: json["is_playing"] as? Bool ?? false)
    }

    /// Fallback device lookup when player state is inactive or empty.
    private static func fetchAvailableDevice(token: String) async -> String? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/devices") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [[String: Any]], !devices.isEmpty else { return nil }
        let active = devices.first(where: { ($0["is_active"] as? Bool) == true })
        return (active ?? devices.first)?["id"] as? String
    }

    // MARK: - Queue lookahead

    /// The next track Spotify says will play, used to bake the song change into
    /// the widget's timeline so it needs no reload at the boundary.
    struct QueuedTrack: Equatable, Sendable {
        let title: String
        let artist: String
        let album: String?
        let durationMs: Int
        /// Largest cover the queue entry offers. Needed to bake the next song's
        /// art into the same timeline as its lyrics.
        let artworkURL: String?
    }

    /// What follows the current track, per Spotify's own queue. Needs the
    /// `user-read-playback-state` scope the ride pipeline already polls with, so
    /// it costs no extra consent. Nil when nothing is queued, the token is gone,
    /// or the player is driving something else.
    static func spotifyNextInQueue(timeout: TimeInterval = 6) async -> QueuedTrack? {
        guard let token = await accessToken(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let next = (json["queue"] as? [[String: Any]])?.first,
              let title = next["name"] as? String else { return nil }
        let artists = (next["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let album = (next["album"] as? [String: Any])?["name"] as? String
        // Spotify orders `images` widest-first; take the first that has a URL.
        let artworkURL = (next["album"] as? [String: Any])
            .flatMap { $0["images"] as? [[String: Any]] }?
            .compactMap { $0["url"] as? String }
            .first
        let queued = QueuedTrack(title: title,
                                 artist: artists.joined(separator: ", "),
                                 album: album,
                                 durationMs: next["duration_ms"] as? Int ?? 0,
                                 artworkURL: artworkURL)
        log("queue lookahead: \(queued.title)")
        return queued
    }

    private static func send(_ request: URLRequest) async -> Result<Void, TransportFailure> {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failure(.init("Network error"))
        }
        switch http.statusCode {
        case 200, 202, 204: return .success(())
        case 401: return .failure(.init("Spotify session expired", statusCode: 401))
        case 403: return .failure(.init("Spotify Premium required", statusCode: 403))
        case 404: return .failure(.init("No active Spotify device", statusCode: 404))
        case 429: return .failure(.init("Spotify rate limited", statusCode: 429))
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            return .failure(.init("Spotify \(http.statusCode) \(body.prefix(120))", statusCode: http.statusCode))
        }
    }

    /// Refreshes the shared token when near expiry or when forced; returns
    /// the current access token, or nil when the user must reconnect.
    static func accessToken(forceRefresh: Bool = false) async -> String? {
        guard let token = SharedWidgetStore.readSpotifyToken() else { return nil }
        let action = forceRefresh ? TokenAction.refresh : SpotifyTokenPolicy.action(for: token, now: Date())
        switch action {
        case .useCurrent:
            return token.accessToken
        case .reauthorize:
            return nil
        case .refresh:
            guard let clientID = SharedWidgetStore.readSpotifyClientID(),
                  let refreshed = try? await SpotifyTokenClient().refresh(token, clientID: clientID) else {
                return nil
            }
            SharedWidgetStore.writeSpotifyToken(refreshed)
            return refreshed.accessToken
        }
    }

    /// Same subsystem the ride pipeline logs to, so transport decisions show up
    /// in the console next to the lyrics diagnostics.
    private static func log(_ message: String) {
        Logger(subsystem: "com.caraoke.poc", category: "transport").info("\(message, privacy: .public)")
    }
}
