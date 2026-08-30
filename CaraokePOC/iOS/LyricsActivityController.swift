import ActivityKit
import Foundation
import os

/// Ported from DriveVerse `LiveActivityController` (MIT © 2026 Praveet Gupta,
/// see THIRD_PARTY_NOTICES.md), adapted to Caraoke's `LyricSnapshot` model and
/// renamed. This replaces the PoC's original thin start/update/end wrapper.
///
/// One activity spans the whole ride: iOS refuses Activity.request from a
/// backgrounded app, so an end-and-restart-per-track design loses the tile on
/// every backgrounded song change. Track changes are plain updates (allowed
/// from the background); the activity ends when Ride Mode stops, or after the
/// no-playback grace period once real pause support lands. On iOS 26 the
/// Lock Screen presentation mirrors onto CarPlay.
@MainActor
final class CaraokeActivityController {
    /// Grace period with no playing snapshot before the activity ends.
    static let endDelay: TimeInterval = 30
    /// Rapid line changes are coalesced (never dropped) to one update per
    /// this interval; the newest line always lands, at worst this late.
    /// Track changes and play/pause flips always send immediately.
    static let minLineUpdateInterval: TimeInterval = 1.5

    private static let log = Logger(subsystem: "com.caraoke.poc", category: "activity")

    private var activity: Activity<LyricsActivityAttributes>?
    private var policy = ActivityUpdatePolicy()
    private var throttle = ActivityUpdateThrottle(minInterval: CaraokeActivityController.minLineUpdateInterval)
    private var endTask: Task<Void, Never>?
    private var stateWatcher: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    private var pendingContent: LyricsActivityAttributes.ContentState?
    private var lastSentTrackKey: String?
    private var lastSentIsPlaying: Bool?

    var isActive: Bool { activity != nil }

    init() {
        // Clean up activities orphaned by a previous app termination.
        Task {
            for stale in Activity<LyricsActivityAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Single entry point, called on every snapshot change. Starts the
    /// session activity on the first playing snapshot (requesting from the
    /// foreground), then gates everything through policy + throttle.
    func sync(snapshot: LyricSnapshot) {
        if snapshot.isPlaying {
            cancelScheduledEnd()
        } else {
            scheduleEnd()
        }

        let key = Self.trackKey(for: snapshot)
        guard policy.shouldUpdate(trackKey: key, lineIndex: snapshot.lineIndex, isPlaying: snapshot.isPlaying) else { return }

        guard let activity else {
            // First start needs a playing snapshot. In this PoC every ride is
            // foregrounded; the intent path (RideModeIntents) will cover the
            // background start once real playback lands.
            guard snapshot.isPlaying else { return }
            beginSession(snapshot: snapshot)
            return
        }

        let critical = key != lastSentTrackKey || snapshot.isPlaying != lastSentIsPlaying
        lastSentTrackKey = key
        lastSentIsPlaying = snapshot.isPlaying
        let content = Self.content(from: snapshot)

        switch throttle.decide(critical: critical, now: Date()) {
        case .sendNow:
            cancelPendingUpdate() // superseded by newer content
            Task {
                await activity.update(ActivityContent(state: content, staleDate: nil))
            }
        case .coalesce(let fireIn):
            pendingContent = content
            armPendingUpdate(after: fireIn, on: activity)
        }
    }

    /// Trailing edge of the throttle: deliver the newest coalesced content
    /// once the spacing interval elapses, so no line change is ever lost.
    private func armPendingUpdate(after delay: TimeInterval, on activity: Activity<LyricsActivityAttributes>) {
        guard pendingTask == nil else { return } // armed — content already replaced
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let content = self.pendingContent else { return }
            self.pendingContent = nil
            self.pendingTask = nil
            self.throttle.noteSent(now: Date())
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    private func cancelPendingUpdate() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingContent = nil
    }

    private func beginSession(snapshot: LyricSnapshot) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let requested = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: ActivityContent(state: Self.content(from: snapshot), staleDate: nil)
            )
            activity = requested
            watch(requested)
            throttle.noteSent(now: Date())
            lastSentTrackKey = Self.trackKey(for: snapshot)
            lastSentIsPlaying = snapshot.isPlaying
            policy.seed(
                trackKey: lastSentTrackKey ?? "",
                lineIndex: snapshot.lineIndex,
                isPlaying: snapshot.isPlaying
            )
        } catch {
            Self.log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
            activity = nil
        }
    }

    /// The system can end or dismiss the activity without asking us (user
    /// swipe, system policy). Without this watcher we'd keep "updating" a
    /// corpse while believing everything is fine.
    private func watch(_ requested: Activity<LyricsActivityAttributes>) {
        stateWatcher?.cancel()
        stateWatcher = Task { [weak self] in
            for await state in requested.activityStateUpdates {
                guard let self, state == .ended || state == .dismissed else { continue }
                if self.activity?.id == requested.id {
                    self.activity = nil
                    self.policy.reset()
                    self.cancelPendingUpdate()
                    Self.log.warning("activity ended outside the app — reopen Caraoke to restart Ride Mode")
                }
            }
        }
    }

    func endNow() async {
        endTask?.cancel()
        endTask = nil
        stateWatcher?.cancel()
        stateWatcher = nil
        cancelPendingUpdate()
        guard let activity else { return }
        self.activity = nil
        policy.reset()
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - Internals

    private func scheduleEnd() {
        guard endTask == nil, activity != nil else { return }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.endDelay))
            guard !Task.isCancelled else { return }
            await self?.endNow()
        }
    }

    private func cancelScheduledEnd() {
        endTask?.cancel()
        endTask = nil
    }

    private static func trackKey(for snapshot: LyricSnapshot) -> String {
        "\(snapshot.title)|\(snapshot.artist)"
    }

    private static func content(from snapshot: LyricSnapshot) -> LyricsActivityAttributes.ContentState {
        LyricsActivityAttributes.ContentState(
            title: snapshot.title,
            artist: snapshot.artist,
            currentLine: snapshot.currentLine,
            nextLine: snapshot.nextLine,
            isPlaying: snapshot.isPlaying,
            progress: snapshot.progress
        )
    }
}
