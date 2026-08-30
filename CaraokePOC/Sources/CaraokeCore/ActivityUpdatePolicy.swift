import Foundation

/// Ported from DriveVerse `LiveActivityUpdatePolicy` (MIT © 2026 Praveet Gupta,
/// see THIRD_PARTY_NOTICES.md), renamed for Caraoke.
///
/// Gate for Activity.update calls: update only when the track, current line
/// index, or play/pause state changes — never on every timer tick. Without
/// this, a 1 s playback poll would re-serialize an unchanged ContentState
/// every second for the whole ride.
/// Pure value type so the policy is unit-testable without ActivityKit.
struct ActivityUpdatePolicy {
    private struct Snapshot: Equatable {
        var trackKey: String
        var lineIndex: Int?
        var isPlaying: Bool
    }

    private var last: Snapshot?

    mutating func shouldUpdate(trackKey: String, lineIndex: Int?, isPlaying: Bool) -> Bool {
        let snapshot = Snapshot(trackKey: trackKey, lineIndex: lineIndex, isPlaying: isPlaying)
        guard snapshot != last else { return false }
        last = snapshot
        return true
    }

    /// Call after starting a fresh activity whose initial content already
    /// reflects the given state, or after ending one.
    mutating func seed(trackKey: String, lineIndex: Int?, isPlaying: Bool) {
        last = Snapshot(trackKey: trackKey, lineIndex: lineIndex, isPlaying: isPlaying)
    }

    mutating func reset() {
        last = nil
    }
}
