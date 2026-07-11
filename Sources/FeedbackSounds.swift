import AppKit
import AudioToolbox
import AVFoundation

/// Soft audio cues for hold-to-dictate: start listening / stop listening.
///
/// Important: `NSSound` instances must be retained until playback finishes,
/// otherwise the sound is deallocated immediately and you hear nothing.
enum FeedbackSounds {
    private static let lock = NSLock()
    /// Keep sounds alive while they play (NSSound is not retain-on-play).
    private static var playing: [NSSound] = []
    private static var players: [AVAudioPlayer] = []

    /// Higher, short tick — "listening started".
    static func playListeningStarted() {
        playSystemSound(named: "Tink", volume: 0.55)
    }

    /// Soft pop — "listening stopped".
    static func playListeningStopped() {
        playSystemSound(named: "Pop", volume: 0.6)
    }

    /// Low thud — hotkey pressed but the app can't record yet (model loading).
    static func playNotReady() {
        playSystemSound(named: "Basso", volume: 0.5)
    }

    private static func playSystemSound(named name: String, volume: Float) {
        // Always hop to main — NSSound is picky about threads.
        if Thread.isMainThread {
            playOnMain(named: name, volume: volume)
        } else {
            DispatchQueue.main.async {
                playOnMain(named: name, volume: volume)
            }
        }
    }

    private static func playOnMain(named name: String, volume: Float) {
        let path = "/System/Library/Sounds/\(name).aiff"
        let url = URL(fileURLWithPath: path)

        // Prefer AVAudioPlayer — more reliable volume + completion cleanup.
        if FileManager.default.fileExists(atPath: path) {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = volume
                player.prepareToPlay()
                lock.lock()
                players.append(player)
                lock.unlock()
                player.play()
                // Drop after duration so we don't leak players.
                let delay = max(player.duration + 0.1, 0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    lock.lock()
                    players.removeAll { $0 === player }
                    lock.unlock()
                }
                return
            } catch {
                NSLog("MacWispr: AVAudioPlayer failed for \(name): \(error)")
            }
        }

        if let sound = NSSound(contentsOf: url, byReference: true)
            ?? NSSound(named: NSSound.Name(name))
        {
            sound.volume = volume
            lock.lock()
            playing.append(sound)
            lock.unlock()
            sound.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                lock.lock()
                playing.removeAll { $0 === sound }
                lock.unlock()
            }
            return
        }

        // Last resort: system "Tock"
        AudioServicesPlaySystemSound(1104)
    }
}
