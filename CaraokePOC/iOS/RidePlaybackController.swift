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
    private let provider: LRCLIBLyricsProvider
    private let apple: AppleMusicSource
    let spotifyAuth: SpotifyAuth
    private let spotify: SpotifySource
    private let coordinator: NowPlayingCoordinator
    private let engine: SyncEngine
    private let relay: LyricsRelayClient
    private var cancellables: Set<AnyCancellable> = []
    private var lastLyricsKey: String?

    init(activity: CaraokeActivityController,
         provider: LRCLIBLyricsProvider = LRCLIBLyricsProvider(),
         spotifyAuth: SpotifyAuth? = nil,
         relay: LyricsRelayClient = LyricsRelayClient()) {
        self.activity = activity
        self.provider = provider
        self.relay = relay
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
        wire()
    }

    func start() {
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
    private func handle(_ state: NowPlayingState?) {
        engine.apply(state)
        guard let state else { return }
        let key = TrackMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        guard key != lastLyricsKey else { return }
        lastLyricsKey = key
        let signature = TrackSignature(
            title: state.title, artist: state.artist,
            album: state.album, durationMs: state.durationMs
        )
        Task { [weak self] in
            guard let track = try? await self?.provider.lyrics(for: signature) else { return }
            self?.engine.setLyrics(
                track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text) }
            )
            self?.armRelay(track: track)
        }
    }

    /// Arms the background relay with the lyric schedule + the track's
    /// wall-clock start (anchor.capturedAt - positionMs). The relay client
    /// holds it until the activity's push token arrives, then POSTs once.
    private func armRelay(track: LyricTrack) {
        guard let anchor = engine.anchor else { return }
        let startEpochMs = Int(anchor.capturedAt.timeIntervalSince1970 * 1000)
            - anchor.positionMs
        relay.register(
            trackTitle: anchor.title,
            trackArtist: anchor.artist,
            lines: track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text) },
            startEpochMs: startEpochMs,
            durationMs: anchor.durationMs
        )
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
