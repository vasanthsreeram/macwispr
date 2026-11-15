import XCTest
@testable import MacWisprCore

final class LeaderboardParticipationTests: XCTestCase {
    func testOptOutKeepsTokenPendingUntilDeleteConfirmed() {
        var s = LeaderboardParticipation(optedIn: true, token: "tok-A")
        s.optOut()
        XCTAssertFalse(s.optedIn)
        XCTAssertNil(s.token)
        XCTAssertEqual(s.pendingDeletionTokens, ["tok-A"])
    }

    func testFailedDeleteKeepsPendingThenRetrySucceeds() {
        var s = LeaderboardParticipation(optedIn: true, token: "tok-A")
        s.optOut()
        s.deletionFinished(.transportError)
        XCTAssertEqual(s.pendingDeletionTokens, ["tok-A"])
        s.deletionFinished(.status(503))
        XCTAssertEqual(s.pendingDeletionTokens, ["tok-A"])
        s.deletionFinished(.status(200))
        XCTAssertEqual(s.pendingDeletionTokens, [])
    }

    func testNotFoundCountsAsDeleted() {
        var s = LeaderboardParticipation(optedIn: true, token: "tok-A")
        s.optOut()
        s.deletionFinished(.status(404))
        XCTAssertEqual(s.pendingDeletionTokens, [])
    }

    func testAuthFailureOtherThan404StaysPending() {
        XCTAssertFalse(LeaderboardParticipation.isDeletionConfirmed(.status(401)))
        XCTAssertTrue(LeaderboardParticipation.isDeletionConfirmed(.status(204)))
    }

    func testReOptInWhilePendingKeepsOldDeletionAndNewToken() {
        var s = LeaderboardParticipation(optedIn: true, token: "tok-A")
        s.optOut()
        s.optIn(newToken: "tok-B")
        XCTAssertTrue(s.optedIn)
        XCTAssertEqual(s.token, "tok-B")
        XCTAssertEqual(s.pendingDeletionTokens, ["tok-A"])
    }

    func testSecondOptOutKeepsEarlierUnconfirmedToken() {
        var s = LeaderboardParticipation(optedIn: true, token: "tok-A")
        s.optOut()
        s.optIn(newToken: "tok-B")
        s.optOut()
        XCTAssertEqual(s.pendingDeletionTokens, ["tok-A", "tok-B"])
        s.deletionFinished(.status(204), token: "tok-A")
        XCTAssertEqual(s.nextDeletionToken, "tok-B")
    }

    func testSyncResultsIgnoredWhenNotOptedInOrTokenChanged() {
        var s = LeaderboardParticipation(optedIn: true, token: "tok-A")
        XCTAssertTrue(s.shouldApplySyncResult(forToken: "tok-A"))
        XCTAssertFalse(s.shouldApplySyncResult(forToken: "tok-X"))
        s.optOut()
        XCTAssertFalse(s.shouldApplySyncResult(forToken: "tok-A"))
    }

    func testOptOutWithoutTokenHasNothingPending() {
        var s = LeaderboardParticipation(optedIn: true, token: nil)
        s.optOut()
        XCTAssertEqual(s.pendingDeletionTokens, [])
    }
}

final class DevCaptureDirectoryTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devcap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func addCapture(_ root: URL, _ name: String) throws {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("audio.wav"))
        try "hello".write(to: dir.appendingPathComponent("03_polished.txt"), atomically: true, encoding: .utf8)
    }

    func testCountCountsOnlyDirectories() throws {
        let root = try makeRoot()
        try addCapture(root, "a")
        try addCapture(root, "b")
        try Data().write(to: root.appendingPathComponent("stray.txt"))
        XCTAssertEqual(DevCaptureDirectory.count(in: root), 2)
    }

    func testClearAllRemovesEverything() throws {
        let root = try makeRoot()
        try addCapture(root, "a")
        try Data().write(to: root.appendingPathComponent(".DS_Store"))
        DevCaptureDirectory.clearAll(in: root)
        XCTAssertEqual(DevCaptureDirectory.count(in: root), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testClearHistoryPathEmptiesCapturesEvenWhenPrefIsOn() throws {
        let root = try makeRoot()
        try addCapture(root, "a")
        let defaults = UserDefaults(suiteName: "devcap-test-\(UUID().uuidString)")!
        defaults.set(true, forKey: "devCaptureEnabled")
        DevCaptureDirectory.clearAll(in: root)
        XCTAssertEqual(DevCaptureDirectory.count(in: root), 0)
        // Clearing must not flip the preference.
        XCTAssertTrue(defaults.bool(forKey: "devCaptureEnabled"))
    }
}
