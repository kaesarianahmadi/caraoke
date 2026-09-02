import Foundation
import Dispatch

/// Runs an async body synchronously for the harness (no XCTest on this
/// machine). Returns (value, error) — exactly one is non-nil on completion.
final class AwaitBox<T> {
    var value: T?
    var error: Error?
}

var awaitResultStep = 0
func awaitResult<T>(_ body: @escaping () async throws -> T) -> (value: T?, error: Error?) {
    let box = AwaitBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    awaitResultStep += 1
    print("STEP \(awaitResultStep) enter")
    fflush(stdout)
    Task {
        do {
            box.value = try await body()
        } catch {
            box.error = error
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)
    print("STEP \(awaitResultStep) exit (\(box.error.map { String(describing: $0) } ?? "ok"))")
    fflush(stdout)
    return (box.value, box.error)
}

/// The lyrics providers return an optional themselves, so awaiting them via
/// `awaitResult` produces a double optional. This flattens it.
func awaitLyrics(_ body: @escaping () async throws -> LyricTrack?) -> (value: LyricTrack?, error: Error?) {
    let outcome = awaitResult(body)
    return (outcome.value.flatMap { $0 }, outcome.error)
}

/// URLProtocol mock so the lyrics networking layer is testable without any
/// real network. Standard pattern: injectable handler + request counter.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requestCount = 0
    static var lastQuery: [String: String]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastQuery = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            .map { items in Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a }) }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        handler = nil
        requestCount = 0
        lastQuery = nil
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func httpResponse(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://lrclib.net")!,
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: headers)!
    }

    static func trackJSON(id: Int, synced: String?, plain: String? = "la la la", instrumental: Bool = false, duration: Double = 210) -> Data {
        func jsonEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        let syncedValue = synced.map { "\"" + jsonEscape($0) + "\"" } ?? "null"
        let plainValue = plain.map { "\"" + jsonEscape($0) + "\"" } ?? "null"
        let json = "{\"id\":\(id),\"trackName\":\"Demo Song\",\"artistName\":\"Demo Artist\",\"albumName\":\"Demo Album\",\"duration\":\(duration),\"instrumental\":\(instrumental),\"plainLyrics\":\(plainValue),\"syncedLyrics\":\(syncedValue)}"
        return Data(json.utf8)
    }
}

/// Minimal assertion harness so the timing core (and now the lyrics
/// networking layer) can be verified on a CommandLineTools-only machine
/// (no XCTest). Mirrors the XCTest cases in LyricTimingTests.swift, which
/// run inside Xcode. Exits 1 on any failure.
final class TestRunner {
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    private var track: LyricTrack {
        LyricTrack(lines: [
            LyricLine(startMs: 0, text: "line one"),
            LyricLine(startMs: 5000, text: "line two"),
            LyricLine(startMs: 10000, text: "line three")
        ])
    }

