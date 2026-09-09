import Foundation
import Security

// The one cross-process store: app ⇄ widget extension ⇄ Live Activity.
//
// The shared KEYCHAIN is the transport, not an App Group: the committed
// distribution profiles grant `R3Y5ZR429L.*` keychain access to both targets
// but carry no `com.apple.security.application-groups` entitlement, so
// `UserDefaults(suiteName: "group.app.caraoke")` silently wrote to the app's
// own container and every widget read came back empty. Keychain items written
// with an explicit access group are readable by both processes with no
// provisioning change.

enum SharedKeychain {
    /// Both targets declare `$(AppIdentifierPrefix)app.caraoke.ios`.
    static let accessGroup = "R3Y5ZR429L.app.caraoke.ios"

    private static func base(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    static func data(service: String, account: String) -> Data? {
        var query = base(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func set(_ data: Data, service: String, account: String) {
        let query = base(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    static func remove(service: String, account: String) {
        SecItemDelete(base(service: service, account: account) as CFDictionary)
    }
}

enum SharedWidgetStore {
    private static let service = "app.caraoke.widget"
    private static let payloadAccount = "state"
    private static let settingsAccount = "settings"

    private static let spotifyService = "com.caraoke.spotify"
    private static let spotifyTokenAccount = "token"
    private static let spotifyClientIDAccount = "clientID"

    // MARK: - Now-playing payload

    static func write(_ payload: SharedWidgetPayload?) {
        guard let payload else {
            SharedKeychain.remove(service: service, account: payloadAccount)
            return
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        SharedKeychain.set(data, service: service, account: payloadAccount)
    }

    static func read() -> SharedWidgetPayload? {
        guard let data = SharedKeychain.data(service: service, account: payloadAccount) else { return nil }
        return try? JSONDecoder().decode(SharedWidgetPayload.self, from: data)
    }

    // MARK: - Widget configuration (theme / toggles)

    static func readSettings() -> SharedWidgetSettings {
        guard let data = SharedKeychain.data(service: service, account: settingsAccount),
              let settings = try? JSONDecoder().decode(SharedWidgetSettings.self, from: data) else {
            return SharedWidgetSettings()
        }
        return settings
    }

    static func writeSettings(_ settings: SharedWidgetSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        SharedKeychain.set(data, service: service, account: settingsAccount)
    }

    // MARK: - Spotify credentials (so widget buttons can drive Spotify)

    static func readSpotifyToken() -> SpotifyToken? {
        guard let data = SharedKeychain.data(service: spotifyService, account: spotifyTokenAccount) else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    static func writeSpotifyToken(_ token: SpotifyToken?) {
        guard let token, let data = try? JSONEncoder().encode(token) else {
            SharedKeychain.remove(service: spotifyService, account: spotifyTokenAccount)
            return
        }
        SharedKeychain.set(data, service: spotifyService, account: spotifyTokenAccount)
    }

    static func readSpotifyClientID() -> String? {
        guard let data = SharedKeychain.data(service: spotifyService, account: spotifyClientIDAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeSpotifyClientID(_ clientID: String?) {
        guard let clientID, !clientID.isEmpty, let data = clientID.data(using: .utf8) else {
            SharedKeychain.remove(service: spotifyService, account: spotifyClientIDAccount)
            return
        }
        SharedKeychain.set(data, service: spotifyService, account: spotifyClientIDAccount)
    }
}
