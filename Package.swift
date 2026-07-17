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
        .executableTarget(
            name: "MacWispr",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "ParakeetASR", package: "speech-swift"),
                .product(name: "Qwen3Chat", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources"
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
        .executableTarget(
            name: "CompareASR",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "bench/CompareASR"
        ),
    ]
)
