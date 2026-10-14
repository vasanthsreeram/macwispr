import Foundation
import MacWisprCore

/// Runs Moondream's Photon runtime (Python) as a child process so MacWispr can
/// use `moondream/parakeet-redux`, which only Photon can execute.
///
/// First load installs the runtime into Application Support with the `uv`
/// binary bundled in the app (uv-managed Python, no system Python needed).
/// Protocol: one JSON object per line on stdin/stdout.
final class PhotonSidecar: @unchecked Sendable {
    enum SidecarError: LocalizedError {
        case runtimeUnavailable
        case setupFailed(String)
        case startFailed(String)
        case transcribeFailed(String)

        var errorDescription: String? {
            switch self {
            case .runtimeUnavailable:
                return "The speech runtime installer is missing from MacWispr. Reinstall the app."
            case .setupFailed(let m): return "Speech model setup failed: \(m)"
            case .startFailed(let m): return "Speech model failed to start: \(m)"
            case .transcribeFailed(let m): return "Transcription failed: \(m)"
            }
        }
    }

    static let modelId = ModelCatalog.shippedRepoID

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("MacWispr", isDirectory: true)
            .appendingPathComponent("photon", isDirectory: true)
    }

    private static var readyMarker: URL {
        rootDirectory.appendingPathComponent(".ready-\(PhotonSetupPlan.runtimeVersion)")
    }

    static var serverScript: URL {
        rootDirectory.appendingPathComponent("photon_server.py")
    }

    static var venvPython: URL {
        PhotonSetupPlan.venvDirectory(root: rootDirectory).appendingPathComponent("bin/python")
    }

    /// Hugging Face cache folder for the Redux weights.
    static var weightsDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        let hub: URL
        if let h = env["HF_HUB_CACHE"], !h.isEmpty {
            hub = URL(fileURLWithPath: h)
        } else if let home = env["HF_HOME"], !home.isEmpty {
            hub = URL(fileURLWithPath: home).appendingPathComponent("hub")
        } else {
            hub = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub")
        }
        return hub.appendingPathComponent("models--moondream--parakeet-redux", isDirectory: true)
    }

    static var weightsOnDisk: Bool {
        let snapshots = weightsDirectory.appendingPathComponent("snapshots")
        guard let revs = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else { return false }
        return revs.contains { rev in
            // Hub snapshots are symlinks into blobs/; measure the target file.
            let file = snapshots.appendingPathComponent(rev).appendingPathComponent("model.safetensors")
                .resolvingSymlinksInPath()
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            return size > 100_000_000
        }
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
            && FileManager.default.fileExists(atPath: readyMarker.path)
    }

    /// Runtime and weights are both on disk; loading needs no network.
    static var isReady: Bool { isInstalled && weightsOnDisk }

    /// Remove the runtime and the downloaded weights.
    static func uninstall() {
        try? FileManager.default.removeItem(at: rootDirectory)
        try? FileManager.default.removeItem(at: weightsDirectory)
    }

    /// `uv` shipped inside MacWispr.app (Contents/Helpers/uv), else a dev install.
    static func bundledUV() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["MACWISPR_UV"], !env.isEmpty {
            candidates.append(env)
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/uv").path)
        if Bundle.main.bundleURL.pathExtension != "app" {
            // `swift run` / tests: fall back to a user install.
            candidates += [
                fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv").path,
                "/opt/homebrew/bin/uv",
            ]
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    private static func systemPython() -> String? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func setupPlan() -> PhotonSetupPlan? {
        PhotonSetupPlan.make(root: rootDirectory, uvPath: bundledUV(), pythonPath: systemPython())
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var buffer = Data()
    private let lock = NSLock()

    // MARK: - Setup

    /// Approximate download size of the runtime (torch dominates).
    private static let expectedRuntimeBytes: Double = 700_000_000

    private static func directorySize(_ url: URL) -> Double {
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []
        ) else { return 0 }
        var total = 0
        for case let f as URL in e {
            total += (try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        }
        return Double(total)
    }

    private static func run(
        _ step: PhotonSetupPlan.Step,
        progressRange: ClosedRange<Double>? = nil,
        watch: URL? = nil,
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: step.executable)
        p.arguments = step.arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in step.environment { env[k] = v }
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        // Long pip-style installs print nothing with --quiet; report progress
        // from how much of the runtime has landed on disk.
        var watcher: Thread?
        if let range = progressRange, let watch, let progress {
            let t = Thread {
                while p.isRunning {
                    let frac = min(1, directorySize(watch) / expectedRuntimeBytes)
                    let value = range.lowerBound + (range.upperBound - range.lowerBound) * frac
                    progress(value, "\(step.label.replacingOccurrences(of: "…", with: "")) \(Int(frac * 100))%")
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            t.start()
            watcher = t
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        _ = watcher
        guard p.terminationStatus == 0 else {
            let out = String(decoding: data, as: UTF8.self)
            throw SidecarError.setupFailed(String(out.suffix(400)))
        }
    }

    /// Install the Photon runtime. Returns the method used (for logs / timing).
    @discardableResult
    static func installRuntime(progress: @escaping @Sendable (Double, String) -> Void) throws -> PhotonSetupPlan.Method {
        guard let plan = setupPlan() else { throw SidecarError.runtimeUnavailable }
        let fm = FileManager.default
        // Start clean so a half-finished or older runtime never lingers.
        try? fm.removeItem(at: plan.venvDirectory)
        if let old = try? fm.contentsOfDirectory(atPath: rootDirectory.path) {
            for name in old where name.hasPrefix(".ready") {
                try? fm.removeItem(at: rootDirectory.appendingPathComponent(name))
            }
        }
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        for (i, step) in plan.steps.enumerated() {
            progress(step.progress, step.label)
            let isInstall = i == plan.steps.count - 1
            let watch = plan.method == .uv
                ? rootDirectory.appendingPathComponent("uv-cache")
                : plan.venvDirectory
            try run(
                step,
                progressRange: isInstall ? step.progress...0.4 : nil,
                watch: isInstall ? watch : nil,
                progress: progress
            )
        }
        // The download cache is only needed during install.
        try? fm.removeItem(at: rootDirectory.appendingPathComponent("uv-cache"))
        fm.createFile(atPath: readyMarker.path, contents: Data(plan.method.rawValue.utf8))
        NSLog("MacWispr: Photon runtime installed via %@", plan.method.rawValue)
        return plan.method
    }

    /// Sidecar server. Reports download progress while fetching the weights,
    /// then `{"ready": true}`. Each request `{"wav": path}` → `{"text": ...}`.
    static let serverSource = """
    import sys, json, os, warnings
    warnings.filterwarnings("ignore")
    def emit(obj):
        sys.stdout.write(json.dumps(obj) + "\\n"); sys.stdout.flush()
    MODEL = "\(modelId)"
    try:
        from huggingface_hub import snapshot_download
        if os.environ.get("HF_HUB_OFFLINE") != "1":
            emit({"status": "Downloading Parakeet Redux (about 180 MB)…", "progress": 0.45})
            snapshot_download(MODEL)
        emit({"status": "Loading Parakeet Redux…", "progress": 0.85})
        import moondream as md
        speech = md.photon(MODEL, device="mps")
    except Exception as e:
        emit({"error": "load: " + str(e)}); sys.exit(1)
    emit({"ready": True})
    for line in sys.stdin:
        try:
            req = json.loads(line)
            res = speech.transcribe(audio=req["wav"])
            out = {"text": res.get("text", "")}
        except Exception as e:
            out = {"error": str(e)}
        emit(out)
    """

    // MARK: - Lifecycle

    func start(progress: @escaping @Sendable (Double, String) -> Void) throws {
        if !Self.isInstalled {
            try Self.installRuntime(progress: progress)
        }
        try Self.serverSource.write(to: Self.serverScript, atomically: true, encoding: .utf8)

        let weightsReady = Self.weightsOnDisk
        progress(0.4, weightsReady ? "Loading Parakeet Redux…" : "Downloading Parakeet Redux (about 180 MB)…")
        let p = Process()
        p.executableURL = Self.venvPython
        p.arguments = ["-u", Self.serverScript.path]
        var env = ProcessInfo.processInfo.environment
        for (k, v) in PhotonSetupPlan.serverEnvironment(weightsReady: weightsReady) { env[k] = v }
        p.environment = env
        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
        stdout = outPipe.fileHandleForReading

        while true {
            guard let line = try readLine() else {
                stop()
                throw SidecarError.startFailed("speech runtime exited during load")
            }
            if line["ready"] as? Bool == true { return }
            if let err = line["error"] as? String {
                stop()
                throw SidecarError.startFailed(err)
            }
            if let status = line["status"] as? String {
                progress(line["progress"] as? Double ?? 0.5, status)
            }
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        try? stdin?.close()
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        buffer = Data()
    }

    var isRunning: Bool { process?.isRunning == true }

    deinit { stop() }

    // MARK: - Transcription

    func transcribe(samples: [Float]) throws -> String {
        guard let stdin, process?.isRunning == true else {
            throw SidecarError.transcribeFailed("speech runtime is not running")
        }
        let wav = FileManager.default.temporaryDirectory
            .appendingPathComponent("macwispr-photon-\(UUID().uuidString).wav")
        try AudioWAVEncoder.encode(samples: samples, sampleRate: 16_000).write(to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }

        let req = try JSONSerialization.data(withJSONObject: ["wav": wav.path])
        stdin.write(req + Data("\n".utf8))
        guard let resp = try readLine() else {
            throw SidecarError.transcribeFailed("speech runtime exited")
        }
        if let err = resp["error"] as? String { throw SidecarError.transcribeFailed(err) }
        return (resp["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readLine() throws -> [String: Any]? {
        guard let stdout else { return nil }
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    return obj
                }
                continue
            }
            let chunk = stdout.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
