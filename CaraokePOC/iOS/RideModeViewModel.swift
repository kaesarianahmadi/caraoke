import SwiftUI
import Combine
import os
import UIKit

/// The ride controller: owns Ride Mode state and the Live Activity.
///
/// Two playback paths behind `useSimulatedPlayback`:
/// - **Simulated (current, default):** the fake 1-second clock walks the
///   bundled demo fixture — the proof-of-concept path that works everywhere.
/// - **Real:** `RidePlaybackController` drives Apple Music/Spotify →
///   arbiter → sync engine → LRCLIB lyrics → Live Activity. The flag flips
///   after Phase C validates the real path on hardware (background-update
///   decision, see research/background-update-strategy.md).
@MainActor
final class RideModeViewModel: ObservableObject {

    /// Phase C: real playback path is LIVE (Apple Music/Spotify → arbiter →
    /// sync engine → LRCLIB → Live Activity). The simulated demo clock is OFF
    /// because the user's locked-phone test proved iOS suspends the app process
    /// at ~30 s — the same suspension hits the simulated path, so the demo is
    /// no longer a useful stand-in for the driving case (see research/
    /// background-update-strategy.md: mechanism #2 relay is required; its
    /// infra needs an APNs push key + a relay host, both user-supplied).
    static let useSimulatedPlayback = false

    @Published private(set) var isOn = false
    @Published private(set) var elapsedMs = 0
    @Published private(set) var currentLine = ""
    @Published private(set) var currentLineIndex: Int? = nil
    @Published private(set) var currentTranslation: String?
    @Published private(set) var previousLines: [String] = []
    @Published private(set) var nextLine: String?
    @Published private(set) var upcomingLines: [String] = []
    @Published private(set) var allLines: [LyricLine] = []
    /// Now-playing identity + clock, bridged from the real playback pipeline
    /// so the home screen's player card matches the Lock Screen tile.
    @Published private(set) var trackTitle = ""
    @Published private(set) var trackArtist = ""
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs: Int?
    @Published private(set) var lyricStatus: LyricStatus = .idle
    /// Cover art of the current track — the mini player and the lyrics page.
    @Published private(set) var artworkData: Data?

    /// Average colour of the cover as `RRGGBB`. The same value the widget
    /// payload carries, so the in-app surfaces can follow the song's colour
    /// exactly like the Home Screen widget does.
    var artworkColorHex: String? {
        artworkData.flatMap(UIImage.init(data:))?.averageColorHex
    }

    // Home screen bindings (design states A–D).

    /// Player-card progress 0–1 (from the pipeline anchor; demo = derived).
    var progress: Double {
        guard let durationMs, durationMs > 0 else { return 0 }
        return min(1, Double(positionMs) / Double(durationMs))
    }

    public enum ActiveMusicSource: String {
        case appleMusic
        case spotify
        case auto
    }

    @Published public var activeSource: ActiveMusicSource = {
        let saved = UserDefaults.standard.string(forKey: "caraoke_active_music_source")
        return ActiveMusicSource(rawValue: saved ?? "") ?? .appleMusic
    }() {
        didSet {
            UserDefaults.standard.set(activeSource.rawValue, forKey: "caraoke_active_music_source")
            switch activeSource {
            case .spotify:
                realPlayback.setSourcePin(.spotify)
            case .appleMusic:
                realPlayback.setSourcePin(.appleMusic)
            case .auto:
                realPlayback.setSourcePin(.auto)
            }
        }
    }

    /// Mutually exclusive active source indicators (prevents both showing active)
    var appleMusicConnected: Bool {
        switch activeSource {
        case .appleMusic:
            return true
        case .spotify:
            return false
        case .auto:
            return !spotifyConnected
        }
    }

    var spotifyConnected: Bool {
        guard spotifyAuth.isConnected else { return false }
        switch activeSource {
        case .spotify:
            return true
        case .appleMusic:
            return false
        case .auto:
            return realPlayback.currentSource == .spotify
        }
    }

