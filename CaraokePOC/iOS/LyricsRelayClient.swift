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

    init(baseURL: URL? = FeatureFlags.relayBaseURL,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    var isEnabled: Bool { baseURL != nil }

    /// Called by the ride pipeline once a track's lyrics are known and
    /// playing. `startEpochMs` = wall-clock time the track started
    /// (= anchor.capturedAt - anchor.positionMs). Re-sends on track change.
    func register(trackTitle: String, trackArtist: String,
                  lines: [LRCLine], startEpochMs: Int, durationMs: Int?) {
        let endMs = startEpochMs + (durationMs ?? (lines.last?.timeMs ?? 0) + 30_000)
        schedule = LyricsRelayPayload(
            activityPushToken: "", // filled when the push token arrives
            trackTitle: trackTitle,
            trackArtist: trackArtist,
            startEpochMs: startEpochMs,
            lines: LyricsRelayPayload.lines(from: lines),
            endAtEpochMs: endMs
        )
        trySend()
    }

    /// Called on every push-token emit from the activity (first arrival +
    /// rotations). The URLSession is deduplicated: if the schedule is not
    /// ready yet we hold the token (websites change); if both are ready we
    /// send. A fresh token supersedes the old one.
    func setPushToken(_ token: Data) {
        pendingPushToken = token
        trySend()
    }

    /// Best effort; failures are silent (foreground path still works).
    private func trySend() {
        guard isEnabled, let schedule, let token = pendingPushToken else { return }
        var payload = schedule
        payload.activityPushToken = token.map { String(format: "%02x", $0) }.joined()
        guard let body = try? LyricsRelayPayloadEncoder.encode(payload) else { return }

        var request = URLRequest(url: baseURL!.appendingPathComponent("sessions"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Task {
            _ = try? await session.data(for: request)
        }
    }
}