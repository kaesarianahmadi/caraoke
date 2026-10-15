import Foundation
import Security
import WidgetKit
import os

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

    /// A failed write here strands the widget extension on stale data with no
    /// trace, so every status is checked: update falls back to add (item
    /// missing), add falls back to update (item already there), and a final
    /// failure is logged rather than silently dropped.
    private static let log = Logger(subsystem: "com.caraoke.poc", category: "keychain")

    static func set(_ data: Data, service: String, account: String) {
        let query = base(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        if status != errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        if status != errSecSuccess {
            log.error("keychain write failed service=\(service, privacy: .public) account=\(account, privacy: .public) status=\(status)")
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

    // MARK: - Diagnostics

    /// Every timeline reload in the app goes through here, so each one is
    /// attributable.
    ///
    /// The distinction this log exists to settle: "the app stopped asking for
    /// reloads" and "the reload was throttled" look identical on the car
    /// screen. Only the log tells them apart. `reason` should name the trigger
    /// (track change, play/pause, seek, artwork, tap) — never a value that
    /// changes every call, or the log stops being groupable.
    static func requestReload(reason: String) {
        reloadLog.notice("reloadAllTimelines reason=\(reason, privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static let reloadLog = Logger(subsystem: "com.caraoke.poc", category: "widgetreload")

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
