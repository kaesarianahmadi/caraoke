import Foundation

/// One user-started intent chain per ride. Old continuations cannot restart a stopped ride.
struct WidgetRefreshSession {
    private(set) var token: String? = nil

    mutating func start() -> String {
        let token = UUID().uuidString
        self.token = token
        return token
    }

    mutating func stop() {
        token = nil
    }

    func contains(_ token: String) -> Bool {
        self.token == token
    }

    /// Wake at the next lyric, capped so track changes, seeks and resume are
    /// discovered promptly. The short floor avoids a zero-delay intent loop.
    static func nextRefreshDelay(payload: SharedWidgetPayload?, now: Date) -> TimeInterval {
        guard let payload, payload.isPlaying, payload.trackStartEpochMs > 0 else { return 3 }
        let position = now.timeIntervalSince1970 * 1000 - Double(payload.trackStartEpochMs)
        guard let next = payload.lines.first(where: { Double($0.timeMs) > position }) else { return 3 }
        return min(3, max(0.05, (Double(next.timeMs) - position) / 1000))
    }
}
