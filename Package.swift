// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenWhispr",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "OpenWhispr",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "Sources"
        )
    ]
)
