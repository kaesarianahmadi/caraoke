import Foundation

/// Client for the background lyric relay (mechanism #2, see research/
/// background-update-strategy.md and relay/README.md).
///
/// The relay exists because iOS suspends the app process ~30 s after
/// backgrounding, after which no local code can push Live Activity updates
/// (measured on device during Phase C). The client sends the FULL lyric
/// schedule + wall-clock start to the relay ONCE per ride; the relay then
/// fires APNs live-activity pushes at each line boundary, so lyrics keep
/// advancing while the phone is locked in the car.
///
/// Safety: a no-op when no relay is deployed (`FeatureFlags.relayBaseURL`
/// nil). Session start cost is one POST; on failure it stays silent and the
/// app continues to work in the foreground as if the relay did not exist.
@MainActor
final class LyricsRelayClient {
    private let baseURL: URL?
    private let session: URLSession

    private var schedule: LyricsRelayPayload?
    private var pendingPushToken: Data?
    /// The token hex this client last armed the relay with. `end()` re-sends it
    /// so the relay can route the teardown to this device's session.
    private var lastSentTokenHex: String?

    init(baseURL: URL? = FeatureFlags.relayBaseURL,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    var isEnabled: Bool { baseURL != nil }

    /// Surfaced on the HomeView diagnostic line via the activity controller.
    var onStatus: ((String) -> Void)?

    /// Called by the ride pipeline once a track's lyrics are known and
    /// playing. `startEpochMs` = wall-clock time the track started
    /// (= anchor.capturedAt - anchor.positionMs). Re-sends on track change,
    /// seek (new startEpochMs), and play/pause flips (isPlaying).
    func register(trackTitle: String, trackArtist: String,
                  lines: [LRCLine], startEpochMs: Int, durationMs: Int?,
                  isPlaying: Bool = true) {
        let endMs = startEpochMs + (durationMs ?? (lines.last?.timeMs ?? 0) + 30_000)
        schedule = LyricsRelayPayload(
            activityPushToken: "", // filled when the push token arrives
            trackTitle: trackTitle,
            trackArtist: trackArtist,
            startEpochMs: startEpochMs,
            lines: LyricsRelayPayload.lines(from: lines),
            endAtEpochMs: endMs,
            isPlaying: isPlaying
        )
        trySend()
    }

    /// Ride stop: tell the relay to end and drop the session so no stale
    /// pushes continue into a tile we're about to dismiss.
    ///
    /// Carries the push token so the relay can route to this device's session:
    /// sessions are keyed by the activity token (one Durable Object per device),
    /// and an end request without it would land on the shared fallback object
    /// and leave the real session armed.
    func end() {
        guard isEnabled else { return }
        let body = try? JSONSerialization.data(withJSONObject: [
            "action": "end",
            "activityPushToken": lastSentTokenHex ?? pendingPushToken.map(Self.hex) ?? "",
        ])
        guard let body else { return }
        var request = URLRequest(url: baseURL!.appendingPathComponent("sessions"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Task { [weak self] in
            _ = try? await self?.session.data(for: request)
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Called on every push-token emit from the activity (first arrival +
    /// rotations). The URLSession is deduplicated: if the schedule is not
    /// ready yet we hold the token (websites change); if both are ready we
    /// send. A fresh token supersedes the old one.
    func setPushToken(_ token: Data) {
        pendingPushToken = token
        trySend()
    }

    /// Best effort; failures are reported via `onStatus` (the foreground
    /// playback path itself is unaffected).
    private func trySend() {
        guard isEnabled, let schedule, let token = pendingPushToken else {
            // The relay is configured but one half is missing. Silence here is
            // what makes a dark relay indistinguishable from a working one: with
            // no push token the activity never gets APNs coverage while the car
            // is locked, and the app falls back to the local arm without saying
            // so. Surface it instead.
            if isEnabled { onStatus?("Relay idle: waiting for the Live Activity push token") }
            return
        }
        var payload = schedule
        payload.activityPushToken = Self.hex(token)
        lastSentTokenHex = payload.activityPushToken
        guard let body = try? LyricsRelayPayloadEncoder.encode(payload) else {
            onStatus?("Relay idle: schedule could not be encoded")
            return
        }

        var request = URLRequest(url: baseURL!.appendingPathComponent("sessions"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Task { [weak self] in
            do {
                let (_, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                self?.onStatus?(code == 200
                    ? "Relay armed (APNs will update lyrics when locked)"
                    : "Relay rejected registration (HTTP \(code))")
            } catch {
                self?.onStatus?("Relay unreachable: \(error.localizedDescription)")
            }
        }
    }
}