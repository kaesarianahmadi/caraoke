import Foundation

enum WidgetRepairOutcome: Equatable, Sendable {
    case updated(SharedWidgetPayload)
    case idle
    case unavailable
}

/// Concurrent widget wakes share the same repair. Cache only failures briefly
/// so an unavailable player does not trigger a request from every wake.
actor AutomaticWidgetRepair {
    private var inFlight: Task<WidgetRepairOutcome, Never>?
    private var nextAttempt = Date.distantPast

    func refresh(force: Bool = false, now: @Sendable () -> Date = { Date() },
                 operation: @escaping @Sendable () async -> WidgetRepairOutcome) async -> WidgetRepairOutcome {
        if let inFlight { return await inFlight.value }
        guard force || now() >= nextAttempt else { return .unavailable }
        let task = Task { await operation() }
        inFlight = task
        let outcome = await task.value
        if case .unavailable = outcome { nextAttempt = now().addingTimeInterval(5) }
        else { nextAttempt = .distantPast }
        inFlight = nil
        return outcome
    }
}
