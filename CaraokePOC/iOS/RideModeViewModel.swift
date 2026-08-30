import SwiftUI
import Combine

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

    /// Flips to `false` after Phase C device validation of the real path.
    static let useSimulatedPlayback = true

    @Published private(set) var isOn = false
    @Published private(set) var elapsedMs = 0
    @Published private(set) var currentLine = ""
    @Published private(set) var nextLine: String?

    private var rideModel = RideModeModel()
    private let track = DemoLyrics.track
    private let activity = CaraokeActivityController()
    private var clockTask: Task<Void, Never>?
    private lazy var realPlayback = RidePlaybackController(activity: activity)
    private var playbackCancellables: Set<AnyCancellable> = []

    /// 1 tick per second simulates playback; lyrics advance by their own
    /// timestamps. (The real path reads the player's position instead.)
    private let tickInterval: Duration = .seconds(1)

    var isPlaying: Bool { isOn }

    /// Ride length across all rides (for the Settings screen).
    var totalRideMs: Int { rideModel.totalRideMs }

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
        playbackCancellables.removeAll()
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
