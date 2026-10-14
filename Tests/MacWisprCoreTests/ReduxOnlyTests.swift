import XCTest
@testable import MacWisprCore

final class ModelCatalogTests: XCTestCase {
    func testOnlyParakeetReduxIsOffered() {
        XCTAssertEqual(ModelCatalog.available, ["Parakeet-Redux"])
        XCTAssertEqual(ModelCatalog.defaultModelID, "Parakeet-Redux")
        XCTAssertEqual(ModelCatalog.shippedRepoID, "moondream/parakeet-redux")
        XCTAssertEqual(ModelCatalog.shippedDisplayName, "Parakeet Redux")
    }

    func testOldSelectionsMigrateToRedux() {
        // Raw values saved by earlier builds (Qwen 0.6B / 1.7B, Parakeet v3 INT4 / INT8).
        for legacy in ["0.6B", "1.7B", "Parakeet-INT4", "Parakeet-INT8", "garbage", ""] {
            XCTAssertEqual(ModelCatalog.migrate(savedModelID: legacy), "Parakeet-Redux", legacy)
        }
        XCTAssertEqual(ModelCatalog.migrate(savedModelID: nil), "Parakeet-Redux")
        XCTAssertEqual(ModelCatalog.migrate(savedModelID: "Parakeet-Redux"), "Parakeet-Redux")
    }

    func testSidebarHasThreePanes() {
        XCTAssertEqual(MainPane.allCases, [.home, .history, .settings])
        XCTAssertEqual(MainPane.allCases.map(\.title), ["Home", "History", "Settings"])
    }
}

final class PhotonSetupPlanTests: XCTestCase {
    let root = URL(fileURLWithPath: "/tmp/mw-photon-root")

    func testPrefersBundledUVWithManagedPython() throws {
        let plan = try XCTUnwrap(PhotonSetupPlan.make(
            root: root, uvPath: "/App/Contents/Helpers/uv", pythonPath: "/opt/homebrew/bin/python3"))
        XCTAssertEqual(plan.method, .uv)
        XCTAssertEqual(plan.steps.count, 2)
        let venv = plan.steps[0]
        XCTAssertEqual(venv.executable, "/App/Contents/Helpers/uv")
        XCTAssertTrue(venv.arguments.contains("--managed-python"))
        XCTAssertEqual(venv.arguments.last, "/tmp/mw-photon-root/venv")
        let install = plan.steps[1]
        XCTAssertEqual(Array(install.arguments.prefix(2)), ["pip", "install"])
        XCTAssertTrue(install.arguments.contains("moondream==2.6.1"))
        XCTAssertEqual(install.environment["UV_PYTHON_INSTALL_DIR"], "/tmp/mw-photon-root/python")
        XCTAssertEqual(install.environment["UV_CACHE_DIR"], "/tmp/mw-photon-root/uv-cache")
        XCTAssertEqual(plan.venvPython.path, "/tmp/mw-photon-root/venv/bin/python")
    }

    func testFallsBackToPipWithoutUV() throws {
        let plan = try XCTUnwrap(PhotonSetupPlan.make(root: root, uvPath: nil, pythonPath: "/usr/local/bin/python3"))
        XCTAssertEqual(plan.method, .pip)
        XCTAssertEqual(plan.steps[0].arguments, ["-m", "venv", "/tmp/mw-photon-root/venv"])
        XCTAssertEqual(plan.steps[1].executable, "/tmp/mw-photon-root/venv/bin/python")
    }

    func testNoRuntimeWithoutUVOrPython() {
        XCTAssertNil(PhotonSetupPlan.make(root: root, uvPath: nil, pythonPath: nil))
    }

    func testServerGoesOfflineOnlyOnceWeightsExist() {
        XCTAssertNil(PhotonSetupPlan.serverEnvironment(weightsReady: false)["HF_HUB_OFFLINE"])
        XCTAssertEqual(PhotonSetupPlan.serverEnvironment(weightsReady: true)["HF_HUB_OFFLINE"], "1")
    }
}

final class InsertionDecisionTests: XCTestCase {
    func testPastesWhenAllowed() {
        XCTAssertEqual(InsertionDecision.decide(typeOut: false, canPostEvents: true, secureInputActive: false), .copyAndPaste)
        XCTAssertEqual(InsertionDecision.decide(typeOut: true, canPostEvents: true, secureInputActive: false), .typeOut)
    }

    func testWithoutAccessibilityOnlyCopies() {
        XCTAssertEqual(
            InsertionDecision.decide(typeOut: false, canPostEvents: false, secureInputActive: false),
            .copyOnly(reason: InsertionDecision.needsAccessibility))
    }

    func testSecureInputBlocksSyntheticPaste() {
        XCTAssertEqual(
            InsertionDecision.decide(typeOut: false, canPostEvents: true, secureInputActive: true),
            .copyOnly(reason: InsertionDecision.secureInput))
    }

    func testAccessibilityResetTargetsOnlyThisApp() {
        XCTAssertEqual(
            AccessibilityRepair.resetArguments(bundleID: "com.vasanthsreeram.macwispr"),
            ["reset", "Accessibility", "com.vasanthsreeram.macwispr"])
    }
}
