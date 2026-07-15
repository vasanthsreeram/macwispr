import Foundation
import CoreAudio

/// A Core Audio input device suitable for `AVAudioEngine` capture.
struct AudioInputDevice: Identifiable, Equatable, Hashable {
    /// Stable Core Audio device UID (`kAudioDevicePropertyDeviceUID`).
    let uid: String
    let name: String

    var id: String { uid }

    static let systemDefaultUID = ""
}

enum AudioInputDevices {
    /// Lists connected input devices (microphones), sorted by name.
    static func inputDevices() -> [AudioInputDevice] {
        guard let deviceIDs = allDeviceIDs() else { return [] }
        return deviceIDs.compactMap { deviceInfo(deviceID: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolves a saved UID to a live `AudioDeviceID`, or nil if unplugged.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        guard let deviceIDs = allDeviceIDs() else { return nil }
        for deviceID in deviceIDs {
            guard let deviceUID = readStringProperty(
                deviceID: deviceID,
                selector: kAudioDevicePropertyDeviceUID
            ), deviceUID == uid else { continue }
            return deviceID
        }
        return nil
    }

    /// Human-readable name for the system default input (for UI subtitles).
    static func defaultInputDeviceName() -> String {
        guard let defaultID = defaultInputDeviceID(),
              let info = deviceInfo(deviceID: defaultID) else {
            return "System Default"
        }
        return info.name
    }

    // MARK: - Core Audio

    private static func allDeviceIDs() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else { return nil }
        return ids
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func deviceInfo(deviceID: AudioDeviceID) -> AudioInputDevice? {
        guard deviceHasInputChannels(deviceID: deviceID),
              deviceIsAlive(deviceID: deviceID),
              let uid = readStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID),
              !uid.isEmpty,
              let name = readStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
                ?? readStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
        else { return nil }
        return AudioInputDevice(uid: uid, name: name)
    }

    private static func deviceHasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return false }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return false
        }

        let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceIsAlive(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive) == noErr else {
            return true
        }
        return alive != 0
    }

    private static func readStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ref) == noErr,
              let ref else { return nil }
        return ref as String
    }
}