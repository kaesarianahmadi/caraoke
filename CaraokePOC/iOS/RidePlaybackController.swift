import Foundation
import Combine
import WidgetKit

// The REAL playback pipeline, wired end-to-end:
//
//   AppleMusicSource ──┐
//                      ├─ NowPlayingCoordinator ─ SyncEngine ─┬─ UI lines
//   SpotifySource ─────┘        (arbiter)      (extrapolate)  └─ Live Activity
//                                        │
//                         track change → LRCLIBLyricsRepository (cached)
//
// Gated behind `RideModeViewModel.useSimulatedPlayback` until Phase C
// validates the real path on hardware (see research/background-update-
// strategy.md for the background-update decision this depends on).

@MainActor
final class RidePlaybackController: ObservableObject {

    @Published private(set) var currentLine = ""
    @Published private(set) var nextLine: String?
    /// Track identity + playback clock the home screen's player card shows.
    @Published private(set) var trackTitle = ""
    @Published private(set) var trackArtist = ""
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs: Int?

    /// Lyrics load state — drives the tile's status badge (design states).
    private(set) var lyricState: LyricStatus = .idle

    private let activity: CaraokeActivityController
    private let audioKeeper = RideAudioKeeper()
    private let provider: LRCLIBLyricsProvider
    private let apple: AppleMusicSource
    let spotifyAuth: SpotifyAuth
    private let spotify: SpotifySource
    private let coordinator: NowPlayingCoordinator
    private let engine: SyncEngine
    private let relay: LyricsRelayClient
    private var cancellables: Set<AnyCancellable> = []
    private var lastLyricsKey: String?
    /// Last lyric track handed to the relay — re-registration on seek/pause
    /// reuses its schedule without refetching.
    private var lastTrack: LyricTrack?
    private var lastRelayStartMs: Int?
    private var lastRelayIsPlaying: Bool?
    private var lastRelayRegisterAt: Date?
    /// A re-registration is triggered when the track's virtual start moves by
    /// more than this (a real seek). Smaller drift is polling jitter and the
    /// relay schedule tolerates it; the app-side engine snaps at 2 s.
    private let relaySeekThresholdMs = 3000
    /// Seek-jitter coalescing window: while this many seconds pass since the
    /// last register, a startMoved-only re-registration waits. Play/pause
    /// flips bypass the window entirely.
    private let relaySeekCoalesceSeconds: TimeInterval = 5

    init(activity: CaraokeActivityController,
         provider: LRCLIBLyricsProvider = LRCLIBLyricsProvider(),
         spotifyAuth: SpotifyAuth? = nil,
         relay: LyricsRelayClient? = nil) {
        self.activity = activity
        self.provider = provider
        // Created here (MainActor-isolated init) — a default-argument
        // expression would run in a nonisolated context and fail to call the
        // @MainActor initializer.
        self.relay = relay ?? LyricsRelayClient()
        self.apple = AppleMusicSource()
        self.spotifyAuth = spotifyAuth ?? SpotifyAuth()
        self.spotify = SpotifySource(tokenProvider: self.spotifyAuth)
        self.coordinator = NowPlayingCoordinator(
            applePublisher: apple.statePublisher,
            spotifyPublisher: spotify.statePublisher,
            pin: .auto
        )
        self.engine = SyncEngine()
        // CombineLatest3 emits only after ALL inputs fire at least once — a
        // gated Spotify source must still announce its idle state or Apple
        // Music updates would be silently swallowed.
        spotify.emitIdle()
        // Relay (mechanism #2): the activity's push token + the lyric
        // schedule together arm the background push session.
        activity.onPushToken = { [weak self] token in
            Task { @MainActor [weak self] in self?.relay.setPushToken(token) }
        }
        self.relay.onStatus = { [weak activity] message in
            activity?.onDiagnostic?(message)
        }
        wire()
    }

    func start() {
        audioKeeper.start()
        apple.start()
        if FeatureFlags.spotifyEnabled {
            spotify.start()
        }
        engine.startTicking()
    }

    func stop() {
        apple.stop()
        spotify.stop()
        engine.stopTicking()
        audioKeeper.stop()
        relay.end()
        let store = UserDefaults(suiteName: "group.app.caraoke") ?? UserDefaults.standard
        store.removeObject(forKey: "widget_title")
        store.set("idle", forKey: "widget_status")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setSourcePin(_ pin: SourcePin) {
        coordinator.pin = pin
    }

    private func wire() {
        coordinator.statePublisher
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)
        engine.positionSubject
            .sink { [weak self] position in self?.render(position) }
            .store(in: &cancellables)
    }

