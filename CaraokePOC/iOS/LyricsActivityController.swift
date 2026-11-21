import ActivityKit
import Foundation
import os

/// Ported from DriveVerse `LiveActivityController` (MIT © 2026 Praveet Gupta,
/// see THIRD_PARTY_NOTICES.md), adapted to Caraoke's `LyricSnapshot` model and
/// renamed. This replaces the PoC's original thin start/update/end wrapper.
///
/// One activity spans the whole ride. Track changes update its content;
/// only explicit start/stop requests change its lifecycle.
@MainActor
final class CaraokeActivityController {
    /// Rapid line changes are coalesced (never dropped) to one update per
    /// this interval; the newest line always lands, at worst this late.
    /// Track changes and play/pause flips always send immediately.
    static let minLineUpdateInterval: TimeInterval = 0.25

    private static let log = Logger(subsystem: "com.caraoke.poc", category: "activity")

    private var activity: Activity<LyricsActivityAttributes>?
    private var lifecycleTask: Task<Void, Never>?
    private var startSnapshot: LyricSnapshot?
    private var needsTeardown = false
    private var policy = ActivityUpdatePolicy()
    private var throttle = ActivityUpdateThrottle(minInterval: CaraokeActivityController.minLineUpdateInterval)
    private var stateWatcher: Task<Void, Never>?
    private var pushTokenTask: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    private var pendingContent: LyricsActivityAttributes.ContentState?
    private var lastSentTrackKey: String?
    private var lastSentIsPlaying: Bool?

    /// Delivers the activity's APNs push token as it arrives/rotates, so the
    /// relay client can register the app-side session (mechanism #2).
    var onPushToken: ((Data) -> Void)?

    /// Human-readable status for the ride screen. Every path that could
    /// silently prevent the activity from appearing reports here — a no-show
    /// with zero feedback cost us a device-test round-trip (build 4).
    var onDiagnostic: ((String) -> Void)?
    var onAvailabilityChange: ((Bool, String?) -> Void)?

    var isActive: Bool { activity?.activityState == .active }

