import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio

// MARK: - Preferences

/// One of the built-in macOS alert sounds under `/System/Library/Sounds`.
enum SystemChime: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Whether this choice maps to a real AIFF file (not silent).
    var isSilent: Bool { self == .none }

    /// File name without extension, or nil when silent.
    var systemSoundName: String? {
        isSilent ? nil : rawValue
    }

    static var playable: [SystemChime] {
        allCases
    }
}

/// User-configurable chimes + volume for dictation feedback.
enum FeedbackSoundPreferences {
    private static let volumeKey = "feedbackSoundVolume"
    private static let startKey = "feedbackSoundStart"
    private static let stopKey = "feedbackSoundStop"
    private static let successKey = "feedbackSoundSuccess"
    private static let failureKey = "feedbackSoundFailure"
    private static let notReadyKey = "feedbackSoundNotReady"

    /// 0…1, applied on top of a soft base so max isn’t ear-splitting.
    static var volume: Double {
        get {
            if UserDefaults.standard.object(forKey: volumeKey) == nil { return 0.45 }
            return min(1, max(0, UserDefaults.standard.double(forKey: volumeKey)))
        }
        set {
            UserDefaults.standard.set(min(1, max(0, newValue)), forKey: volumeKey)
        }
    }

    static var startChime: SystemChime {
        get { load(startKey, default: .tink) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: startKey) }
    }

    static var stopChime: SystemChime {
        get { load(stopKey, default: .pop) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: stopKey) }
    }

    static var successChime: SystemChime {
        get { load(successKey, default: .glass) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: successKey) }
    }

    static var failureChime: SystemChime {
        get { load(failureKey, default: .funk) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: failureKey) }
    }

    static var notReadyChime: SystemChime {
        get { load(notReadyKey, default: .basso) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: notReadyKey) }
    }

    private static func load(_ key: String, default def: SystemChime) -> SystemChime {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let chime = SystemChime(rawValue: raw)
        else { return def }
        return chime
    }

    /// Map 0…1 UI volume → NSSound volume (capped so full isn’t harsh).
    static func playbackVolume() -> Float {
        // Soft ceiling ~0.55 so “100%” is comfortable next to a laptop mic.
        Float(volume) * 0.55
    }
}

// MARK: - Playback

/// Soft audio cues for hold-to-dictate.
///
/// Important: `NSSound` instances must be retained until playback finishes,
/// otherwise the sound is deallocated immediately and you hear nothing.
enum FeedbackSounds {
    private static let lock = NSLock()
    private static var playing: [NSSound] = []
    private static var players: [AVAudioPlayer] = []

    static func playListeningStarted() {
        play(FeedbackSoundPreferences.startChime)
    }

    static func playListeningStopped() {
        play(FeedbackSoundPreferences.stopChime)
    }

    static func playNotReady() {
        play(FeedbackSoundPreferences.notReadyChime)
    }

    static func playSuccess() {
        play(FeedbackSoundPreferences.successChime)
    }

    static func playFailure() {
        play(FeedbackSoundPreferences.failureChime)
    }

    /// Preview a specific chime at the current volume setting.
    static func preview(_ chime: SystemChime) {
        play(chime)
    }

    // MARK: - Output mute

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

    // MARK: - Internals

    private static func play(_ chime: SystemChime) {
        guard let name = chime.systemSoundName else { return }
        let volume = FeedbackSoundPreferences.playbackVolume()
        guard volume > 0.001 else { return }
        playSystemSound(named: name, volume: volume)
    }

    private static func playSystemSound(named name: String, volume: Float) {
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

        AudioServicesPlaySystemSound(1104)
    }
}
