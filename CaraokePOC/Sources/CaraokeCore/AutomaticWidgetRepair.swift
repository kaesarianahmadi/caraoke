import Foundation

/// Coalesces automatic timeline repairs; explicit user taps are never gated.
actor AutomaticWidgetRepair {
    private var inFlight = false
    private var nextAttempt = Date.distantPast

    func begin(now: Date) -> Bool {
        guard !inFlight, now >= nextAttempt else { return false }
        inFlight = true
        return true
    }

    func finish(now: Date) {
        inFlight = false
        nextAttempt = now.addingTimeInterval(5)
    }
}
