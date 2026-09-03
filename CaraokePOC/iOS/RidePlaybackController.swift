import Foundation
import Combine

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
            spotifyPublisher: spotify.statePublisher
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
            Task { [weak self] in
                guard let track = try? await self?.provider.lyrics(for: signature) else { return }
                self?.lastTrack = track
                self?.engine.setLyrics(
                    track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text) }
                )
                self?.armRelay(track: track)
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

    /// Deduped re-registration: only a real timeline change (seek > 3 s or a
    /// play/pause flip) POSTs, so the 1 s poll does not spam the relay.
    private func rearmRelayIfNeeded() {
        guard let anchor = engine.anchor, let track = lastTrack else { return }
        let startEpochMs = Int(anchor.capturedAt.timeIntervalSince1970 * 1000)
            - anchor.positionMs
        let startMoved = lastRelayStartMs.map { abs($0 - startEpochMs) > relaySeekThresholdMs } ?? false
        let playingChanged = lastRelayIsPlaying != anchor.isPlaying
        guard startMoved || playingChanged else { return }
        // Rate guard: Spotify's 5 s poll can wobble startEpochMs by seconds
        // (HTTP latency), which without this would re-register every poll and
        // burn the activity's push budget. The deviation persists in the
        // anchor until a register lands, so the retry fires a poll or two
        // later — seek/pause fixes still apply within seconds.
        let now = Date()
        if let last = lastRelayRegisterAt, now.timeIntervalSince(last) < 5 { return }
        armRelay(track: track)
    }

    /// Renders the extrapolated position: UI lines + Live Activity snapshot.
    private func render(_ position: LyricsPosition?) {
        guard let position else { return }
        currentLine = position.currentLine ?? ""
        nextLine = position.nextLine
        let snapshot = LyricSnapshot(
            title: engine.anchor?.title ?? "",
            artist: engine.anchor?.artist ?? "",
            currentLine: position.currentLine ?? "",
            nextLine: position.nextLine,
            isPlaying: position.isPlaying,
            progress: position.trackProgress,
            lineIndex: position.lineIndex
        )
        activity.sync(snapshot: snapshot)
    }
}