    private static func canReuse(_ activity: Activity<LyricsActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .pending, .stale: return true
        case .ended, .dismissed: return false
        @unknown default: return false
        }
    }

    /// True when the system-level Live Activities toggle for this app is off
    /// (design state D) — the Home gate banner and "Needs attention" row key
    /// off this.
    var authorizationDenied: Bool {
        !ActivityAuthorizationInfo().areActivitiesEnabled
    }

    init() {}

    /// Single entry point, called on every snapshot change. Gates everything
    /// through policy + throttle. Playback pauses do NOT end the activity
    /// (the passenger may pause at a red light; the paused snapshot keeps the
    /// tile accurate instead). It ends only when Ride Mode stops (endNow) or
    /// the system ends it.
    func sync(snapshot: LyricSnapshot) {
        if startSnapshot != nil { startSnapshot = snapshot }
        guard let activity, Self.canReuse(activity), !needsTeardown else { return }
        let key = Self.trackKey(for: snapshot)
        guard policy.shouldUpdate(trackKey: key, lineIndex: snapshot.lineIndex, isPlaying: snapshot.isPlaying) else { return }

        let critical = key != lastSentTrackKey || snapshot.isPlaying != lastSentIsPlaying
        lastSentTrackKey = key
        lastSentIsPlaying = snapshot.isPlaying
        let content = Self.content(from: snapshot)

        switch throttle.decide(critical: critical, now: Date()) {
        case .sendNow:
            cancelPendingUpdate() // superseded by newer content
            Task { [weak self] in
                guard self?.activity?.id == activity.id else { return }
                await activity.update(ActivityContent(state: content,
                                                      staleDate: Self.staleDate(for: snapshot, at: Date())))
            }
        case .coalesce(let fireIn):
            pendingContent = content
            armPendingUpdate(after: fireIn, on: activity)
        }
    }

    /// Eager, always-on start: request the Live Activity the moment Ride Mode
    /// turns on, with a placeholder. Lyrics fill in as soon as a song plays —
    /// the user no longer has to play a song BEFORE enabling Ride Mode, and
    /// the tile persists across backgrounding (requesting here happens in the
    /// foreground where Activity.request is allowed).
    func startIdle() {
        if let activity {
            if Self.canReuse(activity) { return }
            detach()
        }
        guard startSnapshot == nil else { return }
        startSnapshot = LyricSnapshot(
            title: "Ride Mode",
            artist: "",
            currentLine: "Play a song to see lyrics",
            nextLine: nil,
            isPlaying: false,
            progress: 0,
            status: .idle,
            positionMs: 0,
            durationMs: nil,
            lineIndex: nil
        )
        reconcileLifecycle()
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
            await activity.update(ActivityContent(state: content,
                                                  staleDate: Self.staleDate(forContent: content)))
        }
    }

    private func cancelPendingUpdate() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingContent = nil
    }

    private func reconcileLifecycle() {
        guard lifecycleTask == nil else { return }
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            defer { self.lifecycleTask = nil }
            while self.needsTeardown || self.startSnapshot != nil {
                if self.needsTeardown {
                    self.needsTeardown = false
                    for activity in Activity<LyricsActivityAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                    continue
                }
                await self.beginSession()
            }
        }
    }

    private func beginSession() async {
        let activities = Activity<LyricsActivityAttributes>.activities
        let existing = activities.first { $0.activityState == .active } ?? activities.first(where: Self.canReuse)
        for other in activities where other.id != existing?.id && other.activityState != .dismissed {
            await other.end(nil, dismissalPolicy: .immediate)
            if needsTeardown { return }
        }

        guard !needsTeardown, let snapshot = startSnapshot else { return }
        startSnapshot = nil
        guard !authorizationDenied else {
            onAvailabilityChange?(false, nil)
            return
        }
        if let existing, Self.canReuse(existing) {
            attach(existing, snapshot: snapshot)
            if existing.activityState != .pending {
                await existing.update(ActivityContent(state: Self.content(from: snapshot),
                                                      staleDate: Self.staleDate(for: snapshot, at: Date())))
            }
            return
        }
        do {
            // pushType: .token makes the activity receive an APNs push token
            // that a server can use to UPDATE it (mechanism #2 relay). The
            // widget is unchanged — a pushed ContentState renders exactly like
            // a local update. (`.liveActivity` is only for push-to-START.)
            let requested: Activity<LyricsActivityAttributes>
            do {
                requested = try Activity.request(
                    attributes: LyricsActivityAttributes(),
                    content: ActivityContent(state: Self.content(from: snapshot),
                                             staleDate: Self.staleDate(for: snapshot, at: Date())),
                    pushType: .token
                )
                onDiagnostic?("Live Activity started (push-capable)")
            } catch {
                requested = try Activity.request(
                    attributes: LyricsActivityAttributes(),
                    content: ActivityContent(state: Self.content(from: snapshot),
                                             staleDate: Self.staleDate(for: snapshot, at: Date()))
                )
                onDiagnostic?("Live Activity started (no push: \(error.localizedDescription))")
            }
            attach(requested, snapshot: snapshot)
        } catch {
            Self.log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
            onAvailabilityChange?(false, "Couldn’t start the Live Activity. Try switching Live Lyrics off and back on.")
        }
    }

    private func attach(_ activity: Activity<LyricsActivityAttributes>, snapshot: LyricSnapshot) {
        self.activity = activity
        watch(activity)
        observePushToken(activity)
        throttle.noteSent(now: Date())
        let key = Self.trackKey(for: snapshot)
        lastSentTrackKey = key
        lastSentIsPlaying = snapshot.isPlaying
        policy.seed(trackKey: key, lineIndex: snapshot.lineIndex, isPlaying: snapshot.isPlaying)
        reportState(activity.activityState)
    }

    /// Streams the activity's push token (APNs tokens rotate; a fresh token
    /// invalidates the old one, so the relay must re-register on each emit).
    /// `pushTokenUpdates` is the async sequence; `pushToken` is a one-shot
    /// `Data?` and NOT iterable.
    private func observePushToken(_ requested: Activity<LyricsActivityAttributes>) {
        pushTokenTask?.cancel()
        pushTokenTask = Task { [weak self] in
            for await token in requested.pushTokenUpdates {
                guard !Task.isCancelled, let self, self.activity?.id == requested.id else { return }
                self.onPushToken?(token)
            }
        }
    }

    /// The system can end or dismiss the activity without asking us (user
    /// swipe, system policy). Without this watcher we'd keep "updating" a
    /// corpse while believing everything is fine.
    private func watch(_ requested: Activity<LyricsActivityAttributes>) {
        stateWatcher?.cancel()
        stateWatcher = Task { [weak self] in
            for await state in requested.activityStateUpdates {
                guard !Task.isCancelled, let self, self.activity?.id == requested.id else { return }
                self.reportState(state)
                if state == .ended || state == .dismissed {
                    Self.log.warning("activity ended outside the app — reopen Caraoke to restart Ride Mode")
                    self.detach()
                    return
                }
            }
        }
    }

    private func reportState(_ state: ActivityState) {
        switch state {
        case .active: onAvailabilityChange?(true, nil)
        case .pending: onAvailabilityChange?(false, nil)
        case .stale: onAvailabilityChange?(false, "Live Activity is out of date. Keep Caraoke open to refresh it.")
        case .ended, .dismissed: onAvailabilityChange?(false, "Live Activity ended. Switch Live Lyrics off and back on to restart it.")
        @unknown default: onAvailabilityChange?(false, nil)
        }
    }

    func endNow() {
        startSnapshot = nil
        needsTeardown = true
        detach()
        onAvailabilityChange?(false, nil)
        reconcileLifecycle()
    }

    func waitForLifecycle() async {
        await lifecycleTask?.value
    }

    private func detach() {
        stateWatcher?.cancel()
        stateWatcher = nil
        pushTokenTask?.cancel()
        pushTokenTask = nil
        cancelPendingUpdate()
        activity = nil
        policy.reset()
    }

    // MARK: - Internals

    private static func trackKey(for snapshot: LyricSnapshot) -> String {
        "\(snapshot.title)|\(snapshot.artist)"
    }

    private static func content(from snapshot: LyricSnapshot) -> LyricsActivityAttributes.ContentState {
        let safeProgress = snapshot.progress.isFinite ? max(0, min(1, snapshot.progress)) : 0
        return LyricsActivityAttributes.ContentState(
            title: snapshot.title,
            artist: snapshot.artist,
            currentLine: snapshot.currentLine,
            previousLines: Array(snapshot.previousLines.suffix(2)),
            nextLine: snapshot.nextLine,
            upcomingLines: Array(snapshot.upcomingLines.prefix(2)),
            isPlaying: snapshot.isPlaying,
            progress: safeProgress,
            status: snapshot.status.rawValue,
            positionMs: snapshot.positionMs,
            durationMs: snapshot.durationMs,
            boldText: UserDefaults.standard.object(forKey: AppearanceSettings.boldTextKey) as? Bool ?? true
        )
    }

    /// The moment this content stops being trustworthy. Coverage can arrive from
    /// two directions — the app process while it is alive, and the relay's APNs
    /// pushes while it is not — so the budget is shared by both.
    ///
    /// Why it matters: every update used to be sent with `staleDate: nil`, which
    /// declares the content permanently valid. A stalled activity then looked
    /// live to the system *and* to the user — no dimming, no refresh, nothing on
    /// screen saying the lyrics had stopped. With a bounded date the system fades
    /// content when updates genuinely stop, so a freeze becomes visible instead
    /// of silent.
    ///
    /// While playing the activity is re-fed within a line or two (the relay
    /// pushes per line, the app coalesces to 1.5 s), so the grace is generous —
    /// fading a healthy activity mid-song would be its own bug. It is still
    /// bounded by the track's remaining time: a content state that outlives its
    /// own track is certainly wrong. A paused activity is deliberately kept alive
    /// (a red-light pause is minutes, not seconds) but must not claim freshness
    /// forever if the app dies while paused.
    private static func staleDate(forContent content: LyricsActivityAttributes.ContentState,
                                  at now: Date = Date()) -> Date {
        let grace: TimeInterval
        if content.isPlaying {
            var cap: TimeInterval = 90
            if let duration = content.durationMs, let positionMs = content.positionMs, duration > 0 {
                let remaining = (Double(duration) - Double(positionMs)) / 1000.0
                cap = min(cap, max(remaining + 30, 20))
            }
            grace = cap
        } else {
            grace = 600
        }
        return now.addingTimeInterval(grace)
    }

    private static func staleDate(for snapshot: LyricSnapshot, at now: Date) -> Date {
        staleDate(forContent: content(from: snapshot), at: now)
    }
}
