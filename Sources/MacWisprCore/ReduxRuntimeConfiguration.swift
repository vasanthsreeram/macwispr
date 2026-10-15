import Foundation

public enum ReduxRuntime: String, CaseIterable, Identifiable, Sendable {
    case photon
    case mlx

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .photon: return "Photon"
        case .mlx: return "Python MLX (Experimental)"
        }
    }
}

public struct ReduxRuntimeConfiguration: Equatable, Sendable {
    public static let runtimeKey = "reduxRuntime"
    public static let pythonKey = "reduxMLXPythonPath"
    public static let weightsKey = "reduxMLXWeightsPath"

    public let runtime: ReduxRuntime
    public let pythonPath: String
    public let weightsPath: String

    public init(runtime: ReduxRuntime, pythonPath: String, weightsPath: String) {
        self.runtime = runtime
        self.pythonPath = pythonPath
        self.weightsPath = weightsPath
    }

    public static func load(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        let runtime = environment["MACWISPR_REDUX_RUNTIME"] ?? defaults.string(forKey: runtimeKey) ?? "photon"
        return Self(
            runtime: ReduxRuntime(rawValue: runtime) ?? .photon,
            pythonPath: environment["MACWISPR_REDUX_MLX_PYTHON"]
                ?? defaults.string(forKey: pythonKey) ?? "/opt/homebrew/bin/python3",
            weightsPath: environment["MACWISPR_REDUX_MLX_WEIGHTS"]
                ?? defaults.string(forKey: weightsKey) ?? ""
        )
    }

    public func store(defaults: UserDefaults = .standard) {
        defaults.set(runtime.rawValue, forKey: Self.runtimeKey)
        defaults.set(pythonPath, forKey: Self.pythonKey)
        defaults.set(weightsPath, forKey: Self.weightsKey)
    }
}

public struct ReduxRuntimeDiagnostics: Codable, Sendable, Equatable {
    public let backend: String
    public let pid: Int32
    public let weightsSHA256: String
    public let activeGPUBytes: Int64
    public let peakGPUBytes: Int64
    public let cacheGPUBytes: Int64
    public let processPeakRSSBytes: Int64

    public init(
        backend: String, pid: Int32, weightsSHA256: String,
        activeGPUBytes: Int64, peakGPUBytes: Int64, cacheGPUBytes: Int64,
        processPeakRSSBytes: Int64
    ) {
        self.backend = backend
        self.pid = pid
        self.weightsSHA256 = weightsSHA256
        self.activeGPUBytes = activeGPUBytes
        self.peakGPUBytes = peakGPUBytes
        self.cacheGPUBytes = cacheGPUBytes
        self.processPeakRSSBytes = processPeakRSSBytes
    }

    enum CodingKeys: String, CodingKey {
        case backend, pid
        case weightsSHA256 = "weights_sha256"
        case activeGPUBytes = "active_gpu_bytes"
        case peakGPUBytes = "peak_gpu_bytes"
        case cacheGPUBytes = "cache_gpu_bytes"
        case processPeakRSSBytes = "process_peak_rss_bytes"
    }
}
