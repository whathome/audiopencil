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
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "APCore", targets: ["APCore"]),
        .library(name: "APAudio", targets: ["APAudio"]),
        .library(name: "APModels", targets: ["APModels"]),
        .library(name: "APTranscription", targets: ["APTranscription"]),
        .library(name: "APPhonon", targets: ["APPhonon"]),
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
        // Phonon-2 trial (Mac). The revision benchmarked in docs/benchmarks/phonon-2-vs-whisper-small.md: the
        // encoder ladder it measured came after v0.17.7. No traits: speech recognition only, no TTS or diarizer.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "c79c4106b954f81205113c3343e5a7e59a1089b5", traits: []),
    ],
    targets: [
        // Pure logic: settings, gesture detection, diagnostics. No platform frameworks beyond Foundation.
        .target(name: "APCore", resources: [.process("Resources")], swiftSettings: concurrency),

        // Microphone capture (16 kHz mono), levels, audio cues.
        .target(name: "APAudio", dependencies: ["APCore"], resources: [.process("Resources")], swiftSettings: concurrency),

        // Model residency (one large model at a time), catalogue, on-disk locations.
        .target(name: "APModels", dependencies: ["APCore"], resources: [.process("Resources")], swiftSettings: concurrency),

        // WhisperKit wrapper, streaming confirmation logic and meeting speaker labels.
        .target(
            name: "APTranscription",
            dependencies: [
                "APCore",
                "APModels",
                .product(name: "WhisperKit", package: "WhisperKit"),
                // Speaker labels for meeting mode (pyannote), from the same Argmax package as WhisperKit.
                .product(name: "SpeakerKit", package: "WhisperKit"),
            ],
            resources: [.process("Resources")],
            swiftSettings: concurrency
        ),

        // Phonon-2 (FluidAudio) as a second English speech engine. Linked by the Mac app only.
        .target(
            name: "APPhonon",
            dependencies: [
                "APCore",
                "APModels",
                "APTranscription",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [.process("Resources")],
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
            resources: [.process("Resources")],
            swiftSettings: concurrency
        ),

        // Vault storage: Nextcloud (WebDAV, Login Flow v2) or a local folder such as iCloud Drive.
        .target(name: "APStorage", dependencies: ["APCore"], resources: [.process("Resources")], swiftSettings: concurrency),

        // Shared settings file (YAML in the vault), three-way merge, offline upload queue.
        .target(
            name: "APSync",
            dependencies: ["APCore", "APStorage", .product(name: "Yams", package: "Yams")],
            resources: [.process("Resources")],
            swiftSettings: concurrency
        ),

        .testTarget(name: "APCoreTests", dependencies: ["APCore"], swiftSettings: concurrency),
        .testTarget(name: "APAudioTests", dependencies: ["APAudio"], swiftSettings: concurrency),
        .testTarget(
            name: "APTranscriptionTests",
            dependencies: ["APTranscription", "APModels"],
            swiftSettings: concurrency
        ),
        .testTarget(name: "APPhononTests", dependencies: ["APPhonon", "APTranscription", "APModels", "APCore", .product(name: "FluidAudio", package: "FluidAudio")], swiftSettings: concurrency),
        .testTarget(name: "APStorageTests", dependencies: ["APStorage"], swiftSettings: concurrency),
        .testTarget(name: "APSyncTests", dependencies: ["APSync", "APStorage", "APCore", .product(name: "Yams", package: "Yams")], swiftSettings: concurrency),
        .testTarget(
            name: "APSummaryTests",
            dependencies: ["APSummary", "APModels", "APCore"],
            swiftSettings: concurrency
        ),
    ]
)
