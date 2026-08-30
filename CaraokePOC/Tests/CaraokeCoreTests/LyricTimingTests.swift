import XCTest
@testable import CaraokeCore

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
}
