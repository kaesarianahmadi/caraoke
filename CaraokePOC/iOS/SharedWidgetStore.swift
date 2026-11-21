import Foundation
import CoreFoundation
import Security
import WidgetKit
import os

// Spotify credentials remain in the shared Keychain. Widget state and settings
// live in the App Group container, not in securityd.

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
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                log.error("keychain read failed service=\(service, privacy: .public) account=\(account, privacy: .public) status=\(status)")
            }
            return nil
        }
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
    enum Kind: String, CaseIterable {
        case home = "CaraokeWidget"
        case player = "CaraokePlayerWidget"
        case lyrics = "CaraokeLyricsWidget"
        case hybrid = "CaraokeHybridWidget"

        static let lyricSurfaces: Set<Self> = [.home, .lyrics, .hybrid]
    }
    private static let group = "group.app.caraoke.ios"
    private static let fileQueue = DispatchQueue(label: "app.caraoke.widget-files", qos: .userInitiated)
    private static let files = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        .map { WidgetStateFiles(directory: $0.appendingPathComponent("WidgetState", isDirectory: true)) }
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
    static func requestReload(reason: String, kinds: Set<Kind> = Set(Kind.allCases)) {
        for kind in kinds {
            reloadLog.notice("reloadTimeline kind=\(kind.rawValue, privacy: .public) reason=\(reason, privacy: .public)")
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }

    private static let reloadLog = Logger(subsystem: "com.caraoke.poc", category: "widgetreload")

    // MARK: - Now-playing payload

    static func write(_ payload: SharedWidgetPayload?, reloadReason: String? = nil) {
        fileQueue.async {
            access(fallback: ()) { files in
                try files.write(payload)
                notifyChange()
                if let reloadReason { requestReload(reason: reloadReason) }
            }
        }
    }

    static func read() async -> SharedWidgetPayload? {
        await onFileQueue(fallback: nil) { try $0.read() }
    }

    static func replace(_ expected: SharedWidgetPayload, with payload: SharedWidgetPayload) async -> WidgetRepairOutcome {
        await onFileQueue(fallback: .unavailable) { files in
            let current = try files.replace(expected, with: payload)
            if current == payload && payload != expected { notifyChange() }
            guard let current, !current.title.isEmpty else { return .idle }
            return .updated(current)
        }
    }

    static func flushWrites() async {
        await withCheckedContinuation { continuation in
            fileQueue.async { continuation.resume() }
        }
    }

    // MARK: - Widget configuration (theme / toggles)

    static func readSettings() async -> SharedWidgetSettings {
        await onFileQueue(fallback: .init()) { try $0.readSettings() }
    }

    static func updateSettings(reloadReason: String? = nil, _ update: @escaping @Sendable (inout SharedWidgetSettings) -> Void) {
        fileQueue.async {
            access(fallback: ()) { files in
                try files.updateSettings(update)
                notifyChange()
                if let reloadReason { requestReload(reason: reloadReason) }
            }
        }
    }

    private static func onFileQueue<T: Sendable>(fallback: T, _ operation: @escaping @Sendable (WidgetStateFiles) throws -> T) async -> T {
        await withCheckedContinuation { continuation in
            fileQueue.async { continuation.resume(returning: access(fallback: fallback, operation)) }
        }
    }

    private static func access<T>(fallback: T, _ operation: (WidgetStateFiles) throws -> T) -> T {
        guard let files else {
            reloadLog.error("App Group container is unavailable")
            return fallback
        }
        do { return try operation(files) }
        catch {
            reloadLog.error("Widget file access failed: \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    private static func notifyChange() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("app.caraoke.widget.state-changed" as CFString), nil, nil, true)
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
