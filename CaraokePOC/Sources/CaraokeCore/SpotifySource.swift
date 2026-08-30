import Foundation
import Combine

// Ported from DriveVerse `Core/NowPlaying/SpotifySource.swift` (MIT © 2026
// Praveet Gupta, see THIRD_PARTY_NOTICES.md). Polls the Spotify Web API's
// currently-playing endpoint — the OFFICIAL API with OAuth PKCE tokens.
// 5 s while playing, 15 s while idle. Never talks to the Spotify app.
//
// Non-code gates for public launch (locked decisions): Spotify extended-quota
// approval (development mode ≈25 users) and platform-policy clearance for
// lyric-sync display. Lived in iOS before; moved to Core for testability —
// everything here is Foundation + Combine.

/// Structural requirements the auth manager fulfills (conformance declared
/// on iOS/SpotifyAuth.swift where SpotifyAuth lives).
@MainActor
protocol SpotifyTokenProviding: AnyObject {
    var isConnected: Bool { get }
    func validAccessToken() async throws -> String
    func handleUnauthorized() async
}

/// Announces whether Spotify is actually usable for this user. Development
/// mode allows only 5 allowlisted accounts — everyone else gets 403 on every
/// call, so the UI must show a "limited beta" state instead of breakage.
enum SpotifyAvailability: Equatable {
    case notConnected
    case connected
    /// 403 from the API: this account is not on the app's allowlist.
    case needsAllowlist
}

final class SpotifySource: NowPlayingSource {
    static let endpoint = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
    static let defaultActiveInterval: TimeInterval = 5
    static let idleInterval: TimeInterval = 15

    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }

    private let availabilitySubject = CurrentValueSubject<SpotifyAvailability, Never>(.notConnected)
    var availabilityPublisher: AnyPublisher<SpotifyAvailability, Never> {
        availabilitySubject.eraseToAnyPublisher()
    }

    private let session: URLSession
    private let tokenProvider: any SpotifyTokenProviding
    /// Settings-backed (3–10 s); read each cycle so changes apply immediately.
    var activeInterval: () -> TimeInterval = { SpotifySource.defaultActiveInterval }

    private var pollTask: Task<Void, Never>?

    init(session: URLSession = .shared, tokenProvider: any SpotifyTokenProviding) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Foreground resync: abandon the current sleep and poll immediately.
    func pollNow() {
        guard pollTask != nil else { return }
        stop()
        start()
    }

    /// Announces the idle state without starting the poll loop. Needed when
    /// the source is feature-gated off (public builds): the coordinator's
    /// CombineLatest3 requires every input to have emitted at least once.
    func emitIdle() {
        subject.send(nil)
        availabilitySubject.send(.notConnected)
    }

    /// One poll; returns the delay until the next one.
    func pollOnce() async -> TimeInterval {
        guard await tokenProvider.isConnected else {
            subject.send(nil)
            availabilitySubject.send(.notConnected)
            return Self.idleInterval
        }
        let token: String
        do {
            token = try await tokenProvider.validAccessToken()
        } catch {
            subject.send(nil)
            availabilitySubject.send(.notConnected)
            return Self.idleInterval
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return Self.idleInterval }
            switch http.statusCode {
            case 200:
                let state = try Self.parseCurrentlyPlaying(data, capturedAt: Date())
                subject.send(state)
                availabilitySubject.send(.connected)
                return state?.isPlaying == true ? activeInterval() : Self.idleInterval
            case 204: // nothing playing
                subject.send(nil)
                availabilitySubject.send(.connected)
                return Self.idleInterval
            case 401:
                await tokenProvider.handleUnauthorized()
                subject.send(nil)
                availabilitySubject.send(.notConnected)
                return Self.idleInterval
            case 403:
                // Not on the app's development-mode allowlist (or the app was
                // suspended). Surface it clearly and back way off — retrying
                // at poll cadence cannot succeed.
                subject.send(nil)
                availabilitySubject.send(.needsAllowlist)
                return 60
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                return max(retryAfter ?? Self.idleInterval, 1)
            default:
                return Self.idleInterval
            }
        } catch {
            // Transient network error (tunnel, dead zone) — just try again.
            return Self.idleInterval
        }
    }

    // MARK: - Parsing (pure, fixture-tested)

    static func parseCurrentlyPlaying(_ data: Data, capturedAt: Date) throws -> NowPlayingState? {
        struct Payload: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String? }
                let name: String
                let duration_ms: Int?
                let artists: [Artist]?
                let album: Album?
            }
            let progress_ms: Int?
            let is_playing: Bool?
            let item: Item?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let item = payload.item else { return nil } // e.g. private session or ad
        return NowPlayingState(
            title: item.name,
            artist: item.artists?.first?.name ?? "",
            album: item.album?.name,
            durationMs: item.duration_ms,
            positionMs: payload.progress_ms ?? 0,
            isPlaying: payload.is_playing ?? false,
            source: .spotify,
            capturedAt: capturedAt
        )
    }
}
