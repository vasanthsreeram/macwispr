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

    func testHistoryClearingEmptiesCapturesAndClearsEntries() throws {
        let root = try makeRoot()
        try addCapture(root, "a")
        try addCapture(root, "b")
        var cleared = false
        HistoryClearing.clear(clearEntries: { cleared = true }, devCaptureRoot: root)
        XCTAssertTrue(cleared)
        XCTAssertEqual(DevCaptureDirectory.count(in: root), 0)
    }
}

final class LeaderboardDeletionCoordinatorTests: XCTestCase {
    /// In-memory "UserDefaults" + scripted server; survives across coordinator instances (relaunch).
    final class Env: @unchecked Sendable {
        var pending: [String] = []
        var outcomes: [LeaderboardParticipation.DeletionOutcome] = []
        var sent: [String] = []
        func make() -> LeaderboardDeletionCoordinator {
            LeaderboardDeletionCoordinator(
                load: { self.pending }, save: { self.pending = $0 },
                send: { token, done in
                    self.sent.append(token)
                    done(self.outcomes.isEmpty ? .status(204) : self.outcomes.removeFirst())
                })
        }
    }

    func testOfflineOptOutPersistsTokenThenRetryOnLaunchDeletes() {
        let env = Env()
        env.outcomes = [.transportError]
        env.make().optOut(token: "tok-A")
        XCTAssertEqual(env.pending, ["tok-A"])      // kept, not dropped
        XCTAssertEqual(env.sent, ["tok-A"])
        env.make().attempt()                        // "relaunch"
        XCTAssertEqual(env.sent, ["tok-A", "tok-A"])
        XCTAssertEqual(env.pending, [])
    }

    func testServerErrorKeepsPendingAndNotFoundClears() {
        let env = Env()
        env.outcomes = [.status(503), .status(404)]
        let c = env.make()
        c.optOut(token: "tok-A")
        XCTAssertEqual(env.pending, ["tok-A"])
        c.attempt()
        XCTAssertEqual(env.pending, [])
    }

    func testQueuedTokensDrainAfterSuccess() {
        let env = Env()
        env.pending = ["tok-A"]
        env.make().optOut(token: "tok-B")
        XCTAssertEqual(env.sent, ["tok-A", "tok-B"])
        XCTAssertEqual(env.pending, [])
    }

    func testOptOutWithoutTokenSendsNothing() {
        let env = Env()
        env.make().optOut(token: nil)
        XCTAssertEqual(env.sent, [])
    }
}
