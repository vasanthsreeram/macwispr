// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacWispr",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "MacWispr",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "Qwen3Chat", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
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
