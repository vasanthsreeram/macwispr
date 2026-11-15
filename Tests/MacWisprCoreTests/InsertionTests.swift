import AppKit
import XCTest
@testable import MacWisprCore

/// UX-1: each insertion mode, with Accessibility granted and no Secure Input.
final class InsertionModeTests: XCTestCase {
    func testCopyOnlyNeverSendsKeys() {
        XCTAssertEqual(InsertionDecision.decide(mode: .copyOnly, canPostEvents: true, secureInputActive: false), .copy)
    }

    func testPasteSendsCommandV() {
        XCTAssertEqual(InsertionDecision.decide(mode: .paste, canPostEvents: true, secureInputActive: false), .copyAndPaste)
    }

    func testTypeOutTypes() {
        XCTAssertEqual(InsertionDecision.decide(mode: .typeOut, canPostEvents: true, secureInputActive: false), .typeOut)
    }

    /// Copy only is what the user asked for, so a missing grant or a password
    /// field is no reason for a failure banner.
    func testCopyOnlyIsSuccessEvenWithoutAccessibilityOrWithSecureInput() {
        XCTAssertEqual(InsertionDecision.decide(mode: .copyOnly, canPostEvents: false, secureInputActive: false), .copy)
        XCTAssertEqual(InsertionDecision.decide(mode: .copyOnly, canPostEvents: true, secureInputActive: true), .copy)
    }

    func testTypeOutFallsBackToCopyWhenBlocked() {
        XCTAssertEqual(
            InsertionDecision.decide(mode: .typeOut, canPostEvents: false, secureInputActive: false),
            .copyOnly(reason: InsertionDecision.needsAccessibility))
        XCTAssertEqual(
            InsertionDecision.decide(mode: .typeOut, canPostEvents: true, secureInputActive: true),
            .copyOnly(reason: InsertionDecision.secureInput))
    }
}

/// CR-3: ⌘V must use the key that types "v" in the current layout while ⌘ is held.
final class PasteKeyTests: XCTestCase {
    /// ANSI positions of the letters that differ in the fakes below.
    private static let qwerty: [UInt16: String] = [0x09: "v", 0x28: "k", 0x2F: "."]
    private static let dvorak: [UInt16: String] = [0x09: "k", 0x28: "t", 0x2F: "v"]

    func testQwertyUsesAnsiV() {
        XCTAssertEqual(PasteKey.keyCode { code, _ in Self.qwerty[code] }, 0x09)
    }

    func testDvorakUsesThePhysicalKeyThatTypesV() {
        XCTAssertEqual(PasteKey.keyCode { code, _ in Self.dvorak[code] }, 0x2F)
    }

    /// "Dvorak - QWERTY ⌘" switches to QWERTY while ⌘ is down, so ⌘ + ANSI V
    /// already pastes; resolving without ⌘ would pick 0x2F (⌘.) instead.
    func testDvorakQwertyCommandResolvesWithCommandHeld() {
        let keyCode = PasteKey.keyCode { code, commandHeld in
            commandHeld ? Self.qwerty[code] : Self.dvorak[code]
        }
        XCTAssertEqual(keyCode, 0x09)
    }

    func testFallsBackToAnsiVWhenNoKeyTypesV() {
        XCTAssertEqual(PasteKey.keyCode { _, _ in nil }, 0x09)
        XCTAssertEqual(PasteKey.keyCode { _, _ in "ж" }, 0x09)
    }

    func testUppercaseVCounts() {
        XCTAssertEqual(PasteKey.keyCode { code, _ in code == 0x2F ? "V" : nil }, 0x2F)
    }
}

/// UX-2: the transcript borrows the clipboard only for the paste.
final class ClipboardPolicyTests: XCTestCase {
    func testPasteMarksTransientAndRestores() {
        XCTAssertEqual(
            ClipboardPolicy.write(for: .copyAndPaste, secureInputActive: false),
            ClipboardWrite(transient: true, concealed: false, restoreAfterPaste: true))
    }

    func testCopyOnlyLeavesTextAndNeverRestores() {
        let plan = ClipboardPolicy.write(for: .copy, secureInputActive: false)
        XCTAssertEqual(plan, ClipboardWrite(transient: false, concealed: false, restoreAfterPaste: false))
    }

    func testTypeOutLeavesClipboardUntouched() {
        XCTAssertNil(ClipboardPolicy.write(for: .typeOut, secureInputActive: false))
    }

