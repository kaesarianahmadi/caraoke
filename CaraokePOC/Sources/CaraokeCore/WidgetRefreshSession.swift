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
}
