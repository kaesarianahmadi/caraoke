import XCTest
import Combine
// Under SwiftPM, CaraokeCore is an imported module. When the Xcode project
// (project.yml) compiles the same sources into the test bundle directly,
// there is no separate module — the import is dropped via canImport.
#if canImport(CaraokeCore)
@testable import CaraokeCore
#endif

final class LyricTimingTests: XCTestCase {

    private var track: LyricTrack {
        LyricTrack(lines: [
            LyricLine(startMs: 0, text: "line one"),
            LyricLine(startMs: 5000, text: "line two"),
            LyricLine(startMs: 10000, text: "line three")
        ])
    }

    // MARK: lineIndex

    func testBeforeFirstLineIsNil() {
        XCTAssertNil(track.lineIndex(at: -1))
    }

    func testExactBoundarySelectsThatLine() {
        XCTAssertEqual(track.lineIndex(at: 0), 0)
        XCTAssertEqual(track.lineIndex(at: 5000), 1)
        XCTAssertEqual(track.lineIndex(at: 10000), 2)
    }

    func testWithinLineStaysOnLine() {
        XCTAssertEqual(track.lineIndex(at: 4999), 0)
        XCTAssertEqual(track.lineIndex(at: 7500), 1)
    }

    func testBeyondLastLineKeepsLast() {
        XCTAssertEqual(track.lineIndex(at: 999999), 2)
    }

    func testEmptyTrack() {
        let empty = LyricTrack(lines: [])
        XCTAssertNil(empty.lineIndex(at: 0))
        XCTAssertNil(empty.line(at: 0))
        XCTAssertNil(empty.nextLine(after: 0))
    }

    // MARK: current line

    func testCurrentLineAtPositions() {
        XCTAssertEqual(track.line(at: 0)?.text, "line one")
        XCTAssertEqual(track.line(at: 4999)?.text, "line one")
        XCTAssertEqual(track.line(at: 5000)?.text, "line two")
        XCTAssertEqual(track.line(at: 12345)?.text, "line three")
    }

    func testNoCurrentLineBeforeStart() {
        XCTAssertNil(track.line(at: -1))
    }

    // MARK: next line

    func testNextLineDuringFirstLine() {
        XCTAssertEqual(track.nextLine(after: 100)?.text, "line two")
    }

    func testNextLineDuringLastLineIsNil() {
        XCTAssertNil(track.nextLine(after: 10000))
        XCTAssertNil(track.nextLine(after: 99999))
    }

    func testNextLineBeforeStartIsNil() {
        XCTAssertNil(track.nextLine(after: -1))
    }

    // MARK: progress

    func testProgressClampedToZeroBeforeStart() {
        XCTAssertEqual(track.progress(at: -100), 0, accuracy: 0.0001)
    }

    func testProgressAtEndOfTrack() {
        XCTAssertEqual(track.progress(at: 10000), 1, accuracy: 0.0001)
        XCTAssertEqual(track.progress(at: 50000), 1, accuracy: 0.0001)
    }

    func testProgressMidway() {
        XCTAssertEqual(track.progress(at: 5000), 0.5, accuracy: 0.0001)
    }

    // MARK: parser + fixture

    func testParserParsesTsvFixture() throws {
        let fixture = FixtureLoader.loadDemoTrack()
        XCTAssertFalse(fixture.lines.isEmpty)
        XCTAssertGreaterThanOrEqual(fixture.lines.count, 8)
        // fixture must be sorted and strictly increasing
        let starts = fixture.lines.map(\.startMs)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertEqual(Set(starts).count, starts.count)
    }

    func testParserSkipsBlankAndMalformedRows() {
        let raw = "0\thello\n\nbadrow\n\t\n5000\tworld\n"
        let lines = TimedLyricParser.parse(raw)
        XCTAssertEqual(lines.map(\.text), ["hello", "world"])
        XCTAssertEqual(lines.map(\.startMs), [0, 5000])
    }

