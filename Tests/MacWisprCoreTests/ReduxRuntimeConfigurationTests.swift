import Foundation
import XCTest
@testable import MacWisprCore

final class ReduxRuntimeConfigurationTests: XCTestCase {
    private func isolatedDefaults() throws -> UserDefaults {
        let name = "MacWispr.ReduxRuntimeConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testEmptyPreferencesUsePhotonWithoutWritingDefaults() throws {
        let defaults = try isolatedDefaults()
        let before = defaults.dictionaryRepresentation()
        let configuration = ReduxRuntimeConfiguration.load(defaults: defaults, environment: [:])
        XCTAssertEqual(configuration.runtime, .photon)
        XCTAssertEqual(configuration.pythonPath, "/opt/homebrew/bin/python3")
        XCTAssertEqual(configuration.weightsPath, "")
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
    }

    func testExplicitStoreAndLoadRoundTrip() throws {
        let defaults = try isolatedDefaults()
        let configuration = ReduxRuntimeConfiguration(
            runtime: .mlx, pythonPath: "/tmp/candidate env/bin/python3", weightsPath: "/tmp/converted weights"
        )
        configuration.store(defaults: defaults)
        XCTAssertEqual(ReduxRuntimeConfiguration.load(defaults: defaults, environment: [:]), configuration)
        XCTAssertEqual(defaults.string(forKey: ReduxRuntimeConfiguration.runtimeKey), "mlx")
        XCTAssertEqual(defaults.string(forKey: ReduxRuntimeConfiguration.pythonKey), "/tmp/candidate env/bin/python3")
        XCTAssertEqual(defaults.string(forKey: ReduxRuntimeConfiguration.weightsKey), "/tmp/converted weights")
    }

    func testEnvironmentOverridesPreferencesWithoutPersistingOverrides() throws {
        let defaults = try isolatedDefaults()
        let stored = ReduxRuntimeConfiguration(runtime: .photon, pythonPath: "/saved/python", weightsPath: "/saved/weights")
        stored.store(defaults: defaults)
        let loaded = ReduxRuntimeConfiguration.load(defaults: defaults, environment: [
            "MACWISPR_REDUX_RUNTIME": "mlx",
            "MACWISPR_REDUX_MLX_PYTHON": "/env/python",
            "MACWISPR_REDUX_MLX_WEIGHTS": "/env/weights",
        ])
        XCTAssertEqual(loaded, ReduxRuntimeConfiguration(runtime: .mlx, pythonPath: "/env/python", weightsPath: "/env/weights"))
        XCTAssertEqual(ReduxRuntimeConfiguration.load(defaults: defaults, environment: [:]), stored)
    }

    func testPartialEnvironmentPreservesOtherPreferences() throws {
        let defaults = try isolatedDefaults()
        ReduxRuntimeConfiguration(runtime: .mlx, pythonPath: "/saved/python", weightsPath: "/saved/weights")
            .store(defaults: defaults)
        let loaded = ReduxRuntimeConfiguration.load(defaults: defaults, environment: ["MACWISPR_REDUX_RUNTIME": "photon"])
        XCTAssertEqual(loaded, ReduxRuntimeConfiguration(runtime: .photon, pythonPath: "/saved/python", weightsPath: "/saved/weights"))
    }

    func testUnknownSavedRuntimeFallsBackWithoutChangingPreferences() throws {
        let defaults = try isolatedDefaults()
        defaults.set("future-runtime", forKey: ReduxRuntimeConfiguration.runtimeKey)
        let loaded = ReduxRuntimeConfiguration.load(defaults: defaults, environment: [:])
        XCTAssertEqual(loaded.runtime, .photon)
        XCTAssertEqual(defaults.string(forKey: ReduxRuntimeConfiguration.runtimeKey), "future-runtime")
        defaults.set("mlx", forKey: ReduxRuntimeConfiguration.runtimeKey)
        XCTAssertEqual(ReduxRuntimeConfiguration.load(defaults: defaults, environment: [:]).runtime, .mlx)
    }

    func testEmptyExplicitPathsAreNotReplacedWithDefaults() throws {
        let defaults = try isolatedDefaults()
        let loaded = ReduxRuntimeConfiguration.load(defaults: defaults, environment: [
            "MACWISPR_REDUX_RUNTIME": "mlx",
            "MACWISPR_REDUX_MLX_PYTHON": "",
            "MACWISPR_REDUX_MLX_WEIGHTS": "",
        ])
        XCTAssertEqual(loaded, ReduxRuntimeConfiguration(runtime: .mlx, pythonPath: "", weightsPath: ""))
    }

    func testDiagnosticsDecodeAndEncodePythonWireKeys() throws {
        let json = Data("""
        {"backend":"redux-mlx","pid":123,"weights_sha256":"abc123",
         "active_gpu_bytes":100,"peak_gpu_bytes":200,"cache_gpu_bytes":50,"process_peak_rss_bytes":4096}
        """.utf8)
        let expected = ReduxRuntimeDiagnostics(
            backend: "redux-mlx", pid: 123, weightsSHA256: "abc123",
            activeGPUBytes: 100, peakGPUBytes: 200, cacheGPUBytes: 50, processPeakRSSBytes: 4096
        )
        let decoded = try JSONDecoder().decode(ReduxRuntimeDiagnostics.self, from: json)
        XCTAssertEqual(decoded, expected)
        let encoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: json) as? NSDictionary)
    }

    func testDiagnosticsRequireAllCountersAndAnIntegerPID() throws {
        for json in [
            "{\"backend\":\"redux-mlx\",\"pid\":123}",
            """
            {"backend":"redux-mlx","pid":1.5,"weights_sha256":"abc",
             "active_gpu_bytes":100,"peak_gpu_bytes":200,"cache_gpu_bytes":50,"process_peak_rss_bytes":4096}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(ReduxRuntimeDiagnostics.self, from: Data(json.utf8)))
        }
        let complete = ReduxRuntimeDiagnostics(
            backend: "redux-mlx", pid: 1, weightsSHA256: "abc", activeGPUBytes: 1,
            peakGPUBytes: 2, cacheGPUBytes: 0, processPeakRSSBytes: 3
        )
        XCTAssertEqual(try JSONDecoder().decode(ReduxRuntimeDiagnostics.self, from: JSONEncoder().encode(complete)), complete)
    }
}
