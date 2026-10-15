import Darwin
import Foundation
import MacWisprCore

/// Persistent, offline Python MLX runtime. Installation and outer audio chunking belong to the caller.
final class ReduxMLXSidecar: @unchecked Sendable {
    struct SidecarError: LocalizedError {
        let message: String
        var errorDescription: String? {
            "Redux MLX: \(message) Select Photon manually to use the reference runtime."
        }
    }

    private struct Response: Decodable {
        let ready: Bool?
        let status: String?
        let progress: Double?
        let error: String?
        let text: String?
        let diagnostics: ReduxRuntimeDiagnostics?
    }

    private final class Session {
        let process: Process
        let input: FileHandle
        let output: FileHandle
        var buffer = Data()
        var weightsSHA256: String?

        init(process: Process, input: FileHandle, output: FileHandle) {
            self.process = process
            self.input = input
            self.output = output
        }

        deinit {
            try? input.close()
            try? output.close()
        }
    }

    static var codeDirectory: URL? {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["MACWISPR_REDUX_MLX_CODE"] {
            guard !override.isEmpty else { return nil }
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            guard let resources = Bundle.main.resourceURL else { return nil }
            directory = resources.appendingPathComponent("ReduxMLX", isDirectory: true)
        }
        return isReadableFile(directory.appendingPathComponent("app_server.py")) ? directory : nil
    }

    static var isAvailable: Bool { codeDirectory != nil }

    static func isReady(configuration: ReduxRuntimeConfiguration) -> Bool {
        let fm = FileManager.default
        guard isAvailable, !configuration.pythonPath.isEmpty, !configuration.weightsPath.isEmpty,
              isReadableFile(URL(fileURLWithPath: configuration.pythonPath)),
              fm.isExecutableFile(atPath: configuration.pythonPath) else { return false }
        let root = URL(fileURLWithPath: configuration.weightsPath, isDirectory: true)
        return ["conversion.json", "model.safetensors", "config.json", "tokenizer.json", "ternary.json"]
            .allSatisfy { isReadableFile(root.appendingPathComponent($0)) }
    }

