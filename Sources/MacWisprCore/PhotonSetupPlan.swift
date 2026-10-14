import Foundation

/// The commands that install Moondream's Photon runtime for Parakeet Redux.
///
/// Preferred path: the `uv` binary bundled in the app creates a venv on a
/// uv-managed CPython and installs pinned packages. This needs no system Python
/// and is roughly 10x faster than `python -m venv` + pip on a cold cache.
/// Fallback (dev builds without a bundled uv): system `python3` + pip.
public struct PhotonSetupPlan: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let label: String
        /// Progress fraction to report when this step starts.
        public let progress: Double
        public let executable: String
        public let arguments: [String]
        public let environment: [String: String]
    }

    public enum Method: String, Equatable, Sendable {
        case uv
        case pip
    }

    /// Bump when the package pins or layout change; forces a clean reinstall.
    public static let runtimeVersion = "photon-runtime-2"
    public static let pythonVersion = "3.12"
    /// Versions verified end to end with `moondream/parakeet-redux`.
    public static let packages = ["moondream==2.6.1", "kestrel==0.9.1"]

    public let method: Method
    public let root: URL
    public let steps: [Step]

    public var venvDirectory: URL { Self.venvDirectory(root: root) }
    public var venvPython: URL { venvDirectory.appendingPathComponent("bin/python") }

    public static func venvDirectory(root: URL) -> URL {
        root.appendingPathComponent("venv", isDirectory: true)
    }

    /// Build the plan, or nil when neither uv nor Python 3 is available.
    public static func make(root: URL, uvPath: String?, pythonPath: String?) -> PhotonSetupPlan? {
        let venv = venvDirectory(root: root).path
        let venvPython = venvDirectory(root: root).appendingPathComponent("bin/python").path

        if let uv = uvPath {
            let env = uvEnvironment(root: root)
            return PhotonSetupPlan(method: .uv, root: root, steps: [
                Step(
                    label: "Preparing speech runtime…",
                    progress: 0.05,
                    executable: uv,
                    arguments: [
                        "venv", "--quiet",
                        "--python", pythonVersion,
                        "--managed-python",
                        venv,
                    ],
                    environment: env
                ),
                Step(
                    label: "Installing speech runtime…",
                    progress: 0.2,
                    executable: uv,
                    arguments: ["pip", "install", "--quiet", "--python", venvPython] + packages,
                    environment: env
                ),
            ])
        }

        if let python = pythonPath {
            return PhotonSetupPlan(method: .pip, root: root, steps: [
                Step(
                    label: "Preparing speech runtime…",
                    progress: 0.05,
                    executable: python,
                    arguments: ["-m", "venv", venv],
                    environment: [:]
                ),
                Step(
                    label: "Installing speech runtime…",
                    progress: 0.2,
                    executable: venvPython,
                    arguments: ["-m", "pip", "install", "--quiet", "--disable-pip-version-check"] + packages,
                    environment: [:]
                ),
            ])
        }
        return nil
    }

    /// uv state lives under `root`, so deleting the model removes everything.
    public static func uvEnvironment(root: URL) -> [String: String] {
        [
            "UV_PYTHON_INSTALL_DIR": root.appendingPathComponent("python", isDirectory: true).path,
            "UV_CACHE_DIR": root.appendingPathComponent("uv-cache", isDirectory: true).path,
            "UV_NO_CONFIG": "1",
            "UV_PYTHON_DOWNLOADS": "automatic",
        ]
    }

    /// Environment for the sidecar server process.
    /// Once the weights are on disk the Hub stays offline so loads never wait on
    /// the network.
    public static func serverEnvironment(weightsReady: Bool) -> [String: String] {
        var env = [
            "TOKENIZERS_PARALLELISM": "false",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "HF_HUB_DISABLE_PROGRESS_BARS": "1",
            "PYTHONUNBUFFERED": "1",
        ]
        if weightsReady {
            env["HF_HUB_OFFLINE"] = "1"
        }
        return env
    }
}
