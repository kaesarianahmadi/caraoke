import AVFoundation
import Foundation
import os

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
    private static let log = Logger(subsystem: "com.caraoke.poc", category: "audio-keeper")
    private let queue = DispatchQueue(label: "app.caraoke.audio-keeper", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var wantsPlayback = false
    private var isInterrupted = false
    private var sessionActive = false
    private var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Starts the silent keeper session. Safe to call repeatedly.
    func start() {
        queue.async {
            self.wantsPlayback = true
            self.observeSession()
            self.resumeIfAllowed()
        }
    }

    /// Stops the keeper so the app can suspend normally between rides.
    func stop() {
        queue.async {
            guard self.wantsPlayback else { return }
            self.wantsPlayback = false
            self.isInterrupted = false
            self.removeObservers()
            self.player?.stop()
            self.player = nil
            self.deactivateSession()
        }
    }

    /// Runs only on `queue`, including when recovering from system callbacks.
    private func resumeIfAllowed() {
        guard wantsPlayback, !isInterrupted, player?.isPlaying != true else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            let p: AVAudioPlayer
            if let existing = player {
                p = existing
            } else {
                guard let url = Bundle.main.url(forResource: "ride-keeper", withExtension: "wav") else {
                    Self.log.error("Ride keeper audio asset is missing")
                    return
                }
                p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = 1.0
                player = p
            }
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            sessionActive = true
            guard p.play() else {
                Self.log.error("Ride keeper player did not start")
                deactivateSession()
                return
            }
        } catch {
            Self.log.error("Ride keeper audio unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        defer { sessionActive = false }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Self.log.error("Ride keeper could not deactivate: \(error.localizedDescription, privacy: .public)")
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
            queue: nil
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.queue.async { [weak self] in self?.handleInterruption(type) }
        })
        // CarPlay connect/disconnect and Bluetooth hand-offs deactivate the
        // session out from under us on some head units, with no interruption.
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in self?.resumeIfAllowed() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.wantsPlayback else { return }
                self.player = nil
                self.isInterrupted = false
                self.sessionActive = false
                self.resumeIfAllowed()
            }
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType) {
        guard wantsPlayback else { return }
        switch type {
        case .began: isInterrupted = true
        case .ended:
            isInterrupted = false
            resumeIfAllowed()
        @unknown default: break
        }
    }
}