    func selectMusicSource(_ source: ActiveMusicSource) {
        activeSource = source
        let typeStr: String
        switch source {
        case .auto: typeStr = "auto"
        case .spotify: typeStr = "spotify"
        case .appleMusic: typeStr = "apple_music"
        }
        Analytics.signal("playback_source", parameters: ["type": typeStr])
    }

    /// Single SpotifyAuth for Settings + pipeline. Exposed read-only.
    let spotifyAuth = SpotifyAuth()

    /// Non-nil when the Live Activities gate is blocking (design state D):
    /// authorization denied at the system level.
    var liveActivityGateMessage: String? {
        guard activity.authorizationDenied else { return nil }
        return "Live Lyrics is off"
    }

    /// Ride Mode survives a relaunch: the widget can open the app long after
    /// iOS suspended it, and the lyrics page must not come up empty.
    private static let rideModeKey = "caraoke_ride_mode"
    private var playbackStarted = false
    private var rideModel = RideModeModel()
    private let track = DemoLyrics.track
    private let activity = CaraokeActivityController()
    private var clockTask: Task<Void, Never>?
    private lazy var realPlayback = RidePlaybackController(activity: activity, spotifyAuth: spotifyAuth)
    private var playbackCancellables: Set<AnyCancellable> = []
    private var authCancellables: Set<AnyCancellable> = []

    /// 1 tick per second simulates playback; lyrics advance by their own
    /// timestamps. (The real path reads the player's position instead.)
    private let tickInterval: Duration = .seconds(1)

    var isPlaying: Bool { isOn }

    /// True when the active source is actually playing (drives the in-app
    /// transport icon — `isOn` is Ride Mode, not playback).
    var isPlaybackActive: Bool { lyricStatus == .playing }

    /// In-app transport: same routing as the widget / Live Activity buttons,
    /// so the app never drives the wrong player either.
    func transport(_ action: TransportAction) async {
        let source: String?
        switch activeSource {
        case .spotify: source = "spotify"
        case .appleMusic: source = "appleMusic"
        case .auto: source = nil // let the running pipeline decide
        }
        if action == .playPause {
            lyricStatus = (lyricStatus == .playing) ? .paused : .playing
        }
        let outcome = await TransportControl.perform(action, source: source, isPlaying: isPlaybackActive)
        switch outcome {
        case .failed(let msg), .noActivePlayer(let msg):
            transportError = msg
        case .performed:
            transportError = nil
        }
    }

    /// Last transport failure message, shown as a brief overlay on the
    /// lyrics page so the user knows why nothing happened.
    @Published var transportError: String?

    /// Ride length across all rides (for the Settings screen).
    var totalRideMs: Int { rideModel.totalRideMs }

    init() {
        // Diagnostics (why the activity did/didn't appear) go to the console
        // log — the locked Home design has no diagnostic line.
        activity.onDiagnostic = { message in
            Logger(subsystem: "com.caraoke.poc", category: "ride").info("\(message, privacy: .public)")
        }
        // Re-publish object changes when Spotify auth changes.
        spotifyAuth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &authCancellables)

