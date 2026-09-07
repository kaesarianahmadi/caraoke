import Foundation
import Security

struct SharedWidgetPayload: Codable {
    var title: String
    var artist: String
    var currentLine: String
    var nextLine: String?
    var isPlaying: Bool
    var progress: Double
    var status: String
}

enum SharedWidgetStore {
    private static let service = "app.caraoke.widget"
    private static let account = "state"
    private static let suiteName = "group.app.caraoke"

    static func write(_ payload: SharedWidgetPayload?) {
        if let store = UserDefaults(suiteName: suiteName) {
            if let payload {
                store.set(payload.title, forKey: "widget_title")
                store.set(payload.artist, forKey: "widget_artist")
                store.set(payload.currentLine, forKey: "widget_current_line")
                store.set(payload.nextLine, forKey: "widget_next_line")
                store.set(payload.isPlaying, forKey: "widget_is_playing")
                store.set(payload.progress, forKey: "widget_progress")
                store.set(payload.status, forKey: "widget_status")
            } else {
                store.removeObject(forKey: "widget_title")
                store.set("idle", forKey: "widget_status")
            }
        }

        guard let payload else {
            deleteKeychain()
            return
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
        if let store = UserDefaults(suiteName: suiteName),
           let title = store.string(forKey: "widget_title"), !title.isEmpty {
            return SharedWidgetPayload(
                title: title,
                artist: store.string(forKey: "widget_artist") ?? "",
                currentLine: store.string(forKey: "widget_current_line") ?? "",
                nextLine: store.string(forKey: "widget_next_line"),
                isPlaying: store.bool(forKey: "widget_is_playing"),
                progress: store.double(forKey: "widget_progress"),
                status: store.string(forKey: "widget_status") ?? "playing"
            )
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(SharedWidgetPayload.self, from: data)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