    func testFixtureSnapshotFlow() throws {
        let fixture = FixtureLoader.loadDemoTrack()
        let snapshot = LyricSnapshotBuilder.snapshot(
            track: fixture, title: "Demo", artist: "Caraoke", positionMs: 7000, isPlaying: true
        )
        XCTAssertEqual(snapshot.currentLine, fixture.line(at: 7000)?.text)
        XCTAssertEqual(snapshot.nextLine, fixture.nextLine(after: 7000)?.text)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.progress, fixture.progress(at: 7000), accuracy: 0.0001)
        XCTAssertEqual(snapshot.status, .playing)
        XCTAssertEqual(snapshot.positionMs, 7000)
        XCTAssertEqual(snapshot.durationMs, fixture.durationMs)
    }

    // MARK: Ride Mode

    func testRideModeStartStopTracksDuration() {
        var model = RideModeModel()
        XCTAssertFalse(model.isOn)
        model.start(at: 1000)
        XCTAssertTrue(model.isOn)
        model.stop(at: 7000)
        XCTAssertFalse(model.isOn)
        XCTAssertEqual(model.totalRideMs, 6000)
    }

    func testRideModeIgnoresDoubleStart() {
        var model = RideModeModel()
        model.start(at: 1000)
        model.start(at: 5000)
        model.stop(at: 9000)
        XCTAssertEqual(model.totalRideMs, 8000)
    }

    func testRideModeStopWithoutStartIsNoop() {
        var model = RideModeModel()
        model.stop(at: 100)
        XCTAssertEqual(model.totalRideMs, 0)
    }

    func testRideModeResetStats() {
        var model = RideModeModel()
        model.start(at: 0)
        model.stop(at: 5000)
        model.resetStats()
        XCTAssertEqual(model.totalRideMs, 0)
    }
    // MARK: Display segmentation

    func testSegmentedDisplayTextBreaksAtWholeWords() {
        let text = "I guess I got what I prayed for"
        let shown = LyricSegmenter.segmentedDisplayText(for: text)
        XCTAssertTrue(shown.split(separator: "\n").allSatisfy {
            $0.split(whereSeparator: { $0.isWhitespace }).count <= 5
        })
        XCTAssertEqual(shown.replacingOccurrences(of: "\n", with: ""), text)
    }

    func testSegmentedDisplayTextBoundsLongLines() {
        let shown = LyricSegmenter.segmentedDisplayText(for: "Now you're in my bed forever and ever tonight")
        XCTAssertTrue(shown.split(separator: "\n").allSatisfy {
            $0.split(whereSeparator: { $0.isWhitespace }).count <= 5
        })
    }

    func testSegmentedDisplayTextPreservesPunctuationEmojiWhitespaceAndTokens() {
        XCTAssertEqual(LyricSegmenter.segmentedDisplayText(for: "Great balls of fire, …"), "Great balls of fire, …")
        XCTAssertEqual(LyricSegmenter.segmentedDisplayText(for: "🎶 everywhere 🎶"), "🎶 everywhere 🎶")
        let spaced = "  a  b\tc d e f"
        XCTAssertEqual(LyricSegmenter.segmentedDisplayText(for: spaced).replacingOccurrences(of: "\n", with: ""), spaced)
        XCTAssertEqual(LyricSegmenter.segmentedDisplayText(for: "a b c d e\nf g h i j"), "a b c d e\nf g h i j")
        XCTAssertEqual(LyricSegmenter.segmentedDisplayText(for: "supercalifragilisticexpialidocious"), "supercalifragilisticexpialidocious")
    }

    @MainActor
    func testSpotifyOlderPollCannotOverwriteNewerPoll() async {
        let firstStarted = expectation(description: "first request started")
        let protocolState = SpotifyPollProtocol.State(firstStarted: firstStarted)
        SpotifyPollProtocol.state = protocolState
        defer { SpotifyPollProtocol.state = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpotifyPollProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let source = SpotifySource(session: session, tokenProvider: SpotifyTestToken())
        var titles: [String] = []
        let subscription = source.statePublisher.sink { state in
            if let title = state?.title { titles.append(title) }
        }
        let older = Task { await source.pollOnce() }
        await fulfillment(of: [firstStarted], timeout: 5)
        _ = await source.pollOnce()
        protocolState.finishFirst()
        _ = await older.value
        XCTAssertEqual(titles, ["new"])
        withExtendedLifetime(subscription) {}
    }

}

@MainActor
private final class SpotifyTestToken: SpotifyTokenProviding {
    var isConnected: Bool { true }
    func validAccessToken() async throws -> String { "token" }
    func handleUnauthorized() async {}
}

private final class SpotifyPollProtocol: URLProtocol {
    final class State {
        let firstStarted: XCTestExpectation
        private let lock = NSLock()
        private var first: SpotifyPollProtocol?
        private var count = 0

        init(firstStarted: XCTestExpectation) { self.firstStarted = firstStarted }

        func start(_ request: SpotifyPollProtocol) {
            lock.lock()
            count += 1
            let isFirst = count == 1
            if isFirst { first = request }
            lock.unlock()
            if isFirst { firstStarted.fulfill() } else { request.respond(title: "new") }
        }

        func finishFirst() {
            lock.lock()
            let request = first
            first = nil
            lock.unlock()
            request?.respond(title: "old")
        }
    }

    static var state: State?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state?.start(self) }
    override func stopLoading() {}

    private func respond(title: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = Data("{\"item\":{\"name\":\"\(title)\"},\"is_playing\":true}".utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