        bindPlayback()
        isOn = UserDefaults.standard.bool(forKey: Self.rideModeKey)
    }

    private func bindPlayback() {
        realPlayback.$currentLine
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.currentLine = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$currentLineIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.currentLineIndex = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$currentTranslation
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.currentTranslation = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$previousLines
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.previousLines = val
            }
            .store(in: &playbackCancellables)
        realPlayback.$nextLine
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.nextLine = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$upcomingLines
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.upcomingLines = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$allLines
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.allLines = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$trackTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.trackTitle = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$trackArtist
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.trackArtist = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$positionMs
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.positionMs = val
                self.lyricStatus = self.realPlayback.lyricState
            }
            .store(in: &playbackCancellables)

        realPlayback.$durationMs
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                guard let self, self.isOn else { return }
                self.durationMs = val
            }
            .store(in: &playbackCancellables)

        realPlayback.$artworkData
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                self?.artworkData = val
            }
            .store(in: &playbackCancellables)
    }

    func resetStats() {
        rideModel.resetStats()
    }

    func toggle() {
        isOn ? stopRide() : startRide()
    }

    func startRide() {
        guard !isOn else { return }
        isOn = true
        Analytics.signal("ride_started")
        UserDefaults.standard.set(true, forKey: Self.rideModeKey)
        elapsedMs = 0
        rideModel.start(at: 0)
        // Always-on: request the Live Activity up front (foreground-only)
        // with a placeholder, so the tile exists even before any song plays
        // and persists when the user switches to another app.
        activity.startIdle()
        if Self.useSimulatedPlayback {
            startDemoClock()
        } else {
            startRealPlayback()
            playbackStarted = true
        }
    }

    /// Re-requests the Live Activity when it is missing (system ended it, or
    /// the app was relaunched with Ride Mode still on). Called on every
    /// foreground transition — a no-op while an activity is live.
    func ensureActivity() {
        guard isOn else { return }
        if !Self.useSimulatedPlayback, !playbackStarted {
            startRealPlayback()
            playbackStarted = true
        }
        seedFromSharedPayload()
        guard !activity.isActive else { return }
        activity.startIdle()
    }

    /// Fills the UI from the widget's shared payload. Opening the app from a
    /// widget used to show an empty page for the few seconds the pipeline needs
    /// to poll the player; the payload the widget was just rendering is
    /// already the right answer.
    func seedFromSharedPayload() {
        guard trackTitle.isEmpty, let payload = SharedWidgetStore.read(), !payload.title.isEmpty else { return }
        trackTitle = payload.title
        trackArtist = payload.artist
        currentLine = payload.currentLine
        previousLines = payload.previousLines
        nextLine = payload.nextLine
        upcomingLines = payload.upcomingLines
        durationMs = payload.durationMs > 0 ? payload.durationMs : nil
        positionMs = WidgetTimelineBuilder.positionMs(for: payload, now: Date())
        artworkData = payload.artworkData
        lyricStatus = LyricStatus(raw: payload.status) ?? .idle
    }

    func stopRide() {
        guard isOn else { return }
        isOn = false
        UserDefaults.standard.set(false, forKey: Self.rideModeKey)
        playbackStarted = false
        rideModel.stop(at: elapsedMs)
        clockTask?.cancel()
        clockTask = nil
        if !Self.useSimulatedPlayback {
            realPlayback.stop()
        }
        Task { await activity.endNow() }
        trackTitle = ""
        trackArtist = ""
        currentLine = ""
        currentLineIndex = nil
        previousLines = []
        nextLine = nil
        upcomingLines = []
        allLines = []
        positionMs = 0
        durationMs = nil
        lyricStatus = .idle
        artworkData = nil
    }

    private func startDemoClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.tickInterval ?? .seconds(1))
                guard let self else { return }
                self.elapsedMs += 1000
                self.pushSnapshot()
            }
        }
        pushSnapshot()
    }

    private func startRealPlayback() {
        switch activeSource {
        case .spotify:
            realPlayback.setSourcePin(.spotify)
        case .appleMusic:
            realPlayback.setSourcePin(.appleMusic)
        case .auto:
            realPlayback.setSourcePin(.auto)
        }
        realPlayback.start()
    }

    private func pushSnapshot() {
        let snapshot = LyricSnapshotBuilder.snapshot(
            track: track,
            title: DemoLyrics.title,
            artist: DemoLyrics.artist,
            positionMs: elapsedMs,
            isPlaying: isPlaying
        )
        currentLine = snapshot.currentLine
        nextLine = snapshot.nextLine
        activity.sync(snapshot: snapshot)
    }
}
