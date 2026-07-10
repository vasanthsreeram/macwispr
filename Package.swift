// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacWispr",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
        // Direct MLX so we can stream decode tokens during inference.
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.25.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacWispr",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ],
            path: "Sources"
        ),
        .executableTarget(
            name: "BenchLatency",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "BenchLatency"
        ),
    ]
)
