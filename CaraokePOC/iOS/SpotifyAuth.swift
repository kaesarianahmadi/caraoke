import Foundation
import Security
import Combine
import AuthenticationServices
import UIKit

// iOS half of the port from DriveVerse `Core/Auth/SpotifyAuth.swift` (MIT
// © 2026 Praveet Gupta, see THIRD_PARTY_NOTICES.md), renamed for Caraoke:
// Keychain persistence, the ASWebAuthenticationSession PKCE flow, and the
// auth manager. PKCE/policy/token-client logic lives in CaraokeCore.

// MARK: - Keychain storage

final class KeychainTokenStore: SpotifyTokenStore {
    private let service = "com.caraoke.spotify"
    private let account = "token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> SpotifyToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    func save(_ token: SpotifyToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        // Ride Mode polls Spotify while the phone is locked; the default
        // (WhenUnlocked) makes those reads fail and triggers spurious
        // reconnect banners mid-drive.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Client ID storage

/// Where the Spotify Client ID used for OAuth lives. Caraoke (like the
/// category leader) uses the "bring your own Client ID" model: each user
/// creates their own development-mode app (owner is exempt from the 5-user
/// allowlist) and pastes their Client ID here. Public IDs, so UserDefaults
/// is appropriate — the OAuth token stays in the Keychain.
enum SpotifyClientIDStore {
    static let key = "spotify.customClientID"

    static var stored: String? {
        get {
            let value = UserDefaults.standard.string(forKey: key)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Resolution order: the user's own pasted Client ID first, then the
    /// developer-bundled one (Secrets.plist), if present.
    static var hasClientID: Bool { effective != nil }

    static var effective: String? {
        stored ?? SecretsLoader.spotifyClientID
    }
}

// MARK: - Secrets

enum SecretsLoader {
    /// Reads the developer-bundled Spotify Client ID from Secrets.plist
    /// (gitignored — copy Secrets.example.plist). Never hardcoded.
    static var spotifyClientID: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let id = dict["SpotifyClientID"] as? String,
              !id.isEmpty, id != "YOUR_SPOTIFY_CLIENT_ID" else {
            return nil
        }
        return id
    }
}

// MARK: - Auth manager

/// Owns the PKCE authorization flow, token persistence, and refresh.
/// The Client ID is resolved lazily via `clientIDProvider` so a user-pasted
/// ID takes effect without recreating the auth manager.
@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    static let redirectURI = "caraoke://callback"
    static let callbackScheme = "caraoke"
    static let scopes = "user-read-currently-playing user-read-playback-state"
    /// A 401 arriving this soon after a successful refresh means the grant
    /// itself is dead — reconnect instead of refresh-looping.
    static let revokedWindow: TimeInterval = 30

    @Published private(set) var isConnected: Bool
    @Published var needsReconnect = false

    let clientIDProvider: () -> String?
    private let store: SpotifyTokenStore
    private let tokenClient: SpotifyTokenClient
    private var refreshTask: Task<SpotifyToken, Error>?
    private var lastRefreshAt: Date?
    var now: () -> Date = Date.init

    init(
        store: SpotifyTokenStore = KeychainTokenStore(),
        session: URLSession = .shared,
        clientIDProvider: @escaping () -> String? = { SpotifyClientIDStore.effective }
    ) {
        self.store = store
        self.tokenClient = SpotifyTokenClient(session: session)
        self.clientIDProvider = clientIDProvider
        self.isConnected = store.load() != nil
        super.init()
    }

    var hasClientID: Bool { clientIDProvider() != nil }

    // The polling source talks to us through this seam.
    var tokenProvider: SpotifyTokenProviding { self as SpotifyTokenProviding }

    func disconnect() {
        store.clear()
        isConnected = false
        needsReconnect = false
    }

    /// Returns a token valid for at least SpotifyTokenPolicy.expiryMargin,
    /// refreshing first when needed.
    func validAccessToken() async throws -> String {
        let token = store.load()
        switch SpotifyTokenPolicy.action(for: token, now: now()) {
        case .useCurrent:
            if needsReconnect { needsReconnect = false }
            return token!.accessToken
        case .refresh:
            return try await refreshNow().accessToken
        case .reauthorize:
            if isConnected { needsReconnect = true }
            throw SpotifyAuthError.notConnected
        }
    }

    /// Called when the API returns 401 despite a policy-valid token.
    func handleUnauthorized() async {
        if let last = lastRefreshAt, now().timeIntervalSince(last) < Self.revokedWindow {
            // Fresh token still rejected — the grant was revoked.
            store.clear()
            isConnected = false
            needsReconnect = true
            return
        }
        _ = try? await refreshNow()
    }

    /// Single-flight refresh: concurrent callers share one request.
    func refreshNow() async throws -> SpotifyToken {
        if let task = refreshTask {
            return try await task.value
        }
        guard let token = store.load(), let clientID = clientIDProvider() else {
            throw SpotifyAuthError.notConnected
        }
        let client = tokenClient
        let task = Task { try await client.refresh(token, clientID: clientID) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let newToken = try await task.value
            store.save(newToken)
            lastRefreshAt = now()
            isConnected = true
            if needsReconnect { needsReconnect = false }
            return newToken
        } catch SpotifyAuthError.refreshRejected {
            store.clear()
            isConnected = false
            needsReconnect = true
            throw SpotifyAuthError.refreshRejected
        }
    }

    private var webSession: ASWebAuthenticationSession?
    private let presenter = WebAuthPresenter()

    /// Full authorization-code-with-PKCE flow via ASWebAuthenticationSession.
    func connect() async throws {
        guard let clientID = clientIDProvider() else { throw SpotifyAuthError.missingClientID }

        let verifier = SpotifyPKCE.randomVerifier()
        let state = UUID().uuidString
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: SpotifyPKCE.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
        ]

        let callback = try await authenticate(url: comps.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        guard items?.first(where: { $0.name == "state" })?.value == state,
              let code = items?.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.invalidCallback
        }

        let token = try await tokenClient.exchangeCode(
            code, verifier: verifier, clientID: clientID, redirectURI: Self.redirectURI
        )
        store.save(token)
        lastRefreshAt = now()
        isConnected = true
        needsReconnect = false
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = presenter
            self.webSession = session
            session.start()
        }
    }
}

// MARK: - SpotifyTokenProviding

extension SpotifyAuth: SpotifyTokenProviding {}

// MARK: - Web auth presentation anchor

final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let anchor = windows.first(where: \.isKeyWindow) ?? windows.first {
            return anchor
        }
        guard let scene = scenes.first else {
            // Unreachable: connect() is user-initiated from a visible UI,
            // so a window scene always exists by the time this runs.
            preconditionFailure("No UIWindowScene available to present Spotify auth")
        }
        return ASPresentationAnchor(windowScene: scene)
    }
}
