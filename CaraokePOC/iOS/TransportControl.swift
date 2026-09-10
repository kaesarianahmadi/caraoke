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
        guard let token = await accessToken() else {
            // Build 40 returned here with no signal, which is why the buttons
            // looked broken rather than disconnected.
            log("spotify \(action) aborted: no token")
            return .noActivePlayer("Reconnect Spotify in Settings")
        }

        // The device id is what makes these calls land. Without it the Web API
        // answers 404 against a phone playing through the Spotify app.
        let player = await fetchPlayerState(token: token)
        guard let deviceID = player?.deviceID else {
            log("spotify \(action) aborted: no active device")
            return .noActivePlayer("Open Spotify on this phone first")
        }

        let method: String
        let path: String
        switch action {
        case .playPause where player?.isPlaying == true:
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
        guard let url = components?.url else { return .failed("Bad player URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method == "PUT", path == "play" {
            // Resuming with no body and a device_id plays the current item.
            request.httpBody = Data()
        }
        request.timeoutInterval = 8

        switch await send(request) {
        case .success:
            log("spotify \(action) ok device=\(deviceID)")
            return .performed("Spotify")
        case .failure(let message):
            log("spotify \(action) failed: \(message)")
            return .failed(message)
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
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        // 204 = nothing playing anywhere. 404/403 = Premium or scope problem.
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let device = json["device"] as? [String: Any]
        return SpotifyPlayer(deviceID: device?["id"] as? String,
                             isPlaying: json["is_playing"] as? Bool ?? false)
    }

    private static func send(_ request: URLRequest) async -> Result<Void, String> {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failure("Network error")
        }
        switch http.statusCode {
        case 200, 202, 204: return .success
        case 401: return .failure("Spotify session expired")
        case 403: return .failure("Spotify Premium required")
        case 404: return .failure("No active Spotify device")
        case 429: return .failure("Spotify rate limited")
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            return .failure("Spotify \(http.statusCode) \(body.prefix(120))")
        }
    }

    /// Refreshes the shared token when it is within the expiry margin; returns
    /// the current access token, or nil when the user must reconnect.
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
                // Falling back to a token we know is stale only produces a 401
                // two round trips later with no explanation.
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
