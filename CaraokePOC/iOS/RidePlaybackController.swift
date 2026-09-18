import Foundation
import Combine
import UIKit
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
    @Published private(set) var currentTranslation: String?
    @Published private(set) var previousLines: [String] = []
    @Published private(set) var nextLine: String?
    @Published private(set) var upcomingLines: [String] = []
    @Published private(set) var allLines: [LyricLine] = []
    /// Track identity + playback clock the home screen's player card shows.
    @Published private(set) var trackTitle = ""
    @Published private(set) var trackArtist = ""
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs: Int?
    /// Cover art for the in-app mini player / lyrics page, plus its average
    /// colour for the widget background.
    @Published private(set) var artworkData: Data?
    private(set) var artworkColorHex: String?

    /// Active source from engine's anchor
    var currentSource: MusicSource? { engine.anchor?.source }

    /// Lyrics load state — drives the tile's status badge (design states).
    private(set) var lyricState: LyricStatus = .idle

    private let activity: CaraokeActivityController
    private let audioKeeper = RideAudioKeeper()
    private let provider: any LyricsRepository
    private let apple: AppleMusicSource
    let spotifyAuth: SpotifyAuth
    private let spotify: SpotifySource
    private let coordinator: NowPlayingCoordinator
    private let engine: SyncEngine
    private let relay: LyricsRelayClient
    private var cancellables: Set<AnyCancellable> = []
    private var lastLyricsKey: String?
    private var lyricsFetchTask: Task<Void, Never>?
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
    /// Build 42: periodic sync heartbeat to re-anchor the widget when the
    /// engine's extrapolation drifts too far from reality.
    private var syncHeartbeatTask: Task<Void, Never>?
    /// Drift beyond this triggers a widget payload rewrite + timeline reload.
    private static let syncDriftThresholdMs = 2000

    init(activity: CaraokeActivityController,
         provider: any LyricsRepository = FallbackLyricsProvider(),
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
        startSyncHeartbeat()
    }

    private var lastWidgetTitle: String?
    private var lastWidgetIsPlaying: Bool?
    private var lastWidgetStatus: String?
    private var lastWidgetSignature: String?
    private var lastWidgetArtworkHex: String?
    /// Track start in wall-clock epoch ms — only recomputed while playing, so
    /// a paused track keeps the true start the widget extrapolates from.
    private var trackStartEpochMs = 0
    private var trackStartKey: String?
    private var currentArtworkData: Data?
    private var lastArtworkKey: String?

    func stop() {
        apple.stop()
        spotify.stop()
        engine.stopTicking()
        syncHeartbeatTask?.cancel()
        syncHeartbeatTask = nil
        audioKeeper.stop()
        relay.end()
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        lastLyricsKey = nil
        lastTrack = nil
        currentArtworkData = nil
        artworkColorHex = nil
        artworkData = nil
        lastArtworkKey = nil
        lastWidgetStatus = nil
        lastWidgetSignature = nil
        lastWidgetArtworkHex = nil
        lastWidgetTitle = nil
        lastWidgetIsPlaying = nil
        trackStartEpochMs = 0
        trackStartKey = nil
        lastRelayStartMs = nil
        lastRelayIsPlaying = nil
        lastRelayRegisterAt = nil
        currentLine = ""
        currentTranslation = nil
        previousLines = []
        nextLine = nil
        upcomingLines = []
        allLines = []
        trackTitle = ""
        trackArtist = ""
        positionMs = 0
        durationMs = nil
        lyricState = .idle
        SharedWidgetStore.write(nil)
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
    ///
    /// Build 42: when the coordinator emits nil (gap between tracks), the
    /// engine anchor is reset immediately so the next track triggers a fresh
    /// search instead of carrying over the old anchor.
    private func handle(_ state: NowPlayingState?) {
        guard let state else {
            // Gap between tracks: clear anchor so the next track triggers a
            // fresh fetch and relay registration.
            if lastLyricsKey != nil {
                lastLyricsKey = nil
                lastTrack = nil
                currentLine = ""
                previousLines = []
                nextLine = nil
                upcomingLines = []
                allLines = []
                lyricState = .idle
            }
            engine.apply(nil)
            return
        }
        let key = TrackMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        let isNewTrack = key != lastLyricsKey
        if isNewTrack {
            lastLyricsKey = key
            lastTrack = nil
            lyricsFetchTask?.cancel()
            engine.setLyrics([])
            currentLine = ""
            currentTranslation = nil
            previousLines = []
            nextLine = nil
            upcomingLines = []
            allLines = []
            trackTitle = state.title
            trackArtist = state.artist
            lyricState = .loading
        }
        engine.apply(state)
        guard isNewTrack else {
            // Same track: re-register only if a seek or play/pause flip moved the
            // relay's timeline (the 1 s poll makes this near-instant).
            if lastTrack != nil {
                rearmRelayIfNeeded()
            }
            return
        }

        // Extract artwork: Apple Music supplies raw Data; Spotify provides URL
        if let data = state.artworkData, let image = UIImage(data: data) {
            setArtwork(image: image, key: key)
        } else if let urlStr = state.artworkURL, let url = URL(string: urlStr) {
            self.lastArtworkKey = key
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    guard let self, self.lastArtworkKey == key else { return }
                    self.setArtwork(image: image, key: key)
                }
            }
        } else {
            clearArtwork(key: key)
        }

        let signature = TrackSignature(
            title: state.title, artist: state.artist,
            album: state.album, durationMs: state.durationMs
        )
        lyricsFetchTask = Task { [weak self] in
            guard let self else { return }
            guard let track = try? await self.provider.lyrics(for: signature) else {
                if !Task.isCancelled {
                    self.lyricState = .noLyrics
                }
                return
            }
            guard !Task.isCancelled else { return }
            self.lastTrack = track
            self.allLines = track.lines
            self.engine.setLyrics(
                track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text, translation: $0.translation) }
            )
            self.armRelay(track: track)
            self.lyricState = .playing
            self.render(self.engine.positionSubject.value)
        }
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
        currentTranslation = position.currentTranslation
        previousLines = position.previousLines
        nextLine = position.nextLine
        upcomingLines = position.upcomingLines
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
            currentTranslation: position.currentTranslation,
            previousLines: position.previousLines,
            nextLine: position.nextLine,
            upcomingLines: position.upcomingLines,
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

    /// Writes the shared payload and asks WidgetKit to rebuild the timeline.
    ///
    /// Two deliberate limits, both learned from build 38's dead widgets:
    /// - the write is skipped unless the rendered state actually changed
    ///   (`render` runs 4×/s, and keychain writes are not free);
    /// - the reload is skipped unless the track, play state or lyric status
    ///   changed. The widget's own timeline already advances line by line, so
    ///   reloading on a timer only burned WidgetKit's daily budget.
    private func syncWidget(snapshot: LyricSnapshot) {
        let anchor = engine.anchor
        let key = TrackMatcher.signature(
            title: snapshot.title, artist: snapshot.artist, durationMs: snapshot.durationMs
        )
        if anchor?.isPlaying == true || trackStartKey != key {
            trackStartEpochMs = (Int((anchor?.capturedAt.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000))
                - (anchor?.positionMs ?? 0)
            trackStartKey = key
        }

        let widgetLines = lastTrack?.lines.map {
            SharedLyricLine(timeMs: $0.startMs, text: $0.text, translation: $0.translation)
        } ?? []

        let signature = [
            key,
            snapshot.currentLine,
            snapshot.isPlaying ? "1" : "0",
            snapshot.status.rawValue,
            String(trackStartEpochMs / 1000),
            String(widgetLines.count),
            artworkColorHex ?? "-",
        ].joined(separator: "|")
        guard signature != lastWidgetSignature else { return }
        lastWidgetSignature = signature

        let payload = SharedWidgetPayload(
            title: snapshot.title,
            artist: snapshot.artist,
            currentLine: snapshot.currentLine,
            currentTranslation: snapshot.currentTranslation,
            previousLines: snapshot.previousLines,
            nextLine: snapshot.nextLine,
            upcomingLines: snapshot.upcomingLines,
            isPlaying: snapshot.isPlaying,
            progress: snapshot.progress,
            status: snapshot.status.rawValue,
            trackStartEpochMs: trackStartEpochMs,
            durationMs: snapshot.durationMs ?? 0,
            lines: widgetLines,
            artworkData: currentArtworkData,
            artworkColorHex: artworkColorHex,
            source: anchor?.source.rawValue ?? "appleMusic"
        )
        SharedWidgetStore.write(payload)

        let isTitleChanged = snapshot.title != lastWidgetTitle
        let isPlayStateChanged = snapshot.isPlaying != lastWidgetIsPlaying
        let isStatusChanged = snapshot.status.rawValue != lastWidgetStatus
        // Artwork (and its colour) often lands a beat AFTER the track change —
        // Spotify serves it over the network — so the widget must reload again
        // or it keeps the artwork-less timeline it was first handed.
        let isArtworkChanged = artworkColorHex != lastWidgetArtworkHex
        guard isTitleChanged || isPlayStateChanged || isStatusChanged || isArtworkChanged else { return }
        lastWidgetTitle = snapshot.title
        lastWidgetIsPlaying = snapshot.isPlaying
        lastWidgetStatus = snapshot.status.rawValue
        lastWidgetArtworkHex = artworkColorHex
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Artwork

    private func setArtwork(image: UIImage, key: String) {
        let thumb = Self.thumbnail(image)
        currentArtworkData = thumb
        artworkData = thumb
        artworkColorHex = image.averageColorHex
        lastArtworkKey = key
        // Artwork lands a beat after the track change (Spotify serves it over
        // the network). Force the next widget write past the dedupe and reload,
        // or the widget keeps the artwork-less timeline it was first handed.
        lastWidgetSignature = nil
        WidgetCenter.shared.reloadAllTimelines()
        // Re-render now: while paused the engine emits no position ticks, so
        // waiting for the next tick would leave the payload artwork-less.
        render(engine.positionSubject.value)
    }

    private func clearArtwork(key: String) {
        currentArtworkData = nil
        artworkData = nil
        artworkColorHex = nil
        lastArtworkKey = key
        lastWidgetSignature = nil
        WidgetCenter.shared.reloadAllTimelines()
        render(engine.positionSubject.value)
    }

    /// Widgets and the mini player never need more than a 160 pt square, and
    /// the payload travels to the extension through the keychain.
    private static func thumbnail(_ image: UIImage, side: CGFloat = 160) -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            return image.jpegData(compressionQuality: 0.8) ?? Data()
        }
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Sync heartbeat (Build 42)

    /// Every 15 s while playing, check if the widget-extrapolated position
    /// has drifted more than 2 s from the engine anchor. If so, force a
    /// widget payload rewrite + timeline reload to re-sync.
    private func startSyncHeartbeat() {
        syncHeartbeatTask?.cancel()
        syncHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, let anchor = self.engine.anchor, anchor.isPlaying else { continue }
                let extrapolatedMs = SyncEngine.extrapolatedPositionMs(
                    anchor: anchor, at: Date()
                )
                let widgetMs = SharedWidgetStore.read().flatMap { payload in
                    payload.trackStartEpochMs > 0
                        ? max(0, Int(Date().timeIntervalSince1970 * 1000) - payload.trackStartEpochMs)
                        : nil
                } ?? 0
                if widgetMs > 0, abs(extrapolatedMs - widgetMs) > Self.syncDriftThresholdMs {
                    self.lastWidgetSignature = nil
                    self.render(self.engine.positionSubject.value)
                }
            }
        }
    }
}
