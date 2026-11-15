import XCTest
@testable import MacWisprCore

final class LossyJSONArrayFileTests: XCTestCase {
    struct Row: Codable, Equatable { let id: Int; let wordCount: Int }

    private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lossy-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func quarantined() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.contains(".corrupt-") }
    }

    func testBadEntrySkippedOthersSurviveRoundTrip() throws {
        let url = dir.appendingPathComponent("history.json")
        let raw = #"[{"id":1,"wordCount":2},{"id":2,"wordCount":"x"},{"id":3,"wordCount":4}]"#
        try Data(raw.utf8).write(to: url)
        let r = LossyJSONArrayFile.load(Row.self, from: url)
        XCTAssertEqual(r.items, [Row(id: 1, wordCount: 2), Row(id: 3, wordCount: 4)])
        XCTAssertEqual(r.skipped, 1)
        XCTAssertTrue(r.safeToOverwrite)
        // Original still intact; copy preserved with original bytes.
        XCTAssertEqual(try Data(contentsOf: url), Data(raw.utf8))
        XCTAssertEqual(quarantined().count, 1)
        XCTAssertEqual(try Data(contentsOf: quarantined()[0]), Data(raw.utf8))
        // Save + reload round trip keeps good entries.
        try JSONEncoder().encode(r.items).write(to: url)
        XCTAssertEqual(LossyJSONArrayFile.load(Row.self, from: url).items, r.items)
    }

    func testGarbageFileQuarantinedWithOriginalBytes() throws {
        let url = dir.appendingPathComponent("history.json")
        let raw = Data("{not an array".utf8)
        try raw.write(to: url)
        let r = LossyJSONArrayFile.load(Row.self, from: url)
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertTrue(r.safeToOverwrite)
        XCTAssertEqual(quarantined().count, 1)
        XCTAssertEqual(try Data(contentsOf: quarantined()[0]), raw)
        XCTAssertEqual(r.quarantineURL?.lastPathComponent, quarantined()[0].lastPathComponent)
    }

    func testNonArrayJSONQuarantined() throws {
        let url = dir.appendingPathComponent("history.json")
        try Data(#"{"a":1}"#.utf8).write(to: url)
        _ = LossyJSONArrayFile.load(Row.self, from: url)
        XCTAssertEqual(quarantined().count, 1)
    }

    func testValidFileUnchangedNoQuarantine() throws {
        let url = dir.appendingPathComponent("history.json")
        let rows = [Row(id: 1, wordCount: 2), Row(id: 2, wordCount: 3)]
        try JSONEncoder().encode(rows).write(to: url)
        let r = LossyJSONArrayFile.load(Row.self, from: url)
        XCTAssertEqual(r.items, rows)
        XCTAssertEqual(r.skipped, 0)
        XCTAssertTrue(quarantined().isEmpty)
    }

    func testMissingFileIsEmptyAndSafe() {
        let r = LossyJSONArrayFile.load(Row.self, from: dir.appendingPathComponent("history.json"))
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertTrue(r.safeToOverwrite)
        XCTAssertTrue(quarantined().isEmpty)
    }

    func testRepeatedQuarantineSameSecondDoesNotCollide() throws {
        let url = dir.appendingPathComponent("history.json")
        let now = Date()
        for _ in 0..<2 {
            try Data("junk".utf8).write(to: url)
            _ = LossyJSONArrayFile.load(Row.self, from: url, now: now)
        }
        XCTAssertEqual(quarantined().count, 2)
    }
}