    /// Blocked paste/type: the user must press ⌘V, so the text stays put.
    func testFallbackCopyStaysAndIsConcealedUnderSecureInput() {
        XCTAssertEqual(
            ClipboardPolicy.write(for: .copyOnly(reason: InsertionDecision.secureInput), secureInputActive: true),
            ClipboardWrite(transient: false, concealed: true, restoreAfterPaste: false))
        XCTAssertEqual(
            ClipboardPolicy.write(for: .copyOnly(reason: InsertionDecision.needsAccessibility), secureInputActive: false),
            ClipboardWrite(transient: false, concealed: false, restoreAfterPaste: false))
    }

    func testRestoresOnlyIfClipboardIsStillOurs() {
        XCTAssertTrue(ClipboardPolicy.shouldRestore(changeCountAfterWrite: 42, currentChangeCount: 42))
        // User copied something during the delay: keep their copy.
        XCTAssertFalse(ClipboardPolicy.shouldRestore(changeCountAfterWrite: 42, currentChangeCount: 43))
    }

    func testRestoreDelayLetsThePasteLand() {
        XCTAssertGreaterThanOrEqual(ClipboardPolicy.restoreDelay, 0.5)
        XCTAssertLessThanOrEqual(ClipboardPolicy.restoreDelay, 1.0)
    }
}

/// UX-2 against a real (private, uniquely named) pasteboard.
final class PasteboardTransferTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.macwispr.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
    }

    private let richType = NSPasteboard.PasteboardType("com.macwispr.tests.rich")

    private func seedUserClipboard() {
        let item = NSPasteboardItem()
        item.setString("user text", forType: .string)
        item.setData(Data([1, 2, 3]), forType: richType)
        let second = NSPasteboardItem()
        second.setString("second item", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item, second])
    }

    func testPasteRoundTripRestoresEveryItemAndType() throws {
        seedUserClipboard()
        let session = PasteboardTransfer.begin(
            text: "dictated", plan: ClipboardWrite(transient: true, concealed: false, restoreAfterPaste: true),
            on: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "dictated")
        XCTAssertTrue(pasteboard.types?.contains(PasteboardTransfer.transientType) ?? false)
        XCTAssertFalse(pasteboard.types?.contains(PasteboardTransfer.concealedType) ?? true)

        XCTAssertTrue(PasteboardTransfer.finish(try XCTUnwrap(session), on: pasteboard))
        let items = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.string(forType: .string), "user text")
        XCTAssertEqual(items.first?.data(forType: richType), Data([1, 2, 3]))
        XCTAssertEqual(items.last?.string(forType: .string), "second item")
    }

    func testUserCopyDuringDelayIsKept() throws {
        seedUserClipboard()
        let session = PasteboardTransfer.begin(
            text: "dictated", plan: ClipboardWrite(transient: true, concealed: false, restoreAfterPaste: true),
            on: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied meanwhile", forType: .string)

        XCTAssertFalse(PasteboardTransfer.finish(try XCTUnwrap(session), on: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
    }

    /// Two dictations inside the restore delay: the second must still bring
    /// back the user's clipboard, not the first transcript.
    func testBackToBackPastesRestoreTheOriginalClipboard() {
        seedUserClipboard()
        let plan = ClipboardWrite(transient: true, concealed: false, restoreAfterPaste: true)
        let first = PasteboardTransfer.begin(text: "one", plan: plan, on: pasteboard)
        let second = PasteboardTransfer.begin(text: "two", plan: plan, on: pasteboard, pending: first)

        XCTAssertFalse(PasteboardTransfer.finish(first!, on: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "two")
        XCTAssertTrue(PasteboardTransfer.finish(second!, on: pasteboard))
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.string(forType: .string), "user text")
    }

    func testCopyOnlyLeavesPlainTextAndNoRestoreSession() {
        seedUserClipboard()
        let session = PasteboardTransfer.begin(
            text: "keep me", plan: ClipboardWrite(transient: false, concealed: false, restoreAfterPaste: false),
            on: pasteboard)
        XCTAssertNil(session)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
        XCTAssertFalse(pasteboard.types?.contains(PasteboardTransfer.transientType) ?? true)
    }

    func testSecureInputMarksConcealed() {
        _ = PasteboardTransfer.begin(
            text: "secret", plan: ClipboardWrite(transient: false, concealed: true, restoreAfterPaste: false),
            on: pasteboard)
        XCTAssertTrue(pasteboard.types?.contains(PasteboardTransfer.concealedType) ?? false)
    }
}
