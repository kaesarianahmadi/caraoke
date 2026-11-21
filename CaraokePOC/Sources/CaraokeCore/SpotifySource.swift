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
    static let defaultActiveInterval: TimeInterval = 2
    static let idleInterval: TimeInterval = 15

    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }

    private let availabilitySubject = CurrentValueSubject<SpotifyAvailability, Never>(.notConnected)
    var availabilityPublisher: AnyPublisher<SpotifyAvailability, Never> {
        availabilitySubject.eraseToAnyPublisher()
    }

    private let session: URLSession
    private let tokenProvider: any SpotifyTokenProviding
    /// Cadence while a track is present (playing OR paused). Set by the ride
    /// to tune the pause/resume reaction time; read each cycle so changes
    /// apply immediately.
    var activeInterval: () -> TimeInterval = { SpotifySource.defaultActiveInterval }

    private var pollTask: Task<Void, Never>?
    private let pollLock = NSRecursiveLock()
    private var pollGeneration: UInt64 = 0

    private func nextPollGeneration() -> UInt64 {
        pollLock.lock()
        defer { pollLock.unlock() }
        pollGeneration &+= 1
        return pollGeneration
    }

    private func publishIfCurrent(_ generation: UInt64, _ publish: () -> Void) {
        pollLock.lock()
        defer { pollLock.unlock() }
        guard generation == pollGeneration, !Task.isCancelled else { return }
        publish()
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        pollLock.lock()
        defer { pollLock.unlock() }
        return generation == pollGeneration && !Task.isCancelled
    }

    private func beginPoll() -> UInt64? {
        pollLock.lock()
        defer { pollLock.unlock() }
        guard !Task.isCancelled else { return nil }
        pollGeneration &+= 1
        return pollGeneration
    }

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
        _ = nextPollGeneration()
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
        guard let generation = beginPoll() else { return Self.idleInterval }
        guard await tokenProvider.isConnected else {
            publishIfCurrent(generation) {
                subject.send(nil)
                if isCurrent(generation) { availabilitySubject.send(.notConnected) }
            }
            return Self.idleInterval
        }
        let token: String
        do {
            token = try await tokenProvider.validAccessToken()
        } catch {
            publishIfCurrent(generation) {
                subject.send(nil)
                if isCurrent(generation) { availabilitySubject.send(.notConnected) }
            }
            return Self.idleInterval
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let requestedAt = Date()
            let (data, response) = try await session.data(for: request)
            guard isCurrent(generation) else { return Self.idleInterval }
            guard let http = response as? HTTPURLResponse else { return Self.idleInterval }
            // `progress_ms` was sampled mid-request: stamping at response
            // arrival made every report look 200-800 ms behind reality. The
            // sample's true time is the request's midpoint — server sampling
            // sits at the middle of the round trip, so extrapolation starts
            // from there instead of the arrival time.
            let capturedAt = requestedAt.addingTimeInterval(Date().timeIntervalSince(requestedAt) / 2)
            switch http.statusCode {
            case 200, 204:
                let playback = try SpotifyPlayback.decode(data, statusCode: http.statusCode, capturedAt: capturedAt)
                let state: NowPlayingState?
                if case .track(let track) = playback { state = track } else { state = nil }
                publishIfCurrent(generation) {
                    subject.send(state)
                    if isCurrent(generation) { availabilitySubject.send(.connected) }
                }
                // Stay on the fast cadence whenever a TRACK is present — even
                // paused. Dropping to 15 s on pause made resume (and the
                // pause icon) lag up to ~10 s: the is_playing flip is only
                // discovered at the next poll, so the poll must stay quick
                // while a ride is live. Only back off when nothing is playing.
                return state != nil ? activeInterval() : Self.idleInterval
            case 401:
                guard isCurrent(generation) else { return Self.idleInterval }
                await tokenProvider.handleUnauthorized()
                publishIfCurrent(generation) {
                    subject.send(nil)
                    if isCurrent(generation) { availabilitySubject.send(.notConnected) }
                }
                return Self.idleInterval
            case 403:
                // Not on the app's development-mode allowlist (or the app was
                // suspended). Surface it clearly and back way off — retrying
                // at poll cadence cannot succeed.
                publishIfCurrent(generation) {
                    subject.send(nil)
                    if isCurrent(generation) { availabilitySubject.send(.needsAllowlist) }
                }
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
}
