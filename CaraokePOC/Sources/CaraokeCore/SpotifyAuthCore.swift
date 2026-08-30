import Foundation
import CryptoKit
import Security

// Ported from DriveVerse `Core/Auth/SpotifyAuth.swift` (MIT © 2026 Praveet
// Gupta, see THIRD_PARTY_NOTICES.md): the platform-neutral, unit-testable
// half of the Spotify integration — PKCE, token policy, token storage
// contract, and the token endpoint client. The iOS half (Keychain store,
// ASWebAuthenticationSession flow) lives in iOS/SpotifyAuth.swift.
//
// This is the OFFICIAL Spotify OAuth authorization-code + PKCE flow against
// accounts.spotify.com — no unofficial endpoints (per project constraints).
// Public-launch gates are non-code: extended quota approval + platform
// policy clearance (see the locked-decisions document).

// MARK: - PKCE (RFC 7636)

enum SpotifyPKCE {
    /// 64 characters from the RFC 7636 unreserved set.
    static func randomVerifier() -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// S256: BASE64URL(SHA256(ASCII(verifier))), no padding.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token model & policy

struct SpotifyToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum TokenAction: Equatable {
    case useCurrent
    case refresh
    case reauthorize
}

enum SpotifyTokenPolicy {
    /// Refresh this long before actual expiry so in-flight requests don't 401.
    static let expiryMargin: TimeInterval = 60

    static func action(for token: SpotifyToken?, now: Date) -> TokenAction {
        guard let token else { return .reauthorize }
        return now < token.expiresAt.addingTimeInterval(-expiryMargin) ? .useCurrent : .refresh
    }
}

// MARK: - Token storage

protocol SpotifyTokenStore: AnyObject {
    func load() -> SpotifyToken?
    func save(_ token: SpotifyToken)
    func clear()
}

/// Used by unit tests and SwiftUI previews.
final class InMemorySpotifyTokenStore: SpotifyTokenStore {
    var token: SpotifyToken?
    func load() -> SpotifyToken? { token }
    func save(_ token: SpotifyToken) { self.token = token }
    func clear() { token = nil }
}

// MARK: - Token endpoint client

enum SpotifyAuthError: Error, Equatable {
    case missingClientID
    case invalidCallback
    case notConnected
    case http(Int)
    /// Spotify rejected the refresh token — the user must reconnect.
    case refreshRejected
}

/// Talks to accounts.spotify.com/api/token. Pure request/response — the
/// session is injected so tests can stub it.
struct SpotifyTokenClient {
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String, now: Date = Date()) async throws -> SpotifyToken {
        let response = try await post([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        guard let refresh = response.refresh_token else { throw SpotifyAuthError.invalidCallback }
        return SpotifyToken(
            accessToken: response.access_token,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expires_in))
        )
    }

    /// PKCE refresh can rotate the refresh token; keep the old one if the
    /// response omits it.
    func refresh(_ token: SpotifyToken, clientID: String, now: Date = Date()) async throws -> SpotifyToken {
        let response: TokenResponse
        do {
            response = try await post([
                "grant_type": "refresh_token",
                "refresh_token": token.refreshToken,
                "client_id": clientID,
            ])
        } catch SpotifyAuthError.http(let status) where status == 400 || status == 401 {
            throw SpotifyAuthError.refreshRejected
        }
        return SpotifyToken(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? token.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expires_in))
        )
    }

    private func post(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(params)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw SpotifyAuthError.http(http.statusCode) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(
            params
                .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
                .sorted()
                .joined(separator: "&")
                .utf8
        )
    }
}
