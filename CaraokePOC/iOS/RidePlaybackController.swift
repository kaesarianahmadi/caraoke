import Foundation
import Combine
import UIKit
import WidgetKit
import os

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
    @Published private(set) var currentLineIndex: Int? = nil
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
    /// Set when a correction must reach the widget even though nothing about
    /// the track, play state or status changed — the reload gate below only
    /// opens on a visible change, so a drift correction would otherwise be
    /// written to the shared store and never picked up.
    private var forceWidgetReload = false
    /// What the player says plays next, plus its lyrics, resolved on every
    /// track change and baked into the same widget timeline as the current
    /// song. Spotify only: MusicKit exposes no public queue.
    private var chainedTrack: LyricTrack?
    private var chainedNext: TransportControl.QueuedTrack?
    private var chainTask: Task<Void, Never>?
    /// The chained song's own cover, fetched from the queue entry's album art.
    /// Without it the baked tail switches title and artist at the boundary but
    /// keeps painting the cover of the song that already ended.
    private var chainedArtwork: Data?
    private var chainedArtworkHex: String?
    /// Boundary diagnostics — the only way to tell "the app stopped reloading"
    /// from "the reload was throttled", which look identical on screen.
    private static let log = Logger(subsystem: "com.caraoke.poc", category: "ride")
    /// Coalesces rapid reloadAllTimelines calls (lyrics landing, artwork landing,
    /// queue chain, seek jumps) into a trailing debounce so chronod never
    /// penalizes the widget with a 70+ second lockout.
    private var pendingWidgetReloadTask: Task<Void, Never>?
    private var lastWidgetReloadDate: Date = .distantPast
    private let minWidgetReloadInterval: TimeInterval = 1.0
    private let widgetReloadDebounce: TimeInterval = 0.2
    /// The `trackStartEpochMs` carried by the last reload that actually
    /// executed. Drift is measured against *this*, never against the shared
    /// store — the store is rewritten the moment the app re-anchors, so a
    /// store-vs-engine comparison reads zero drift even while the widget is
    /// still rendering a timeline baked from the old anchor. That is what made
    /// a seek invisible: the payload was corrected and the tile was not.
    private var lastReloadedTrackStartMs = 0
    /// What one widget bake contains. Recorded at payload-write time and
    /// promoted to `reloadedBake` when a reload actually executes — the
    /// heartbeat self-heals against what the tile was last HANDED, the same
    /// discipline as `lastReloadedTrackStartMs`.
    private struct Bake {
        /// Date of the bake's last entry (0 when the bake is static — a
        /// single entry covers nothing to run out of).
        var coverageEndMs = 0
        /// The bake came back as one static entry while the payload says the
        /// song is playing — FIX's fallback state, a tile that never slides.
        var staticWhilePlaying = false
        /// (date ms, lyric line index) per baked entry: "which line does the
        /// tile show at time T" reads straight off these.
        var stamps: [(dateMs: Int, lineIndex: Int)] = []
    }
    private var pendingBake = Bake()
    private var reloadedBake = Bake()
    /// Self-heal triggers fire once per episode each (chronod's budget is
    /// ~40-70 reloads per widget per day; bursts under a second apart earn a
    /// 70 s penalty box).
    private var selfHealFiredCoverageMs = 0
    private var selfHealFiredStatic = false
    private var selfHealFiredDivergence = false
    /// Last bold-text value written to the shared widget settings.
    private var lastWidgetBoldText: Bool?

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
        pendingWidgetReloadTask?.cancel()
        pendingWidgetReloadTask = nil
        audioKeeper.stop()
        relay.end()
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        chainTask?.cancel()
        chainTask = nil
        chainedTrack = nil
        chainedNext = nil
        chainedArtwork = nil
        chainedArtworkHex = nil
        forceWidgetReload = false
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
        lastWidgetStatus = nil
        trackStartEpochMs = 0
        trackStartKey = nil
        lastReloadedTrackStartMs = 0
        pendingBake = Bake()
        reloadedBake = Bake()
        selfHealFiredCoverageMs = 0
        selfHealFiredStatic = false
        selfHealFiredDivergence = false
        lastWidgetBoldText = nil
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
        SharedWidgetStore.requestReload(reason: "ride-mode-stop")
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
        // Duration deliberately excluded from the key: its 5 s bucket
        // flipped on identical now-playing noise (a nil or wobbling
        // duration_ms), re-keyed the same track mid-song, and wiped the
        // lyrics to "No lyrics".
        let key = TrackMatcher.signature(
            title: state.title, artist: state.artist, durationMs: nil
        )
        let isNewTrack = key != lastLyricsKey
        if isNewTrack {
            lastLyricsKey = key
            lastTrack = nil
            lyricsFetchTask?.cancel()
            chainTask?.cancel()
            chainedTrack = nil
            chainedNext = nil
            chainedArtwork = nil
            chainedArtworkHex = nil
            Self.log.info("track change → \(state.title, privacy: .public)")
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
            // Transient failures (network, rate limit) retry instead of
            // downgrading to "No lyrics" — that downgrade wiped mid-song
            // lyrics on a blip. Three attempts, 5 s apart, cancelled with
            // the task on track change.
            for attempt in 0..<3 {
                if Task.isCancelled { return }
                let fetched: LyricTrack?
                do {
                    fetched = try await self.provider.lyrics(for: signature)
                } catch {
                    if attempt < 2 {
                        try? await Task.sleep(for: .seconds(5))
                        continue
                    }
                    // Out of retries: claim "No lyrics" only when this track
                    // never had any — last-good lyrics stay on screen.
                    if self.lastTrack == nil {
                        self.lyricState = .noLyrics
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                guard let track = fetched else {
                    // Definitive: the provider says no synced lyrics exist.
                    if self.lastTrack == nil {
                        self.lyricState = .noLyrics
                    }
                    return
                }
                self.lastTrack = track
                self.allLines = track.lines
                self.engine.setLyrics(
                    track.lines.map { LRCLine(timeMs: $0.startMs, text: $0.text, translation: $0.translation) }
                )
                self.armRelay(track: track)
                self.lyricState = .playing
                self.render(self.engine.positionSubject.value)
                Self.log.info("lyrics landed → \(track.lines.count, privacy: .public) lines, widget write follows")
                self.startChainFetch()
                return
            }
        }
    }

    /// Asks the player what follows this track and resolves its lyrics, so the
    /// widget's next timeline carries the song change instead of waiting for a
    /// wake that iOS is free to refuse (build 56).
    ///
    /// Speculative by design: a skip invalidates the guess, and the app's own
    /// reload on the real track change replaces it. The upside is the case that
    /// matters on a drive — an uninterrupted song change needs no reload, no
    /// wake, and no budget at all.
    private func startChainFetch() {
        chainTask?.cancel()
        chainedTrack = nil
        chainedNext = nil
        chainedArtwork = nil
        chainedArtworkHex = nil
        guard engine.anchor?.source == .spotify else { return }
        chainTask = Task { [weak self] in
            guard let self else { return }
            guard let queued = await TransportControl.spotifyNextInQueue(),
                  !Task.isCancelled, queued.durationMs > 0 else { return }
            let signature = TrackSignature(title: queued.title, artist: queued.artist,
                                           album: queued.album, durationMs: queued.durationMs)
            guard let next = try? await self.provider.lyrics(for: signature),
                  !Task.isCancelled, !next.lines.isEmpty else { return }
            // Resolved before the write, not alongside it: the cover is a
            // second network hop behind the queue call, and the chain's single
            // reload is the one chance to put it in the payload. Landing it
            // afterwards would need another reload — exactly the call that gets
            // starved when the boundary arrives.
            let art = await Self.fetchArtwork(urlString: queued.artworkURL)
            guard !Task.isCancelled else { return }
            self.chainedNext = queued
            self.chainedTrack = next
            self.chainedArtwork = art?.data
            self.chainedArtworkHex = art?.hex
            Self.log.info("chained next → \(queued.title, privacy: .public) (\(next.lines.count, privacy: .public) lines) art=\(art != nil, privacy: .public)")
            // The payload now knows the future: rewrite and reload so the
            // widget picks up a timeline that crosses the boundary on its own.
            self.lastWidgetSignature = nil
            self.forceWidgetReload = true
            self.render(self.engine.positionSubject.value)
        }
    }

    /// Downloads a cover by URL and reduces it to the thumbnail + average
    /// colour the widget paints with. Silent on failure: a chain without art
    /// still carries the lyrics, and the tile falls back to the current song's
    /// cover rather than dropping the whole chain.
    private static func fetchArtwork(urlString: String?) async -> (data: Data, hex: String?)? {
        guard let urlString, let url = URL(string: urlString),
              let (raw, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: raw) else { return nil }
        return (thumbnail(image), image.averageColorHex)
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

        // A real seek re-anchors the widget *before* the relay's coalescing
        // window gets a chance to swallow it. That window exists to absorb
        // Spotify's poll jitter in the relay schedule, and nothing else — while
        // it also gated the widget reload, a second seek inside five seconds
        // left the tile rendering a timeline baked from the pre-seek anchor,
        // with no code path left that could notice. chronod is protected by the
        // debounce in `scheduleWidgetReload`, not by this.
        if startMoved {
            lastWidgetSignature = nil
            forceWidgetReload = true
            render(engine.positionSubject.value)
        }

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
        currentLineIndex = position.lineIndex
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
        lyricState = state
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
    /// Three deliberate limits, all learned from dead widgets:
    /// - a track change clears the lyrics before the fetch returns, and writing
    ///   that empty payload is what froze the tile on the new song's blank
    ///   state — the outgoing song is held until there are real lines, and the
    ///   reload then carries them;
    /// - the write is skipped unless the rendered state actually changed
    ///   (`render` runs 4×/s, and keychain writes are not free);
    /// - the reload is skipped unless something the baked timeline cannot know
    ///   by itself changed: the track, the play state, the lyric status or the
    ///   artwork. Line advance is not one of those — the widget walks the
    ///   payload's timed line list on its own, and reloading per line is what
    ///   burned WidgetKit's daily reload budget.
    private func syncWidget(snapshot: LyricSnapshot) {
        guard snapshot.status != .loading else { return }

        // Widget settings ride the shared store: the appearance UI owns
        // `appearance.boldText` in UserDefaults and the widget reads boldText
        // from here. Written only when the value changes.
        let boldText = UserDefaults.standard.object(forKey: "appearance.boldText") as? Bool ?? true
        if boldText != lastWidgetBoldText {
            var settings = SharedWidgetStore.readSettings()
            settings.boldText = boldText
            SharedWidgetStore.writeSettings(settings)
            lastWidgetBoldText = boldText
        }

        let anchor = engine.anchor
        // Same duration-free key as `handle` — see the comment there.
        let key = TrackMatcher.signature(
            title: snapshot.title, artist: snapshot.artist, durationMs: nil
        )
        if anchor?.isPlaying == true || trackStartKey != key {
            trackStartEpochMs = (Int((anchor?.capturedAt.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000))
                - (anchor?.positionMs ?? 0)
            trackStartKey = key
        }

        var widgetLines = lastTrack?.lines.map {
            SharedLyricLine(timeMs: $0.startMs, text: $0.text, translation: $0.translation)
        } ?? []
        // Chain the song the player says comes next into the same array, offset
        // by this song's length, so one timeline crosses the boundary with no
        // reload. Only meaningful when this song's own lines end before the
        // boundary — otherwise the offsets would land out of order.
        let spanMs = snapshot.durationMs ?? 0
        var nextStartMs = 0
        var nextDurationMs = 0
        var nextTitle = ""
        var nextArtist = ""
        if let chained = chainedTrack, let queued = chainedNext,
           spanMs > 0, queued.durationMs > 0,
           let lastLine = widgetLines.last, lastLine.timeMs < spanMs {
            widgetLines += chained.lines.map {
                SharedLyricLine(timeMs: spanMs + $0.startMs, text: $0.text, translation: $0.translation)
            }
            nextStartMs = spanMs
            nextDurationMs = queued.durationMs
            nextTitle = queued.title
            nextArtist = queued.artist
        }

        let signature = [
            key,
            snapshot.currentLine,
            snapshot.isPlaying ? "1" : "0",
            snapshot.status.rawValue,
            String(trackStartEpochMs / 1000),
            String(widgetLines.count),
            String(nextStartMs),
            artworkColorHex ?? "-",
            chainedArtworkHex ?? "-",
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
            source: anchor?.source.rawValue ?? "appleMusic",
            resyncingUntilMs: 0,
            nextStartMs: nextStartMs,
            nextDurationMs: nextDurationMs,
            nextTitle: nextTitle,
            nextArtist: nextArtist,
            nextArtworkData: chainedArtwork,
            nextArtworkColorHex: chainedArtworkHex
        )
        SharedWidgetStore.write(payload)

        // Record what the widget's bake of this payload will contain. The
        // heartbeat self-heals against the copy a reload actually delivered
        // (see `scheduleWidgetReload`) — the store is rewritten every tick
        // and would always read as up to date while a stale tile freezes.
        let baked = WidgetTimelineBuilder.entries(for: payload, now: Date(), includeOutro: true)
        var stamps: [(dateMs: Int, lineIndex: Int)] = []
        for entry in baked {
            if let index = entry.lineIndex, (0..<widgetLines.count).contains(index) {
                stamps.append((dateMs: Int(entry.date.timeIntervalSince1970 * 1000), lineIndex: index))
            }
        }
        pendingBake = Bake(
            coverageEndMs: baked.count > 1
                ? Int((baked.last?.date ?? Date()).timeIntervalSince1970 * 1000)
                : 0,
            staticWhilePlaying: payload.isPlaying && baked.count == 1,
            stamps: stamps
        )

        let isTitleChanged = snapshot.title != lastWidgetTitle
        let isPlayStateChanged = snapshot.isPlaying != lastWidgetIsPlaying
        let isStatusChanged = snapshot.status.rawValue != lastWidgetStatus
        // Line changes deliberately reload nothing: the payload just written
        // already carries the full timed lyric list plus `trackStartEpochMs`,
        // and the widget's baked timeline walks it entry by entry on its own.
        // Reloading per line spent the whole daily budget in two tracks and
        // left chronod ignoring the reloads that mattered — the song change,
        // the seek, the artwork landing. When that self-advancing timeline
        // runs out or drifts anyway, the heartbeat's bounded self-heal below
        // reloads on its own — still never per line.
        // Artwork (and its colour) often lands a beat AFTER the track change —
        // Spotify serves it over the network — so the widget must reload again
        // or it keeps the artwork-less timeline it was first handed.
        let isArtworkChanged = artworkColorHex != lastWidgetArtworkHex
        // A drift correction has to be able to reach the widget on its own:
        // nothing about the track, play state or status changed, so without
        // this the heartbeat's fix was written to the shared store and never
        // picked up until the next song.
        let forced = forceWidgetReload
        forceWidgetReload = false
        guard forced || isTitleChanged || isPlayStateChanged || isStatusChanged || isArtworkChanged else { return }
        lastWidgetTitle = snapshot.title
        lastWidgetIsPlaying = snapshot.isPlaying
        lastWidgetStatus = snapshot.status.rawValue
        lastWidgetArtworkHex = artworkColorHex
        // Name the trigger, so the reload log says why this bake happened.
        // Coalesced triggers are rare enough that naming the first is honest;
        // a burst is visible as consecutive lines with different reasons.
        var causes: [String] = []
        if forced { causes.append("heartbeat") }
        if isTitleChanged { causes.append("title") }
        if isPlayStateChanged { causes.append("playstate") }
        if isStatusChanged { causes.append("status") }
        if isArtworkChanged { causes.append("artwork") }
        scheduleWidgetReload(reason: causes.joined(separator: "+"))
        Self.log.info("widget reload scheduled: lines=\(widgetLines.count, privacy: .public) chain=\(nextStartMs, privacy: .public) forced=\(forced, privacy: .public)")
    }

    // MARK: - Widget reload coalescing (Build 57)
    //
    // iOS chronod throttles aggressively when reloadAllTimelines() is called in
    // bursts (< 1 s apart), placing the widget into a 70+ second penalty box
    // where all reloads are ignored. We coalesce rapid triggers (lyrics landing,
    // artwork landing, queue chain, and seeks) through a trailing debounce.
    private func scheduleWidgetReload(reason: String) {
        pendingWidgetReloadTask?.cancel()
        pendingWidgetReloadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.widgetReloadDebounce))
            guard !Task.isCancelled else { return }

            let elapsed = Date().timeIntervalSince(self.lastWidgetReloadDate)
            if elapsed < self.minWidgetReloadInterval {
                let remaining = self.minWidgetReloadInterval - elapsed
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }

            self.lastWidgetReloadDate = Date()
            self.pendingWidgetReloadTask = nil
            // Record the anchor this reload carries. The sync heartbeat measures
            // the engine against *this* value — what the widget was last
            // actually handed — because nothing else in the process can see
            // whether a timeline that was written ever became one that renders.
            // The bake rides along for the same reason.
            self.lastReloadedTrackStartMs = self.trackStartEpochMs
            self.reloadedBake = self.pendingBake
            SharedWidgetStore.requestReload(reason: reason)
            Self.log.info("widget reload executed (coalesced) reason=\(reason, privacy: .public)")
        }
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
    /// widget payload rewrite + timeline reload to re-sync. The same beat
    /// runs the bounded self-heal below, which is what un-freezes a CarPlay
    /// tile whose baked timeline ran out or arrived stale.
    private func startSyncHeartbeat() {
        syncHeartbeatTask?.cancel()
        syncHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, let anchor = self.engine.anchor, anchor.isPlaying else { continue }
                self.selfHealWidgetTimeline()
                // Both sides are track anchors, so this is engine-vs-widget and
                // not the app against itself. Reading `SharedWidgetStore` here
                // measured a payload the app had already re-anchored the instant
                // it noticed the seek — a stale tile and a correct one produced
                // the same number, which is why a skip never registered as a
                // desync. `lastReloadedTrackStartMs` only advances when a reload
                // actually executes, so anything the reload gate or the seek
                // coalescer dropped shows up here as real drift.
                let engineStartMs = Int(anchor.capturedAt.timeIntervalSince1970 * 1000) - anchor.positionMs
                let widgetStartMs = self.lastReloadedTrackStartMs
                guard widgetStartMs > 0 else { continue }
                if abs(engineStartMs - widgetStartMs) > Self.syncDriftThresholdMs {
                    self.lastWidgetSignature = nil
                    // Without this the corrected payload is written and the
                    // reload gate below refuses it — the drift fix never
                    // reached the tile.
                    self.forceWidgetReload = true
                    Self.log.info("widget anchor stale by \(engineStartMs - widgetStartMs, privacy: .public)ms → forcing widget reload")
                    self.render(self.engine.positionSubject.value)
                }
            }
        }
    }

    /// Bounded self-healing reloads — the fix for "the widget shows one
    /// picture and never slides". A baked timeline advances on its own until
    /// it runs out, and on the CarPlay host the `.after` refill does not
    /// always arrive. Three repairs on the 15 s beat, each firing at most
    /// once per episode so chronod's daily budget survives: the delivered
    /// bake is about to run out, it came back static while playing, or the
    /// tile's line has diverged from the app's by more than one.
    private func selfHealWidgetTimeline() {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let bake = reloadedBake
        if !bake.staticWhilePlaying { selfHealFiredStatic = false }
        let shownLine = bake.stamps.last(where: { $0.dateMs <= nowMs })?.lineIndex ?? -1
        let diverged = abs((currentLineIndex ?? -1) - shownLine) > 1
        if !diverged { selfHealFiredDivergence = false }

        let cause: String
        if bake.coverageEndMs > 0, nowMs >= bake.coverageEndMs - 10_000,
           selfHealFiredCoverageMs != bake.coverageEndMs {
            selfHealFiredCoverageMs = bake.coverageEndMs
            cause = "coverage end at \(bake.coverageEndMs - nowMs)ms"
        } else if bake.staticWhilePlaying, !selfHealFiredStatic {
            selfHealFiredStatic = true
            cause = "static entry while playing"
        } else if diverged, !selfHealFiredDivergence {
            selfHealFiredDivergence = true
            cause = "line divergence app \(currentLineIndex ?? -1) vs tile \(shownLine)"
        } else {
            return
        }
        Self.log.info("widget self-heal: \(cause, privacy: .public) → reload")
        scheduleWidgetReload()
    }
}
