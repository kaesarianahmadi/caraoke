import AVFoundation
import Foundation

/// Keeps the Caraoke process alive while a ride is active so it can detect
/// track changes (skips/seeks, via MusicKit/MediaPlayer notifications and the
/// 1 s poll) and re-arm the background lyric relay. The phone cannot do
/// this while suspended (~30 s after locking), so a silent looping audio
/// session (UIBackgroundModes: audio) is the standard mechanism karaoke /
/// lyrics companion apps use — the playback renders inaudible frames (~-68
/// dBFS) mixed with the user's music (.mixWithOthers) without interrupting it.

final class RideAudioKeeper {
    private var player: AVAudioPlayer?
    private var isActive = false

    /// Starts the silent keeper session. Safe to call repeatedly.

    func start() {
        guard !isActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback + .mixWithOthers: plays alongside Apple Music/Spotify
            // without ducking or interrupting them.; NO .duckOthers.
 
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            guard let url = Bundle.main.url(forResource: "ride-keeper", withExtension: "wav") else {
                return
            }
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1  // loop forever — one 1 s inaudible sample
            p.volume = 1.0      // the asset itself is already ~-68 dBFS
            p.play()
            player = p
            isActive = true
        } catch {
            // Not fatal for the ride; foreground sync still works.
 
            isActive = false
        }
    }

    /// Stops the keeper so the app can suspend normally between rides.

 
    func stop() {
        guard isActive else { return }
        player?.pause()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isActive = false
    }
}