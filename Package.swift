// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacWispr",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
        // Sparkle auto-updates (binary XCFramework via SPM). Private EdDSA key never goes in git.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // MLX LLM for on-device polish (Qwen3.5 SFT default; optional Liquid LFM pack).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.2.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MacWisprCore",
            path: "Sources/MacWisprCore"
        ),
        .executableTarget(
            name: "MacWispr",
            dependencies: [
                "MacWisprCore",
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "ParakeetASR", package: "speech-swift"),
                .product(name: "Qwen3Chat", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources",
            exclude: ["MacWisprCore", "MacWisprCLI"]
        ),
        // `macwispr` CLI + MCP server: read-only agent access to history and meetings.
        // build-app.sh ships it as Contents/Helpers/macwispr (a target named
        // `macwispr` would collide with `MacWispr` on case-insensitive disks).
        .executableTarget(
            name: "MacWisprCLI",
            dependencies: ["MacWisprCore"],
            path: "Sources/MacWisprCLI"
        ),
        .executableTarget(
            name: "BenchLatency",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "ParakeetASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "BenchLatency"
        ),
        // ASR gate: pass/fail harness for engine swaps (bench/asr_gate/README.md).
        .executableTarget(
            name: "ASRGate",
            dependencies: [
                "MacWisprCore",
                .product(name: "ParakeetASR", package: "speech-swift"),
            ],
            path: "bench/asr_gate/ASRGate"
        ),
        .executableTarget(
            name: "CompareASR",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "bench/CompareASR"
        ),
        .testTarget(
            name: "MacWisprCoreTests",
            dependencies: ["MacWisprCore"],
            path: "Tests/MacWisprCoreTests"
        ),
    ]
)
