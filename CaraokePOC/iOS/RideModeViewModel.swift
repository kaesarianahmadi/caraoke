import SwiftUI
import Combine
import os

/// The ride controller: owns Ride Mode state and the Live Activity.
///
/// Two playback paths behind `useSimulatedPlayback`:
/// - **Simulated (current, default):** the fake 1-second clock walks the
///   bundled demo fixture — the proof-of-concept path that works everywhere.
/// - **Real:** `RidePlaybackController` drives Apple Music/Spotify →
///   arbiter → sync engine → LRCLIB lyrics → Live Activity. The flag flips
///   after Phase C validates the real path on hardware (background-update
///   decision, see research/background-update-strategy.md).
@MainActor
final class RideModeViewModel: ObservableObject {

    /// Phase C: real playback path is LIVE (Apple Music/Spotify → arbiter →
    /// sync engine → LRCLIB → Live Activity). The simulated demo clock is OFF
    /// because the user's locked-phone test proved iOS suspends the app process
    /// at ~30 s — the same suspension hits the simulated path, so the demo is
    /// no longer a useful stand-in for the driving case (see research/
    /// background-update-strategy.md: mechanism #2 relay is required; its
    /// infra needs an APNs push key + a relay host, both user-supplied).
    static let useSimulatedPlayback = false

    @Published private(set) var isOn = false
    @Published private(set) var elapsedMs = 0
    @Published private(set) var currentLine = ""
    @Published private(set) var nextLine: String?
    /// Now-playing identity + clock, bridged from the real playback pipeline
    /// so the home screen's player card matches the Lock Screen tile.
    @Published private(set) var trackTitle = ""
    @Published private(set) var trackArtist = ""
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs: Int?
    @Published private(set) var lyricStatus: LyricStatus = .idle

    // Home screen bindings (design states A–D).

    /// Player-card progress 0–1 (from the pipeline anchor; demo = derived).
    var progress: Double {
        guard let durationMs, durationMs > 0 else { return 0 }
        return min(1, Double(positionMs) / Double(durationMs))
    }

    /// Apple Music is always available as a source — the app reads the system
    /// player (MPMusicPlayerController), so the design's "Connected" state is
    /// unconditional for it.
    var appleMusicConnected: Bool { true }

    /// Spotify connection state — one shared auth object for the whole app
    /// (Settings connect flow and the playback pipeline's SpotifySource both
    /// read this instance, so "Connected" in Settings is the same session the
    /// pipeline uses).
    @Published private(set) var spotifyConnected = false

    /// Single SpotifyAuth for Settings + pipeline. Exposed read-only.
    let spotifyAuth = SpotifyAuth()

    /// Non-nil when the Live Activities gate is blocking (design state D):
    /// authorization denied at the system level.
    var liveActivityGateMessage: String? {
        guard activity.authorizationDenied else { return nil }
        return "Live Activities is off"
    }

    private var rideModel = RideModeModel()
    private let track = DemoLyrics.track
    private let activity = CaraokeActivityController()
    private var clockTask: Task<Void, Never>?
    private lazy var realPlayback = RidePlaybackController(activity: activity, spotifyAuth: spotifyAuth)
    private var playbackCancellables: Set<AnyCancellable> = []

    /// 1 tick per second simulates playback; lyrics advance by their own
    /// timestamps. (The real path reads the player's position instead.)
    private let tickInterval: Duration = .seconds(1)

    var isPlaying: Bool { isOn }

    /// Ride length across all rides (for the Settings screen).
    var totalRideMs: Int { rideModel.totalRideMs }

    init() {
        // Diagnostics (why the activity did/didn't appear) go to the console
        // log — the locked Home design has no diagnostic line.
        activity.onDiagnostic = { message in
            Logger(subsystem: "com.caraoke.poc", category: "ride").info("\(message, privacy: .public)")
        }
        // Mirror the shared auth's connection state for the home screen.
        spotifyAuth.$isConnected
            .map { $0 }
            .assign(to: &$spotifyConnected)
    }

    func resetStats() {
        rideModel.resetStats()
    }

    func toggle() {
        isOn ? stopRide() : startRide()
    }

    func startRide() {
        guard !isOn else { return }
        isOn = true
        elapsedMs = 0
        rideModel.start(at: 0)
        // Always-on: request the Live Activity up front (foreground-only)
        // with a placeholder, so the tile exists even before any song plays
        // and persists when the user switches to another app.
        activity.startIdle()
        if Self.useSimulatedPlayback {
            startDemoClock()
        } else {
            startRealPlayback()
        }
    }

    func stopRide() {
        guard isOn else { return }
        isOn = false
        rideModel.stop(at: elapsedMs)
        clockTask?.cancel()
        clockTask = nil
        if !Self.useSimulatedPlayback {
            realPlayback.stop()
        }
        Task { await activity.endNow() }
        // Design state C: Live Lyrics off hides the player card — drop the
        // frozen now-playing bindings (and the bridge subscriptions) so
        // nothing lingers on Home.
        playbackCancellables.removeAll()
        trackTitle = ""
        trackArtist = ""
        currentLine = ""
        nextLine = nil
        positionMs = 0
        durationMs = nil
        lyricStatus = .idle
    }

    private func startDemoClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.tickInterval ?? .seconds(1))
                guard let self else { return }
                self.elapsedMs += 1000
                self.pushSnapshot()
            }
        }
        pushSnapshot()
    }

    private func startRealPlayback() {
        realPlayback.start()
        // Bridge the pipeline's published lines into this model; the
        // pipeline also drives the Live Activity directly.
        realPlayback.$currentLine.assign(to: &$currentLine)
        realPlayback.$nextLine.assign(to: &$nextLine)
        realPlayback.$trackTitle.assign(to: &$trackTitle)
        realPlayback.$trackArtist.assign(to: &$trackArtist)
        realPlayback.$positionMs.assign(to: &$positionMs)
        realPlayback.$durationMs.assign(to: &$durationMs)
        playbackCancellables.removeAll()
        // Status isn't @Published on the controller (write-once per track),
        // so copy it on every tick alongside the playhead.
        realPlayback
            .$positionMs
            .receive(on: RunLoop.main)
            .map { [weak realPlayback] _ in realPlayback?.lyricState ?? .idle }
            .assign(to: &$lyricStatus)
    }

    private func pushSnapshot() {
        let snapshot = LyricSnapshotBuilder.snapshot(
            track: track,
            title: DemoLyrics.title,
            artist: DemoLyrics.artist,
            positionMs: elapsedMs,
            isPlaying: isPlaying
        )
        currentLine = snapshot.currentLine
        nextLine = snapshot.nextLine
        activity.sync(snapshot: snapshot)
    }
}