    /// Feeds every arbitrated playback report into the sync engine, and — on
    /// a real track change — fetches synced lyrics (cached by the provider).
    /// On the same track it re-arms the relay when the player seeks or
    /// pauses/resumes (the relay otherwise holds a stale wall-clock schedule
    /// and overwrites the tile with out-of-sync lines).
    private func handle(_ state: NowPlayingState?) {
        engine.apply(state)
        guard let state else { return }
        let key = TrackMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        guard key == lastLyricsKey else {
            lastLyricsKey = key
            let signature = TrackSignature(
                title: state.title, artist: state.artist,
                album: state.album, durationMs: state.durationMs
            )
            lyricState = .loading
            Task { [weak self] in
                guard let self else { return }
                guard let track = try? await self.provider.lyrics(for: signature) else {
                    self.lyricState = .noLyrics
                    return
                }
                self.lastTrack = track
                self.engine.setLyrics(
                    track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text) }
                )
                self.armRelay(track: track)
                self.lyricState = .playing // render() refines play vs pause
            }
            return
        }
        // Same track: re-register only if a seek or play/pause flip moved the
        // relay's timeline (the 1 s poll makes this near-instant).
        guard lastTrack != nil else { return }
        rearmRelayIfNeeded()
    }

    /// Arms the background relay with the lyric schedule + the track's
    /// wall-clock start (anchor.capturedAt - positionMs). The relay client
    /// holds it until the activity's push token arrives, then POSTs once.
    private func armRelay(track: LyricTrack) {
        guard let anchor = engine.anchor else { return }
        let startEpochMs = Int(anchor.capturedAt.timeIntervalSince1970 * 1000)
            - anchor.positionMs
        lastTrack = track
        lastRelayStartMs = startEpochMs
        lastRelayIsPlaying = anchor.isPlaying
        lastRelayRegisterAt = Date()
        relay.register(
            trackTitle: anchor.title,
            trackArtist: anchor.artist,
            lines: track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text) },
            startEpochMs: startEpochMs,
            durationMs: anchor.durationMs,
            isPlaying: anchor.isPlaying
        )
    }

    /// Deduped re-registration: only a real timeline change (seek > 3 s) or a
    /// play/pause flip POSTs. Flips (pause ↔ resume) are always critical and
    /// re-register immediately — never rate-limited. Seek drift (startMoved)
    /// is coalesced by a small window because Spotify's poll can wobble the
    /// derived start by seconds; the deviation persists in the anchor until a
    /// register lands, so a real seek still corrects a poll or two later.
    private func rearmRelayIfNeeded() {
        guard let anchor = engine.anchor, let track = lastTrack else { return }
        let startEpochMs = Int(anchor.capturedAt.timeIntervalSince1970 * 1000)
            - anchor.positionMs
        let startMoved = lastRelayStartMs.map { abs($0 - startEpochMs) > relaySeekThresholdMs } ?? false
        let playingChanged = lastRelayIsPlaying != anchor.isPlaying
        guard startMoved || playingChanged else { return }
        // Paused timeline is frozen: positionMs doesn't move, so the derived
        // startEpochMs drifts with capturedAt on every idle poll. A paused →
        // paused poll has nothing new to tell the relay (the pause flip
        // already registered the frozen schedule).
        if !anchor.isPlaying && lastRelayIsPlaying == false { return }
        // The seek-jitter coalescing window applies only to startMoved;
        // play/pause flips pass through immediately.
        if startMoved, let last = lastRelayRegisterAt,
           Date().timeIntervalSince(last) < relaySeekCoalesceSeconds {
            return
        }
        armRelay(track: track)
    }

    /// Renders the extrapolated position: UI lines + Live Activity snapshot.
    private func render(_ position: LyricsPosition?) {
        guard let position else { return }
        currentLine = position.currentLine ?? ""
        nextLine = position.nextLine
        let anchor = engine.anchor
        // Design status ladder: fetch in progress → "loading"; fetch failed →
        // "no lyrics"; otherwise playing / paused from the clock.
        let state: LyricStatus
        switch lyricState {
        case .loading, .noLyrics:
            state = lyricState
        default:
            state = position.isPlaying ? .playing : .paused
        }
        let snapshot = LyricSnapshot(
            title: anchor?.title ?? "",
            artist: anchor?.artist ?? "",
            currentLine: position.currentLine ?? "",
            nextLine: position.nextLine,
            isPlaying: position.isPlaying,
            progress: position.trackProgress,
            status: state,
            positionMs: position.positionMs,
            durationMs: anchor?.durationMs,
            lineIndex: position.lineIndex
        )
        trackTitle = anchor?.title ?? ""
        trackArtist = anchor?.artist ?? ""
        self.positionMs = position.positionMs
        self.durationMs = anchor?.durationMs
        activity.sync(snapshot: snapshot)
        syncWidget(snapshot: snapshot)
    }

    private func syncWidget(snapshot: LyricSnapshot) {
        let store = UserDefaults(suiteName: "group.app.caraoke") ?? UserDefaults.standard
        store.set(snapshot.title, forKey: "widget_title")
        store.set(snapshot.artist, forKey: "widget_artist")
        store.set(snapshot.currentLine, forKey: "widget_current_line")
        store.set(snapshot.nextLine, forKey: "widget_next_line")
        store.set(snapshot.isPlaying, forKey: "widget_is_playing")
        store.set(snapshot.progress, forKey: "widget_progress")
        store.set(snapshot.status.rawValue, forKey: "widget_status")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
