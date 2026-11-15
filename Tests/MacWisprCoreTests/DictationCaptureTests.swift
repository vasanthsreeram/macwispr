import XCTest
@testable import MacWisprCore

/// EDGE-1: a dictation started while the previous one transcribes must not
/// share (or wipe) the previous session's audio.
final class CaptureSessionRingsTests: XCTestCase {
    private func makeSessions() -> CaptureSessionRings {
        CaptureSessionRings { SampleRing(sampleRate: 1_000, ramCapSeconds: 2, keepTailSeconds: 1) }
    }

    func testNewSessionGetsFreshRingAndLeavesPreviousAudioIntact() {
        let sessions = makeSessions()
        let a = sessions.beginSession()
        a.append([0.1, 0.2, 0.3])

        let b = sessions.beginSession()
        XCTAssertFalse(a === b)
        XCTAssertTrue(sessions.current === b)
        XCTAssertEqual(b.count, 0)
        // A's transcriber still holds all of A's audio after B starts.
        XCTAssertEqual(a.count, 3)
    }

    func testPreviousSessionCleanupDoesNotClearNewSession() {
        let sessions = makeSessions()
        let a = sessions.beginSession()
        a.append([0.1, 0.2])
        let b = sessions.beginSession()
        b.append([0.5, 0.6, 0.7, 0.8])

        // A's deferred cleanup runs after B is already recording.
        sessions.clear(a)

        XCTAssertEqual(a.count, 0)
        XCTAssertEqual(b.count, 4)
        XCTAssertEqual(sessions.current.count, 4)
        XCTAssertEqual(b.loadRange(start: 0, count: 4), [0.5, 0.6, 0.7, 0.8])
    }

    func testClearCurrentSessionResetsOnlyThatRing() {
        let sessions = makeSessions()
        let a = sessions.beginSession()
        a.append([0.1])
        sessions.clear(sessions.current)
        XCTAssertEqual(a.count, 0)
        XCTAssertTrue(sessions.current === a)
    }
}

/// EDGE-2: a start queued behind an idle-unload reload must not open the mic
/// after the user already released the key (or pressed Esc).
final class PendingDictationStartTests: XCTestCase {
    func testFirstRequestKicksOffReloadOnce() {
        var gate = PendingDictationStart()
        XCTAssertTrue(gate.request())
        XCTAssertTrue(gate.isReloading)
        XCTAssertTrue(gate.wantsStart)
        // A second press while the reload runs must not spawn another reload.
        XCTAssertFalse(gate.request())
    }

    func testStartsAfterReloadWhenStillWanted() {
        var gate = PendingDictationStart()
        _ = gate.request()
        XCTAssertTrue(gate.reloadFinished(modelLoaded: true, isRecording: false))
        XCTAssertFalse(gate.isReloading)
        XCTAssertFalse(gate.wantsStart)
    }

    func testKeyUpDuringReloadCancelsStart() {
        var gate = PendingDictationStart()
        _ = gate.request()
        XCTAssertTrue(gate.cancel())
        XCTAssertFalse(gate.reloadFinished(modelLoaded: true, isRecording: false))
    }

    func testRepressAfterReleaseReArmsStartWithoutSecondReload() {
        var gate = PendingDictationStart()
        _ = gate.request()
        _ = gate.cancel()
        XCTAssertFalse(gate.request())
        XCTAssertTrue(gate.reloadFinished(modelLoaded: true, isRecording: false))
    }

    func testFailedReloadOrAlreadyRecordingDoesNotStart() {
        var gate = PendingDictationStart()
        _ = gate.request()
        XCTAssertFalse(gate.reloadFinished(modelLoaded: false, isRecording: false))
        XCTAssertFalse(gate.wantsStart)

        _ = gate.request()
        XCTAssertFalse(gate.reloadFinished(modelLoaded: true, isRecording: true))
    }

    func testCancelWithNothingPendingReportsNoChange() {
        var gate = PendingDictationStart()
        XCTAssertFalse(gate.cancel())
    }

    func testNewRequestAfterFinishedReloadStartsAnotherReload() {
        var gate = PendingDictationStart()
        _ = gate.request()
        _ = gate.reloadFinished(modelLoaded: true, isRecording: false)
        XCTAssertTrue(gate.request())
    }
}

/// EDGE-3: "System Default" (nil / empty UID) and an unplugged UID must bind
/// the default input device instead of leaving the engine on the old device.
final class InputDeviceResolverTests: XCTestCase {
    private let available: [String: UInt32] = ["usb-mic": 42, "builtin": 7]

    func testKnownUIDBindsThatDevice() {
        XCTAssertEqual(
            InputDeviceResolver.deviceToBind(requestedUID: "usb-mic", available: available, defaultDeviceID: 7),
            42
        )
    }

    func testNilUIDBindsDefault() {
        XCTAssertEqual(
            InputDeviceResolver.deviceToBind(requestedUID: nil, available: available, defaultDeviceID: 7),
            7
        )
    }

    func testEmptyOrBlankUIDBindsDefault() {
        XCTAssertEqual(
            InputDeviceResolver.deviceToBind(requestedUID: "", available: available, defaultDeviceID: 7),
            7
        )
        XCTAssertEqual(
            InputDeviceResolver.deviceToBind(requestedUID: "  \n", available: available, defaultDeviceID: 7),
            7
        )
    }

    func testUnknownUIDBindsDefault() {
        XCTAssertEqual(
            InputDeviceResolver.deviceToBind(requestedUID: "unplugged", available: available, defaultDeviceID: 7),
            7
        )
    }

    func testUIDIsTrimmed() {
        XCTAssertEqual(
            InputDeviceResolver.deviceToBind(requestedUID: " usb-mic ", available: available, defaultDeviceID: 7),
            42
        )
    }

    func testNoDefaultAndUnknownLeavesBindingAlone() {
        XCTAssertNil(
            InputDeviceResolver.deviceToBind(requestedUID: "unplugged", available: available, defaultDeviceID: nil)
        )
    }
}

/// EDGE-4: an engine configuration change mid-dictation must restart capture.
final class CaptureConfigurationChangeTests: XCTestCase {
    func testRestartsWhileCapturing() {
        XCTAssertEqual(
            CaptureConfigurationChange.action(isCapturing: true, restartsThisSession: 0),
            .restartIntoSessionRing
        )
    }

    func testIgnoredWhenIdle() {
        XCTAssertEqual(CaptureConfigurationChange.action(isCapturing: false, restartsThisSession: 0), .ignore)
        XCTAssertEqual(CaptureConfigurationChange.action(isCapturing: false, restartsThisSession: 99), .ignore)
    }

    func testStopsInsteadOfLoopingForever() {
        let cap = CaptureConfigurationChange.maxRestartsPerSession
        XCTAssertEqual(
            CaptureConfigurationChange.action(isCapturing: true, restartsThisSession: cap - 1),
            .restartIntoSessionRing
        )
        XCTAssertEqual(CaptureConfigurationChange.action(isCapturing: true, restartsThisSession: cap), .stop)
    }

    func testUsableFormat() {
        XCTAssertTrue(CaptureConfigurationChange.canCapture(sampleRate: 48_000, channelCount: 2))
        XCTAssertFalse(CaptureConfigurationChange.canCapture(sampleRate: 0, channelCount: 1))
        XCTAssertFalse(CaptureConfigurationChange.canCapture(sampleRate: 48_000, channelCount: 0))
    }
}