    private static func isReadableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let fm = FileManager.default
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && fm.isReadableFile(atPath: url.path)
    }

    private let configuration: ReduxRuntimeConfiguration
    private let requestLock = NSLock()
    private let stateLock = NSLock()
    private var session: Session?
    private static let maximumLineBytes = 65_536
    private static let loadTimeout: TimeInterval = 180
    private static let requestTimeout: TimeInterval = 120

    init(configuration: ReduxRuntimeConfiguration) {
        self.configuration = configuration
    }

    deinit { stop() }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return session?.process.isRunning == true && session?.weightsSHA256 != nil
    }

    func start(progress: @escaping @Sendable (Double, String) -> Void) throws {
        requestLock.lock()
        defer { requestLock.unlock() }
        if isRunning { return }
        stop()
        if let raw = ProcessInfo.processInfo.environment["MACWISPR_REDUX_RUNTIME"],
           ReduxRuntime(rawValue: raw) == nil {
            throw SidecarError(message: "MACWISPR_REDUX_RUNTIME must be photon or mlx.")
        }
        guard configuration.runtime == .mlx else {
            throw SidecarError(message: "Choose the experimental MLX runtime before starting it.")
        }
        guard let code = Self.codeDirectory else {
            throw SidecarError(message: "Python code is missing. Bundle ReduxMLX or set MACWISPR_REDUX_MLX_CODE.")
        }
        guard Self.isReady(configuration: configuration) else {
            throw SidecarError(message: "Set an executable MLX Python and a local packed.py converted weights directory. Nothing is installed or downloaded automatically.")
        }
        progress(0.1, "Starting experimental Redux MLX")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.pythonPath)
        process.arguments = ["-u", code.appendingPathComponent("app_server.py").path,
                             "--weights", configuration.weightsPath]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["DO_NOT_TRACK"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let candidate = Session(process: process, input: input.fileHandleForWriting, output: output.fileHandleForReading)
        do {
            stateLock.lock()
            do {
                try process.run()
                session = candidate
                stateLock.unlock()
            } catch {
                stateLock.unlock()
                throw SidecarError(message: "Cannot launch the configured Python executable. Check its permissions and environment.")
            }
            try input.fileHandleForReading.close()
            try output.fileHandleForWriting.close()
            guard fcntl(candidate.input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw SidecarError(message: "Cannot configure the runtime input pipe.")
            }
            let flags = fcntl(candidate.input.fileDescriptor, F_GETFL)
            guard flags != -1, fcntl(candidate.input.fileDescriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
                throw SidecarError(message: "Cannot configure bounded runtime writes.")
            }
            let deadline = ProcessInfo.processInfo.systemUptime + Self.loadTimeout
            while true {
                let response = try readResponse(candidate, deadline: deadline)
                if let error = response.error { throw SidecarError(message: error) }
                if response.ready == true {
                    let diagnostics = try validateDiagnostics(response, candidate)
                    stateLock.lock()
                    let current = session === candidate
                    if current { candidate.weightsSHA256 = diagnostics.weightsSHA256 }
                    stateLock.unlock()
                    guard current else { throw SidecarError(message: "Runtime startup was cancelled.") }
                    progress(1, "Experimental Redux MLX is ready")
                    return
                }
                guard let status = response.status else {
                    throw SidecarError(message: "Expected a ready or status response from app_server.py.")
                }
                progress(min(0.99, max(0, response.progress ?? 0.5)), status)
            }
        } catch {
            stop(candidate)
            throw error
        }
    }

    func stop() {
        stateLock.lock()
        let current = session
        session = nil
        stateLock.unlock()
        if let current { terminate(current.process) }
    }

    private func stop(_ candidate: Session) {
        stateLock.lock()
        if session === candidate { session = nil }
        stateLock.unlock()
        terminate(candidate.process)
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    func transcribe(samples: [Float]) throws -> String {
        guard (320...(28 * 16_000)).contains(samples.count) else {
            throw SidecarError(message: "Each request needs 320 to 448000 samples at 16 kHz. Chunk longer audio in the caller.")
        }
        guard samples.allSatisfy({ $0.isFinite }) else {
            throw SidecarError(message: "Audio samples must be finite.")
        }
        requestLock.lock()
        defer { requestLock.unlock() }
        let current = try runningSession()
        let wav = FileManager.default.temporaryDirectory
            .appendingPathComponent("macwispr-redux-mlx-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        do {
            try AudioWAVEncoder.encode(samples: samples, sampleRate: 16_000).write(to: wav, options: .atomic)
        } catch {
            throw SidecarError(message: "Cannot create the temporary WAV. Check free disk space and temporary-directory permissions.")
        }
        let response = try exchange(["wav": wav.path], current)
        if let error = response.error { throw SidecarError(message: error) }
        guard let text = response.text else {
            stop(current)
            throw SidecarError(message: "The runtime returned no transcript field. Check the bundled app_server.py version.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func diagnostics() throws -> ReduxRuntimeDiagnostics {
        requestLock.lock()
        defer { requestLock.unlock() }
        let current = try runningSession()
        let response = try exchange(["command": "stats"], current)
        if let error = response.error { throw SidecarError(message: error) }
        guard response.status == "stats", let diagnostics = response.diagnostics else {
            stop(current)
            throw SidecarError(message: "The runtime returned an invalid stats response.")
        }
        return diagnostics
    }

    private func runningSession() throws -> Session {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let session, session.process.isRunning, session.weightsSHA256 != nil else {
            throw SidecarError(message: "The runtime is not running. Start it with verified local converted weights.")
        }
        return session
    }

    private func exchange(_ request: [String: String], _ current: Session) throws -> Response {
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + Self.requestTimeout
            let data = try JSONSerialization.data(withJSONObject: request) + Data([0x0A])
            guard data.count <= Self.maximumLineBytes else {
                throw SidecarError(message: "The runtime request exceeds the JSON-line limit.")
            }
            try data.withUnsafeBytes { bytes in
                var written = 0
                while written < bytes.count {
                    try wait(current.input.fileDescriptor, events: Int16(POLLOUT), current, deadline: deadline)
                    let count = Darwin.write(current.input.fileDescriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                    if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                    guard count > 0 else { throw SidecarError(message: "Runtime input closed. Restart the experimental runtime.") }
                    written += count
                }
            }
            let response = try readResponse(current, deadline: deadline)
            _ = try validateDiagnostics(response, current)
            return response
        } catch {
            stop(current)
            throw error
        }
    }

    private func validateDiagnostics(_ response: Response, _ current: Session) throws -> ReduxRuntimeDiagnostics {
        guard let value = response.diagnostics, value.backend == "redux-mlx",
              value.pid == current.process.processIdentifier,
              value.weightsSHA256.utf8.count == 64,
              value.weightsSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              value.activeGPUBytes >= 0, value.peakGPUBytes >= 0, value.cacheGPUBytes >= 0,
              value.processPeakRSSBytes > 0,
              current.weightsSHA256 == nil || current.weightsSHA256 == value.weightsSHA256 else {
            throw SidecarError(message: "Runtime diagnostics do not identify the expected redux-mlx process and weights. Check the Python code directory.")
        }
        return value
    }

    private func wait(_ fd: Int32, events: Int16, _ current: Session, deadline: TimeInterval) throws {
        while true {
            stateLock.lock()
            let cancelled = session !== current
            stateLock.unlock()
            guard !cancelled else { throw SidecarError(message: "Runtime operation was cancelled.") }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw SidecarError(message: "Runtime timed out. Check the MLX environment and local weights, then restart it.")
            }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(100, max(1, remaining * 1000))))
            if result < 0 && errno == EINTR { continue }
            guard result >= 0 else { throw SidecarError(message: "Cannot poll the runtime pipe.") }
            if result > 0 {
                guard descriptor.revents & Int16(POLLNVAL) == 0 else {
                    throw SidecarError(message: "The runtime pipe is closed.")
                }
                return
            }
        }
    }

    private func readResponse(_ current: Session, deadline: TimeInterval) throws -> Response {
        while true {
            if let newline = current.buffer.firstIndex(of: 0x0A) {
                guard newline <= Self.maximumLineBytes else {
                    throw SidecarError(message: "Runtime output exceeded the JSON-line limit.")
                }
                let line = current.buffer.prefix(upTo: newline)
                let response: Response
                do { response = try JSONDecoder().decode(Response.self, from: Data(line)) }
                catch { throw SidecarError(message: "Runtime stdout was not a valid protocol response. Check app_server.py and its dependencies.") }
                current.buffer.removeSubrange(...newline)
                return response
            }
            guard current.buffer.count <= Self.maximumLineBytes else {
                throw SidecarError(message: "Runtime output exceeded the JSON-line limit.")
            }
            try wait(current.output.fileDescriptor, events: Int16(POLLIN), current, deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(current.output.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                throw SidecarError(message: "Runtime exited or closed stdout. Check the pinned MLX dependencies and converted weights.")
            }
            current.buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}
