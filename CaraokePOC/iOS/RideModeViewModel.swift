import SwiftUI
import Combine

/// The PoC's ride controller: owns Ride Mode state, the fake timed lyric
/// clock, and the Live Activity. All timing is simulated locally — there is
/// no networking and no real music source in this proof of concept (the
/// AppleMusicSource seam is ready for the real playback milestone).
@MainActor
final class RideModeViewModel: ObservableObject {

    @Published private(set) var isOn = false
    @Published private(set) var elapsedMs = 0
    @Published private(set) var currentLine = ""
    @Published private(set) var nextLine: String?

    private var rideModel = RideModeModel()
    private let track = DemoLyrics.track
    private let activity = CaraokeActivityController()
    private var clockTask: Task<Void, Never>?

    /// 1 tick per second simulates playback; lyrics advance by their own
    /// timestamps. (The real app reads the player's position instead.)
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

    func stopRide() {
        guard isOn else { return }
        isOn = false
        rideModel.stop(at: elapsedMs)
        clockTask?.cancel()
        clockTask = nil
        Task { await activity.endNow() }
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
