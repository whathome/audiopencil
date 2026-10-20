// swift-tools-version: 6.2
// Shared core for Audio Pencil (macOS now, iOS in phase 2).
// Build and test through xcodebuild: MLX (milestone 3) needs Xcode to compile its Metal shaders.

import PackageDescription

let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "AudioPencilKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "APCore", targets: ["APCore"]),
        .library(name: "APAudio", targets: ["APAudio"]),
        .library(name: "APModels", targets: ["APModels"]),
        .library(name: "APTranscription", targets: ["APTranscription"]),
        .library(name: "APSummary", targets: ["APSummary"]),
        .library(name: "APStorage", targets: ["APStorage"]),
        .library(name: "APSync", targets: ["APSync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
        // Pinned: mlx-swift 0.31.5+ needs Swift tools 6.3; Xcode 26.3 ships Swift 6.2.
        // Move to the latest mlx-swift-lm after updating Xcode.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.5")),
        .package(url: "https://github.com/jpsim/Yams.git", .upToNextMinor(from: "6.2.2")),
    ],
    targets: [
        // Pure logic: settings, gesture detection, diagnostics. No platform frameworks beyond Foundation.
        .target(name: "APCore", swiftSettings: concurrency),

        // Microphone capture (16 kHz mono), levels, audio cues.
        .target(name: "APAudio", dependencies: ["APCore"], swiftSettings: concurrency),

        // Model residency (one large model at a time), catalogue, on-disk locations.
        .target(name: "APModels", dependencies: ["APCore"], swiftSettings: concurrency),

        // WhisperKit wrapper and streaming confirmation logic.
        .target(
            name: "APTranscription",
            dependencies: [
                "APCore",
                "APModels",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: concurrency
        ),

        // MLX summarisation model. Needs xcodebuild (Metal shaders), not `swift build`.
        .target(
            name: "APSummary",
            dependencies: [
                "APCore",
                "APModels",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: concurrency
        ),

        // Vault storage: Nextcloud (WebDAV, Login Flow v2) or a local folder such as iCloud Drive.
        .target(name: "APStorage", dependencies: ["APCore"], swiftSettings: concurrency),

        // Shared settings file (YAML in the vault), three-way merge, offline upload queue.
        .target(
            name: "APSync",
            dependencies: ["APCore", "APStorage", .product(name: "Yams", package: "Yams")],
            swiftSettings: concurrency
        ),

        .testTarget(name: "APCoreTests", dependencies: ["APCore"], swiftSettings: concurrency),
        .testTarget(
            name: "APTranscriptionTests",
            dependencies: ["APTranscription", "APModels"],
            swiftSettings: concurrency
        ),
        .testTarget(name: "APStorageTests", dependencies: ["APStorage"], swiftSettings: concurrency),
        .testTarget(name: "APSyncTests", dependencies: ["APSync", "APStorage", "APCore", .product(name: "Yams", package: "Yams")], swiftSettings: concurrency),
        .testTarget(
            name: "APSummaryTests",
            dependencies: ["APSummary", "APModels", "APCore"],
            swiftSettings: concurrency
        ),
    ]
)
