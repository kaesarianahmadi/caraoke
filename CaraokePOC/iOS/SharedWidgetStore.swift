import Foundation
import Security

struct SharedLyricLine: Codable, Hashable {
    var timeMs: Int
    var text: String
}

struct SharedWidgetPayload: Codable {
    var title: String
    var artist: String
    var currentLine: String
    var nextLine: String?
    var upcomingLines: [String]
    var isPlaying: Bool
    var progress: Double
    var status: String
    var trackStartEpochMs: Int
    var durationMs: Int
    var lines: [SharedLyricLine]

    init(title: String,
         artist: String,
         currentLine: String,
         nextLine: String? = nil,
         upcomingLines: [String] = [],
         isPlaying: Bool,
         progress: Double,
         status: String,
         trackStartEpochMs: Int = 0,
         durationMs: Int = 0,
         lines: [SharedLyricLine] = []) {
        self.title = title
        self.artist = artist
        self.currentLine = currentLine
        self.nextLine = nextLine
        self.upcomingLines = upcomingLines.isEmpty ? (nextLine.map { [$0] } ?? []) : upcomingLines
        self.isPlaying = isPlaying
        self.progress = progress
        self.status = status
        self.trackStartEpochMs = trackStartEpochMs
        self.durationMs = durationMs
        self.lines = lines
    }
}

enum SharedWidgetStore {
    private static let service = "app.caraoke.widget"
    private static let account = "state"
    private static let accessGroup = "R3Y5ZR429L.app.caraoke.ios"
    private static let suiteName = "group.app.caraoke"
    private static let payloadKey = "widget_full_payload"

    static func write(_ payload: SharedWidgetPayload?) {
        // 1. Write to App Group UserDefaults
        if let store = UserDefaults(suiteName: suiteName) {
            if let payload {
                store.set(payload.title, forKey: "widget_title")
                store.set(payload.artist, forKey: "widget_artist")
                store.set(payload.currentLine, forKey: "widget_current_line")
                store.set(payload.nextLine, forKey: "widget_next_line")
                store.set(payload.isPlaying, forKey: "widget_is_playing")
                store.set(payload.progress, forKey: "widget_progress")
                store.set(payload.status, forKey: "widget_status")
                if let data = try? JSONEncoder().encode(payload) {
                    store.set(data, forKey: payloadKey)
                }
            } else {
                store.removeObject(forKey: "widget_title")
                store.removeObject(forKey: payloadKey)
                store.set("idle", forKey: "widget_status")
            }
        }

        // 2. Write to Shared Keychain
        guard let payload else {
            deleteKeychain()
            return
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateFields: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, updateFields as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }

    static func read() -> SharedWidgetPayload? {
        // Try App Group UserDefaults first
        if let store = UserDefaults(suiteName: suiteName) {
            if let data = store.data(forKey: payloadKey),
               let decoded = try? JSONDecoder().decode(SharedWidgetPayload.self, from: data) {
                return decoded
            }
            if let title = store.string(forKey: "widget_title"), !title.isEmpty {
                return SharedWidgetPayload(
                    title: title,
                    artist: store.string(forKey: "widget_artist") ?? "",
                    currentLine: store.string(forKey: "widget_current_line") ?? "",
                    nextLine: store.string(forKey: "widget_next_line"),
                    upcomingLines: [],
                    isPlaying: store.bool(forKey: "widget_is_playing"),
                    progress: store.double(forKey: "widget_progress"),
                    status: store.string(forKey: "widget_status") ?? "playing"
                )
            }
        }

        // Fallback to Shared Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let decoded = try? JSONDecoder().decode(SharedWidgetPayload.self, from: data) {
            return decoded
        }

        // Generic query without access group fallback (simulator)
        let simQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var simResult: AnyObject?
        if SecItemCopyMatching(simQuery as CFDictionary, &simResult) == errSecSuccess,
           let simData = simResult as? Data,
           let decoded = try? JSONDecoder().decode(SharedWidgetPayload.self, from: simData) {
            return decoded
        }

        return nil
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)

        let simQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(simQuery as CFDictionary)
    }
}
