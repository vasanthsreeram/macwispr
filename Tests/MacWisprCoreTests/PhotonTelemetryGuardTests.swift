import XCTest
@testable import MacWisprCore

final class PhotonTelemetryGuardTests: XCTestCase {
    func testSourceContainsGuardBeforeMoondreamImport() throws {
        let src = PhotonServerScript.source(modelId: "moondream/parakeet-redux")
        let guardRange = try XCTUnwrap(src.range(of: PhotonServerScript.telemetryGuard))
        let importRange = try XCTUnwrap(src.range(of: "import moondream"))
        XCTAssertLessThan(guardRange.lowerBound, importRange.lowerBound)
        XCTAssertTrue(src.contains("MODEL = \"moondream/parakeet-redux\""))
        XCTAssertFalse(src.contains("__MODEL__"))
    }

    func testEnvironmentStripsMoondreamVars() {
        let base = [
            "MOONDREAM_API_KEY": "secret", "MOONDREAM_API_BASE_URL": "https://x",
            "HOME": "/Users/x",
        ]
        let env = PhotonSetupPlan.sidecarEnvironment(base: base, weightsReady: true)
        XCTAssertNil(env["MOONDREAM_API_KEY"])
        XCTAssertNil(env["MOONDREAM_API_BASE_URL"])
        XCTAssertEqual(env["HOME"], "/Users/x")
        XCTAssertEqual(env["HF_HUB_OFFLINE"], "1")
    }

    func testGuardBlocksReporterAndDNS() throws {
        let py = "/usr/bin/python3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: py), "no python3")
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("photon-guard-\(UUID().uuidString)")
        let pkg = dir.appendingPathComponent("kestrel")
        try fm.createDirectory(at: pkg, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "".write(to: pkg.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        try """
        import socket
        ATTEMPTS = []
        class PhotonReporter:
            async def validate_api_key(self): return True
            async def _flush_window(self, *, rotate=True):
                ATTEMPTS.append("flush")
                socket.create_connection(("api.moondream.ai", 443), timeout=1)
                return "sent"
        """.write(to: pkg.appendingPathComponent("photon.py"), atomically: true, encoding: .utf8)

        let script = PhotonServerScript.telemetryGuard + """

        import asyncio, json, socket
        import kestrel.photon as p
        r = p.PhotonReporter()
        flushed = asyncio.run(r._flush_window())
        valid = asyncio.run(r.validate_api_key())
        try:
            socket.getaddrinfo("api.moondream.ai", 443); dns = "resolved"
        except socket.gaierror:
            dns = "blocked"
        print(json.dumps({"attempts": len(p.ATTEMPTS), "flushed": flushed, "valid": valid, "dns": dns}))
        """
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("photon-guard-\(UUID().uuidString).py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: scriptURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: py)
        proc.arguments = [scriptURL.path]
        proc.environment = ["PYTHONPATH": dir.path]
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out; proc.standardError = err
        try proc.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["attempts"] as? Int, 0)
        XCTAssertTrue(obj["flushed"] is NSNull)
        XCTAssertEqual(obj["valid"] as? Bool, false)
        XCTAssertEqual(obj["dns"] as? String, "blocked")
    }
}
