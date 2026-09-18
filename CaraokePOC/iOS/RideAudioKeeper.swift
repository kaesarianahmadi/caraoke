import AVFoundation
import Foundation

/// Keeps the Caraoke process alive while a ride is active so it can detect
/// track changes (skips/seeks, via MusicKit/MediaPlayer notifications and the
/// 1 s poll) and re-arm the background lyric relay. The phone cannot do
/// this while suspended (~30 s after locking), so a silent looping audio
/// session (UIBackgroundModes: audio) is the standard mechanism karaoke /
/// lyrics companion apps use — the playback renders inaudible frames (~-68
/// dBFS) mixed with the user's music (.mixWithOthers) without interrupting it.
///
/// Build 46 — the freeze fix. The keeper used to die silently the first time
/// anything took the audio session away, which is exactly the driving case:
/// a CarPlay navigation prompt, a Siri request, or an incoming call posts
/// `interruptionNotification`, iOS pauses the player, and nothing ever
/// resumed it. The process then looked idle, iOS suspended Caraoke ~30 s
/// later, and the lyric tile froze mid-song while the music kept playing.
/// The keeper now observes interruptions and route changes and re-arms
/// itself, so background execution survives the whole ride.
final class RideAudioKeeper {
    private var player: AVAudioPlayer?
    private var isActive = false
    private var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Starts the silent keeper session. Safe to call repeatedly.
    func start() {
        guard !isActive else { return }
        observeSession()
        guard play() else { return }
        isActive = true
    }

    /// Stops the keeper so the app can suspend normally between rides.
    func stop() {
        guard isActive else { return }
        removeObservers()
        player?.pause()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isActive = false
    }

    /// Builds the session, starts the loop, and reports whether audio is
    /// actually rendering. Called from `start()` and from every recovery path.
    @discardableResult
    private func play() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback + .mixWithOthers: plays alongside Apple Music/Spotify
            // without ducking or interrupting them.; NO .duckOthers.
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            guard let url = Bundle.main.url(forResource: "ride-keeper", withExtension: "wav") else {
                return false
            }
            // Reuse the player across an interruption when we still have it —
            // rebuilding it costs a disk read on every navigation prompt.
            let p = player ?? (try AVAudioPlayer(contentsOf: url))
            p.numberOfLoops = -1  // loop forever — one 1 s inaudible sample
            p.volume = 1.0      // the asset itself is already ~-68 dBFS
            if !p.isPlaying { p.play() }
            player = p
            return true
        } catch {
            // Not fatal for the ride; foreground sync still works.
            return false
        }
    }

    /// The recovery path. Everything below exists so a prompt, a call, or a
    /// head-unit swap cannot end background execution.
    private func observeSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        })
        // CarPlay connect/disconnect and Bluetooth hand-offs deactivate the
        // session out from under us on some head units, with no interruption.
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func handleInterruption(_ note: Notification) {
        guard isActive,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended else { return }
        // .shouldResume is advisory; resume either way. iOS takes the session
        // back cleanly whether or not we ask, and a keeper that stays silent
        // is the bug we are fixing.
        _ = play()
    }

    private func handleRouteChange(_ note: Notification) {
        guard isActive, let p = player, !p.isPlaying else { return }
        _ = play()
    }
}
