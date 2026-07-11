import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio

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
        playSystemSound(named: "Tink", volume: 0.85)
    }

    /// Soft pop — "listening stopped" (mic released / hold ended).
    static func playListeningStopped() {
        playSystemSound(named: "Pop", volume: 0.9)
    }

    /// Low thud — hotkey pressed but the app can't record yet (model loading).
    static func playNotReady() {
        playSystemSound(named: "Basso", volume: 0.75)
    }

    /// Soft success after text was inserted into the target app.
    static func playSuccess() {
        playSystemSound(named: "Glass", volume: 0.55)
    }

    /// Distinct failure (paste/AX/STT) — not the same as "release mic".
    static func playFailure() {
        playSystemSound(named: "Funk", volume: 0.7)
    }

    // MARK: - Output mute (so users know why chimes are silent)

    /// True when the default output device is muted or its volume is effectively zero.
    static func isOutputMuted() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown
        else { return false }

        // Hardware mute switch / software mute
        var mute: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address),
           AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute) == noErr,
           mute != 0
        {
            return true
        }

        // Volume at (or near) zero
        var volume: Float32 = 1
        size = UInt32(MemoryLayout<Float32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address),
           AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr,
           volume < 0.01
        {
            return true
        }

        return false
    }

    // MARK: - Playback

    private static func playSystemSound(named name: String, volume: Float) {
        // Always hop to main — NSSound / AVAudioPlayer are picky about threads.
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

        // 1) NSSound by name — most reliable for system UI sounds on macOS.
        if let sound = NSSound(named: NSSound.Name(name))
            ?? (FileManager.default.fileExists(atPath: path)
                ? NSSound(contentsOf: url, byReference: true)
                : nil)
        {
            sound.volume = volume
            lock.lock()
            playing.append(sound)
            lock.unlock()
            if !sound.play() {
                NSLog("MacWispr: NSSound.play() returned false for %@", name)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                lock.lock()
                playing.removeAll { $0 === sound }
                lock.unlock()
            }
            return
        }

        // 2) AVAudioPlayer fallback
        if FileManager.default.fileExists(atPath: path) {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = volume
                player.prepareToPlay()
                lock.lock()
                players.append(player)
                lock.unlock()
                if !player.play() {
                    NSLog("MacWispr: AVAudioPlayer.play() returned false for %@", name)
                }
                let delay = max(player.duration + 0.15, 0.4)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    lock.lock()
                    players.removeAll { $0 === player }
                    lock.unlock()
                }
                return
            } catch {
                NSLog("MacWispr: AVAudioPlayer failed for %@: %@", name, "\(error)")
            }
        }

        // 3) Last resort: fixed system beep
        AudioServicesPlaySystemSound(1104)
    }
}
