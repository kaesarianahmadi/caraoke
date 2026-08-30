import Foundation

/// Ride Mode state machine. This is the "master switch" concept from the PRD:
/// an on/off state named Ride Mode, plus a small timer model used by the
/// simulator and the (future) safe-stop-when-parked behaviour.
///
/// Pure Foundation so it is testable on macOS.
struct RideModeModel: Equatable, Sendable {
    private(set) var isOn = false
    private(set) var startedAtMs: Int?
    /// Ride length in ms, preserved across toggles (so the UI can say how long
    /// the last ride lasted). Reset only by `resetStats()`.
    private(set) var totalRideMs: Int = 0

    mutating func start(at nowMs: Int) {
        guard !isOn else { return }
        isOn = true
        startedAtMs = nowMs
    }

    mutating func stop(at nowMs: Int) {
        guard isOn else { return }
        if let started = startedAtMs, nowMs >= started {
            totalRideMs += nowMs - started
        }
        isOn = false
        startedAtMs = nil
    }

    mutating func resetStats() {
        totalRideMs = 0
    }
}