    private func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            failures.append(name)
            print("FAIL: \(name)")
        }
    }

    private func checkEqual<T: Equatable>(_ name: String, _ actual: T?, _ expected: T?) {
        check(name, actual == expected)
        if actual != expected {
            print("      actual=\(String(describing: actual)) expected=\(String(describing: expected))")
        }
    }

    func run() {
        // MARK: lineIndex
        checkEqual("beforeFirstLineIsNil", track.lineIndex(at: -1), nil)
        checkEqual("exactBoundary0", track.lineIndex(at: 0), 0)
        checkEqual("exactBoundary5000", track.lineIndex(at: 5000), 1)
        checkEqual("exactBoundary10000", track.lineIndex(at: 10000), 2)
        checkEqual("withinLine4999", track.lineIndex(at: 4999), 0)
        checkEqual("withinLine7500", track.lineIndex(at: 7500), 1)
        checkEqual("beyondLast", track.lineIndex(at: 999999), 2)

        // empty track
        let empty = LyricTrack(lines: [])
        checkEqual("emptyIndex", empty.lineIndex(at: 0), nil)
        checkEqual("emptyLine", empty.line(at: 0), nil)
        checkEqual("emptyNext", empty.nextLine(after: 0), nil)

        // MARK: current line
        checkEqual("currentAt0", track.line(at: 0)?.text, "line one")
        checkEqual("currentAt4999", track.line(at: 4999)?.text, "line one")
        checkEqual("currentAt5000", track.line(at: 5000)?.text, "line two")
        checkEqual("currentAt12345", track.line(at: 12345)?.text, "line three")
        checkEqual("currentBeforeStart", track.line(at: -1), nil)

        // MARK: next line
        checkEqual("nextDuringFirst", track.nextLine(after: 100)?.text, "line two")
        checkEqual("nextDuringLast", track.nextLine(after: 10000), nil)
        checkEqual("nextAfterEnd", track.nextLine(after: 99999), nil)
        checkEqual("nextBeforeStart", track.nextLine(after: -1), nil)

        // MARK: progress
        check("progressBeforeStart0", abs(track.progress(at: -100) - 0) < 0.0001)
        check("progressAtEnd1", abs(track.progress(at: 10000) - 1) < 0.0001)
        check("progressBeyondEnd1", abs(track.progress(at: 50000) - 1) < 0.0001)
        check("progressMidway", abs(track.progress(at: 5000) - 0.5) < 0.0001)

        // MARK: parser + fixture
        let fixture = FixtureLoader.loadDemoTrack()
        check("fixtureNonEmpty", !fixture.lines.isEmpty)
        check("fixtureHasEnoughLines", fixture.lines.count >= 8)
        let starts = fixture.lines.map(\.startMs)
        check("fixtureSorted", starts == starts.sorted())
        check("fixtureStrictlyIncreasing", Set(starts).count == starts.count)
        check("fixtureStartsWithZero", starts.first == 0)

        let parsed = TimedLyricParser.parse("0\thello\n\nbadrow\n\t\n5000\tworld\n")
        checkEqual("parserTexts", parsed.map(\.text), ["hello", "world"])
        checkEqual("parserStarts", parsed.map(\.startMs), [0, 5000])

        let snap = LyricSnapshotBuilder.snapshot(
            track: fixture, title: "Demo", artist: "Caraoke", positionMs: 7000, isPlaying: true
        )
        checkEqual("snapshotCurrent", snap.currentLine, fixture.line(at: 7000)?.text)
        checkEqual("snapshotNext", snap.nextLine, fixture.nextLine(after: 7000)?.text)
        check("snapshotPlaying", snap.isPlaying)
        check("snapshotProgress", abs(snap.progress - fixture.progress(at: 7000)) < 0.0001)

        // MARK: Ride Mode
        var model = RideModeModel()
        check("rideInitiallyOff", !model.isOn)
        model.start(at: 1000)
        check("rideOnAfterStart", model.isOn)
        model.stop(at: 7000)
        check("rideOffAfterStop", !model.isOn)
        checkEqual("rideDuration", model.totalRideMs, 6000)

        var model2 = RideModeModel()
        model2.start(at: 1000)
        model2.start(at: 5000)
        model2.stop(at: 9000)
        checkEqual("rideIgnoresDoubleStart", model2.totalRideMs, 8000)

        var model3 = RideModeModel()
        model3.stop(at: 100)
        checkEqual("rideStopNoStart", model3.totalRideMs, 0)

        var model4 = RideModeModel()
        model4.start(at: 0)
        model4.stop(at: 5000)
        model4.resetStats()
        checkEqual("rideReset", model4.totalRideMs, 0)

        // MARK: LRC parser (ported from DriveVerse, tested here)
        let lrc = LRCParser.parse(
            """
            [ti:Demo]
            [ar:Someone]
            [00:01.00]first
            [00:05.5]second
            [00:10.250][00:20.5]repeat
            [offset:500]
            [00:30]late
            """
        )
        checkEqual("lrcCount", lrc.count, 5)
        // [offset:500] shifts every entry 500 ms earlier, including the lines
        // that appeared before the tag in the source text.
        checkEqual("lrcFirst", lrc.first?.timeMs, 500)
        checkEqual("lrcFirstText", lrc.first?.text, "first")
        check("lrcFracOneDigit", lrc.contains { $0.timeMs == 5000 && $0.text == "second" })
        check("lrcMultiTag", lrc.filter { $0.text == "repeat" }.map(\.timeMs) == [9750, 20000])
        check("lrcOffset", lrc.contains { $0.timeMs == 29500 && $0.text == "late" })

        checkEqual("lrcColonFrac", LRCParser.parse("[01:02:30]x").first?.timeMs, 62300)
        checkEqual("lrcEmpty", LRCParser.parse("[ti:x]\n\nno brackets here").count, 0)
        checkEqual("lrcClampNegative", LRCParser.parse("[offset:2000]\n[00:01]x").first?.timeMs, 0)
        checkEqual("lrcNegativeOffset", LRCParser.parse("[offset:-1000]\n[00:01]x").first?.timeMs, 2000)

        // MARK: TrackMatcher (ported from DriveVerse, vendor type decoupled)
        checkEqual("matchTitle", TrackMatcher.normalizeTitle("Song (feat. X) - Remix"), "song")
        checkEqual("matchArtist", TrackMatcher.normalizeArtist("Rihanna feat. JAY-Z"), "rihanna")
        checkEqual("matchWhitespace", TrackMatcher.normalizeTitle("  Hello   World  "), "hello world")
        checkEqual(
            "matchSignatureBucket",
            TrackMatcher.signature(title: "A", artist: "B", durationMs: 100000),
            TrackMatcher.signature(title: "A", artist: "B", durationMs: 102499)
        )
        check(
            "matchSignatureDifferent",
            TrackMatcher.signature(title: "A", artist: "B", durationMs: 100000)
                != TrackMatcher.signature(title: "A", artist: "C", durationMs: 100000)
        )
        let candidates = [
            LyricsCandidate(title: "Song", durationMs: 200_000, hasSyncedLyrics: false),
            LyricsCandidate(title: "Song", durationMs: 201_000, hasSyncedLyrics: true),
            LyricsCandidate(title: "Song", durationMs: 250_000, hasSyncedLyrics: true),
        ]
        check("matchPrefersSyncedWithinTolerance", TrackMatcher.bestMatch(from: candidates, title: "Song (Deluxe)", durationMs: 200_500)?.hasSyncedLyrics == true)
        check("matchRejectsFarDuration", TrackMatcher.bestMatch(from: [candidates[0], candidates[2]], title: "Song", durationMs: 200_500)?.durationMs == 200_000)
        check("matchNoDurationKnown", TrackMatcher.bestMatch(from: candidates, title: "Song", durationMs: nil)?.hasSyncedLyrics == true)
        check("matchNone", TrackMatcher.bestMatch(from: candidates, title: "Other", durationMs: nil) == nil)

        // MARK: ActivityUpdatePolicy (ported from DriveVerse, tested here)
        var policy = ActivityUpdatePolicy()
        check("policyFirstSends", policy.shouldUpdate(trackKey: "a|b", lineIndex: 0, isPlaying: true))
        check("policySameSuppresses", !policy.shouldUpdate(trackKey: "a|b", lineIndex: 0, isPlaying: true))
        check("policyLineChangeSends", policy.shouldUpdate(trackKey: "a|b", lineIndex: 1, isPlaying: true))
        check("policyPauseSends", policy.shouldUpdate(trackKey: "a|b", lineIndex: 1, isPlaying: false))
        check("policyTrackChangeSends", policy.shouldUpdate(trackKey: "c|d", lineIndex: 1, isPlaying: false))
        policy.reset()
        check("policyResetSends", policy.shouldUpdate(trackKey: "c|d", lineIndex: 1, isPlaying: false))
        var seeded = ActivityUpdatePolicy()
        seeded.seed(trackKey: "a|b", lineIndex: 0, isPlaying: true)
        check("policySeedSuppresses", !seeded.shouldUpdate(trackKey: "a|b", lineIndex: 0, isPlaying: true))

        // MARK: ActivityUpdateThrottle (ported from DriveVerse, tested here)
        let base = Date(timeIntervalSince1970: 0)
        var throttle = ActivityUpdateThrottle(minInterval: 1.5)
        checkEqual("throttleFirst", throttle.decide(critical: false, now: base), .sendNow)
        checkEqual(
            "throttleCoalesces",
            throttle.decide(critical: false, now: base.addingTimeInterval(0.5)),
            .coalesce(fireIn: 1.0)
        )
        checkEqual("throttleCriticalAlwaysSends", throttle.decide(critical: true, now: base.addingTimeInterval(0.6)), .sendNow)
        throttle.noteSent(now: base.addingTimeInterval(0.9))
        // TimeInterval subtraction carries float error, so compare with a
        // tolerance instead of exact equality.
        if case .coalesce(let fireIn) = throttle.decide(critical: false, now: base.addingTimeInterval(1.0)) {
            check("throttleNoteSentArms", abs(fireIn - 1.4) < 0.001)
        } else {
            check("throttleNoteSentArms", false)
        }
        checkEqual("throttleIntervalElapsed", throttle.decide(critical: false, now: base.addingTimeInterval(2.5)), .sendNow)

        // MARK: LRCLIB lyrics provider (mocked network — no real requests)
        do {
            MockURLProtocol.reset()
            let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
            var clock = fixedNow

            func makeProvider(cacheDir: URL) -> LRCLIBLyricsProvider {
                LRCLIBLyricsProvider(
                    session: MockURLProtocol.makeSession(),
                    cache: LyricsDiskCache(directory: cacheDir),
                    userAgent: "Caraoke/0.1 (test suite)",
                    now: { clock }
                )
            }
            let sig = TrackSignature(title: "Demo Song", artist: "Demo Artist",
                                     album: "Demo Album", durationMs: 210_000)
            let syncedJSON = MockURLProtocol.trackJSON(id: 1, synced: "[00:01.00]hello\n[00:05.00]world")

            // /api/get 200 → parsed synced lines; request shape sanity
            var seenUA: String?
            var seenPath: String?
            MockURLProtocol.handler = { request in
                seenUA = request.value(forHTTPHeaderField: "User-Agent")
                seenPath = request.url?.path
                return (MockURLProtocol.httpResponse(200), syncedJSON)
            }
            let providerA = makeProvider(cacheDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-a-\(UUID().uuidString)"))
            let r1 = awaitLyrics { try await providerA.lyrics(for: sig) }
            check("lrclibGetNoThrow", r1.error == nil)
            check("lrclibGetLines", r1.value?.lines.map(\.text) == ["hello", "world"])
            check("lrclibGetStart", r1.value?.lines.first?.startMs == 1000)
            check("lrclibGetUA", seenUA?.contains("Caraoke") == true)
            check("lrclibGetPath", seenPath == "/api/get")
            check("lrclibGetQuery", MockURLProtocol.lastQuery?["track_name"] == "Demo Song"
                && MockURLProtocol.lastQuery?["artist_name"] == "Demo Artist"
                && MockURLProtocol.lastQuery?["duration"] == "210"
                && MockURLProtocol.lastQuery?["album_name"] == "Demo Album")

            // fresh cache hit → zero additional network
            _ = awaitLyrics { try await providerA.lyrics(for: sig) }
            check("lrclibFreshCacheSkipsNetwork", MockURLProtocol.requestCount == 1)

            // /api/get 404 → /api/search fallback → best synced within ±3 s
            MockURLProtocol.reset()
            let searchJSON = Data("""
            [{"id":2,"trackName":"Demo Song (Live)","artistName":"Demo Artist","albumName":null,"duration":180,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:01.00]live"},
             {"id":3,"trackName":"Demo Song","artistName":"Demo Artist","albumName":null,"duration":211,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:02.00]studio"}]
            """.utf8)
            MockURLProtocol.handler = { request in
                let isGet = request.url?.path == "/api/get"
                return (MockURLProtocol.httpResponse(isGet ? 404 : 200),
                        isGet ? Data("null".utf8) : searchJSON)
            }
            let providerB = makeProvider(cacheDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-b-\(UUID().uuidString)"))
            let r2 = awaitLyrics { try await providerB.lyrics(for: sig) }
            check("lrclibSearchFallback", r2.value?.lines.map(\.text) == ["studio"])
            check("lrclibSearchFallbackStart", r2.value?.lines.first?.startMs == 2000)
            check("lrclibSearchFallbackRequests", MockURLProtocol.requestCount == 2)

            // nothing at either endpoint → nil, no throw
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in (MockURLProtocol.httpResponse(404), Data("null".utf8)) }
            let providerC = makeProvider(cacheDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-c-\(UUID().uuidString)"))
            let r3 = awaitLyrics { try await providerC.lyrics(for: sig) }
            check("lrclibNotFoundNil", r3.value == nil && r3.error == nil)

            // plain-only and instrumental are "no synced lyrics" → nil
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in
                (MockURLProtocol.httpResponse(200), MockURLProtocol.trackJSON(id: 4, synced: nil))
            }
            let providerD = makeProvider(cacheDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-d-\(UUID().uuidString)"))
            let r4 = awaitLyrics { try await providerD.lyrics(for: sig) }
            check("lrclibPlainOnlyNil", r4.value == nil && r4.error == nil)

            MockURLProtocol.handler = { _ in
                (MockURLProtocol.httpResponse(200), MockURLProtocol.trackJSON(id: 5, synced: nil, instrumental: true))
            }
            let r5 = awaitLyrics { try await providerD.lyrics(for: sig) }
            check("lrclibInstrumentalNil", r5.value == nil && r5.error == nil)

            // 429 → rateLimited honoring Retry-After; backoff short-circuits network
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in
                (MockURLProtocol.httpResponse(429, headers: ["Retry-After": "60"]), Data("null".utf8))
            }
            let providerE = makeProvider(cacheDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-e-\(UUID().uuidString)"))
            let r6 = awaitResult { try await providerE.lyrics(for: sig) }
            if case LyricsError.rateLimited(let until)? = r6.error {
                check("lrclib429HonorsRetryAfter", until.timeIntervalSince(fixedNow) == 60)
            } else {
                check("lrclib429HonorsRetryAfter", false)
            }
            check("lrclib429OneRequest", MockURLProtocol.requestCount == 1)
            clock = fixedNow.addingTimeInterval(1)
            let r7 = awaitResult { try await providerE.lyrics(for: sig) }
            check("lrclibBackoffShortCircuits", r7.error != nil && MockURLProtocol.requestCount == 1)

            // stale cache + 429 → stale served instead of blanking the ride
            MockURLProtocol.reset()
            let dirF = FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-f-\(UUID().uuidString)")
            let cacheF = LyricsDiskCache(directory: dirF)
            cacheF.store(syncedJSON, for: TrackMatcher.signature(title: "Demo Song", artist: "Demo Artist", durationMs: 210_000),
                         at: fixedNow.addingTimeInterval(-31 * 24 * 3600))
            MockURLProtocol.handler = { _ in
                (MockURLProtocol.httpResponse(429, headers: ["Retry-After": "120"]), Data("null".utf8))
            }
            let providerF = makeProvider(cacheDir: dirF)
            let r8 = awaitLyrics { try await providerF.lyrics(for: sig) }
            check("lrclibStaleOn429", r8.value?.lines.map(\.text) == ["hello", "world"] && r8.error == nil)
            check("lrclibStaleOn429OneRequest", MockURLProtocol.requestCount == 1)
            let r9 = awaitLyrics { try await providerF.lyrics(for: sig) }
            check("lrclibBackoffServesStale", r9.value?.lines.map(\.text) == ["hello", "world"] && MockURLProtocol.requestCount == 1)

            // stale cache + healthy network → refetch replaces
            MockURLProtocol.reset()
            clock = fixedNow.addingTimeInterval(10_000)
            MockURLProtocol.handler = { _ in
                (MockURLProtocol.httpResponse(200), MockURLProtocol.trackJSON(id: 6, synced: "[00:03.00]fresh"))
            }
            let r10 = awaitLyrics { try await providerF.lyrics(for: sig) }
            check("lrclibStaleRefetches", r10.value?.lines.map(\.text) == ["fresh"] && MockURLProtocol.requestCount == 1)

            // network down + no cache → throws
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let providerG = makeProvider(cacheDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("lrclib-g-\(UUID().uuidString)"))
            let r11 = awaitLyrics { try await providerG.lyrics(for: sig) }
            check("lrclibNetworkErrorThrows", r11.value == nil && r11.error != nil)
        }

        // MARK: Spotify PKCE / token client / source parsing (mocked network)
        do {
            // RFC 7636 appendix B test vector
            check("spotifyPKCEVector",
                  SpotifyPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                      == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
            let verifier = SpotifyPKCE.randomVerifier()
            check("spotifyVerifierLength", verifier.count == 64)
            let challenge = SpotifyPKCE.challenge(for: verifier)
            check("spotifyChallengeShape", challenge.count == 43
                && !challenge.contains("=") && !challenge.contains("+") && !challenge.contains("/"))

            // token policy
            let token = SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1000))
            check("spotifyPolicyNil", SpotifyTokenPolicy.action(for: nil, now: Date(timeIntervalSince1970: 0)) == .reauthorize)
            check("spotifyPolicyUseCurrent", SpotifyTokenPolicy.action(for: token, now: Date(timeIntervalSince1970: 400)) == .useCurrent)
            check("spotifyPolicyRefreshNearExpiry", SpotifyTokenPolicy.action(for: token, now: Date(timeIntervalSince1970: 970)) == .refresh)
            check("spotifyPolicyRefreshExpired", SpotifyTokenPolicy.action(for: token, now: Date(timeIntervalSince1970: 2000)) == .refresh)

            // form body: sorted keys, form-encoding of specials
            let form = String(data: SpotifyTokenClient.formBody(["b": "x y+z", "a": "1"]), encoding: .utf8) ?? ""
            check("spotifyFormBody", form == "a=1&b=x%20y%2Bz")

            // token exchange + refresh against a mocked endpoint
            MockURLProtocol.reset()
            let tokenJSON = Data(#"{"access_token":"at1","refresh_token":"rt1","expires_in":3600}"#.utf8)
            MockURLProtocol.handler = { _ in (MockURLProtocol.httpResponse(200), tokenJSON) }
            let tokenClient = SpotifyTokenClient(session: MockURLProtocol.makeSession())
            let fixedNow = Date(timeIntervalSince1970: 5_000)
            let exchanged = awaitResult {
                try await tokenClient.exchangeCode("code", verifier: "v", clientID: "cid", redirectURI: "caraoke://callback", now: fixedNow)
            }
            check("spotifyExchange", exchanged.value?.accessToken == "at1"
                && exchanged.value?.refreshToken == "rt1"
                && exchanged.value?.expiresAt.timeIntervalSince(fixedNow) == 3600)

            // refresh: keeps the old refresh token when Spotify omits rotation
            MockURLProtocol.handler = { _ in
                (MockURLProtocol.httpResponse(200), Data(#"{"access_token":"at2","expires_in":3600}"#.utf8))
            }
            let refreshed = awaitResult { try await tokenClient.refresh(token, clientID: "cid", now: fixedNow) }
            check("spotifyRefreshRotation", refreshed.value?.accessToken == "at2" && refreshed.value?.refreshToken == "r")

            // 400 → refreshRejected (user must reconnect)
            MockURLProtocol.handler = { _ in (MockURLProtocol.httpResponse(400), Data("{}".utf8)) }
            let rejected = awaitResult { try await tokenClient.refresh(token, clientID: "cid") }
            check("spotifyRefreshRejected", rejected.error.map { String(describing: $0).contains("refreshRejected") } == true)

            // currently-playing parsing
            let playingJSON = Data(#"{"progress_ms":45000,"is_playing":true,"item":{"name":"Song X","duration_ms":200000,"artists":[{"name":"Artist X"}],"album":{"name":"Album X"}}}"#.utf8)
            let state = try? SpotifySource.parseCurrentlyPlaying(playingJSON, capturedAt: fixedNow)
            check("spotifyParsePlaying", state?.title == "Song X"
                && state?.artist == "Artist X"
                && state?.album == "Album X"
                && state?.positionMs == 45000
                && state?.durationMs == 200000
                && state?.isPlaying == true
                && state?.source == .spotify)
            let emptyItemJSON = Data(#"{"progress_ms":null,"is_playing":false,"item":null}"#.utf8)
            let noItem = try? SpotifySource.parseCurrentlyPlaying(emptyItemJSON, capturedAt: fixedNow)
            check("spotifyParseNoItem", noItem == nil)
        }

        // MARK: Entitlement model + cache lifecycle
        do {
            check("entitleAllPlans", CaraokeProducts.isEntitled(productIDs: CaraokeProducts.all))
            check("entitleLifetimeOnly", CaraokeProducts.isEntitled(productIDs: [CaraokeProducts.lifetime]))
            check("entitleEmpty", !CaraokeProducts.isEntitled(productIDs: []))
            check("entitleUnrelated", !CaraokeProducts.isEntitled(productIDs: ["com.vendor.other"]))

            check("paywallThreePlans", PaywallContent.plans.count == 3)
            check("paywallYearlyRecommended", PaywallContent.plans.first?.productID == CaraokeProducts.yearly && PaywallContent.plans.first?.isRecommended == true)
            check("paywallLifetimeText", (PaywallContent.plans.first { $0.productID == CaraokeProducts.lifetime })?.fallbackPriceText.contains("$20") == true)

            // cache clearAll
            let caDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-clear-\(UUID().uuidString)")
            let caCache = LyricsDiskCache(directory: caDir)
            caCache.store(Data("one".utf8), for: "track-a", at: Date())
            caCache.store(Data("two".utf8), for: "track-b", at: Date())
            check("cacheStoresTwo", caCache.retrieve(for: "track-a") != nil && caCache.retrieve(for: "track-b") != nil)
            caCache.clearAll()
            check("cacheClearsAll", caCache.retrieve(for: "track-a") == nil && caCache.retrieve(for: "track-b") == nil)
        }

        // MARK: SyncEngine + now-playing arbiter (ported from DriveVerse)
        do {
            func nowPlayingState(title: String = "S", posMs: Int, playedAgo: TimeInterval, playing: Bool,
                                 at now: Date, source: MusicSource = .spotify, duration: Int? = 100_000) -> NowPlayingState {
                NowPlayingState(title: title, artist: "A", album: nil, durationMs: duration,
                                positionMs: posMs, isPlaying: playing, source: source,
                                capturedAt: now.addingTimeInterval(-playedAgo))
            }
            let t0 = Date(timeIntervalSince1970: 1_000_000)

            // position extrapolation
            let playingAnchor = nowPlayingState(posMs: 10_000, playedAgo: 5, playing: true, at: t0)
            check("syncExtrapolate", SyncEngine.extrapolatedPositionMs(anchor: playingAnchor, at: t0) == 15_000)
            check("syncExtrapolatePaused", SyncEngine.extrapolatedPositionMs(
                anchor: nowPlayingState(posMs: 10_000, playedAgo: 5, playing: false, at: t0), at: t0) == 10_000)
            check("syncExtrapolateClamps", SyncEngine.extrapolatedPositionMs(
                anchor: nowPlayingState(posMs: 99_000, playedAgo: 5, playing: true, at: t0), at: t0) == 100_000)

            // binary-search line index
            let lines = [LRCLine(timeMs: 1000, text: "a"), LRCLine(timeMs: 5000, text: "b"), LRCLine(timeMs: 9000, text: "c")]
            check("syncLineBefore", SyncEngine.lineIndex(forPositionMs: 500, in: lines) == nil)
            check("syncLineExact", SyncEngine.lineIndex(forPositionMs: 5000, in: lines) == 1)
            check("syncLineBetween", SyncEngine.lineIndex(forPositionMs: 7000, in: lines) == 1)
            check("syncLineLast", SyncEngine.lineIndex(forPositionMs: 99_999, in: lines) == 2)
            check("syncLineEmpty", SyncEngine.lineIndex(forPositionMs: 0, in: []) == nil)

            // position building
            let pos = SyncEngine.position(atMs: 7000, lines: lines, durationMs: 12_000, isPlaying: true)
            check("syncPosCurrent", pos.currentLine == "b" && pos.nextLine == "c")
            check("syncPosLineProgress", abs(pos.lineProgress - 0.5) < 0.001)
            check("syncPosTrackProgress", abs(pos.trackProgress - 7000.0 / 12000.0) < 0.001)

            // engine apply semantics: jitter kept, seek snaps, track snaps, pause freezes
            var clock = t0
            let engine = SyncEngine(now: { clock })
            var positions: [LyricsPosition?] = []
            let cancellable = engine.positionSubject.sink { positions.append($0) }
            engine.setLyrics(lines)
            engine.apply(playingAnchor)
            clock = t0
            engine.tick()
            check("syncEngineTickLine", positions.last??.currentLine == "c")

            let jitter = nowPlayingState(posMs: 15_500, playedAgo: 0, playing: true, at: t0)
            engine.apply(jitter)
            check("syncEngineJitterKeptAnchor", engine.anchor?.positionMs == 10_000)

            let seek = nowPlayingState(posMs: 20_500, playedAgo: 0, playing: true, at: t0)
            engine.apply(seek)
            check("syncEngineSeekSnaps", engine.anchor?.positionMs == 20_500)

            engine.apply(nowPlayingState(title: "T2", posMs: 1_000, playedAgo: 0, playing: true, at: t0))
            check("syncEngineTrackSnaps", engine.anchor?.title == "T2")

            engine.apply(nowPlayingState(title: "T2", posMs: 3_000, playedAgo: 0, playing: false, at: t0))
            clock = t0.addingTimeInterval(9)
            engine.tick()
            check("syncEnginePausedFreezes", positions.last??.positionMs == 3_000)
            check("syncEnginePausedLine", positions.last??.currentLine == "a")
            _ = cancellable

            // arbiter
            let applePlaying = nowPlayingState(posMs: 1, playedAgo: 0, playing: true, at: t0, source: .appleMusic)
            let spotifyPlaying = nowPlayingState(title: "Sp", posMs: 2, playedAgo: 0, playing: true, at: t0, source: .spotify)
            check("arbiterAppleWins", NowPlayingArbiter.arbitrate(apple: applePlaying, spotify: spotifyPlaying, pin: .auto, previous: nil)?.title == "S")
            check("arbiterSpotifyWhenAppleIdle", NowPlayingArbiter.arbitrate(apple: nil, spotify: spotifyPlaying, pin: .auto, previous: nil)?.title == "Sp")
            let bothIdle = NowPlayingArbiter.arbitrate(apple: applePlaying.with(isPlaying: false),
                                                       spotify: spotifyPlaying.with(isPlaying: false),
                                                       pin: .auto, previous: nil)
            check("arbiterBothIdle", bothIdle?.title == "S" && bothIdle?.isPlaying == false)
            check("arbiterPinnedSpotify", NowPlayingArbiter.arbitrate(apple: applePlaying, spotify: spotifyPlaying, pin: .spotify, previous: nil)?.title == "Sp")
            check("arbiterPinnedMissing", NowPlayingArbiter.arbitrate(apple: nil, spotify: spotifyPlaying, pin: .appleMusic, previous: nil) == nil)
        }

        // MARK: relay payload
        do {
            let lines = [LRCLine(timeMs: 0, text: "a"),
                         LRCLine(timeMs: 4000, text: "b")]
            let payload = LyricsRelayPayload(
                activityPushToken: "abcd",
                trackTitle: "T",
                trackArtist: "A",
                startEpochMs: 1_700_000_000_000,
                lines: LyricsRelayPayload.lines(from: lines),
                endAtEpochMs: 1_700_000_000_000 + 300_000
            )
            checkEqual("relayLinesMapped", payload.lines.count, 2)
            checkEqual("relayLineTimes", payload.lines.map(\.t), [0, 4000])
            checkEqual("relayLineText", payload.lines.last?.text, "b")
            let json = try LyricsRelayPayloadEncoder.encode(payload)
            let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
            check("relayJSONHasToken", obj?["activityPushToken"] as? String == "abcd")
            check("relayJSONHasStartEpochMs", obj?["startEpochMs"] as? Int == 1_700_000_000_000)
            check("relayJSONLinesCount", (obj?["lines"] as? [[String: Any]])?.count == 2)
            // Sorted-keys encoding must be stable/deterministic.
            let json2 = try LyricsRelayPayloadEncoder.encode(payload)
            check("relayJSONDeterministic", json == json2)
        } catch {
            check("relayEncoding", false)
        }

        // MARK: summary
        print("\n\(passed) passed, \(failed) failed")
        if !failures.isEmpty {
            print("Failures: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }
}

TestRunner().run()
