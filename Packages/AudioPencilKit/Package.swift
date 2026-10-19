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
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
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

        .testTarget(name: "APCoreTests", dependencies: ["APCore"], swiftSettings: concurrency),
        .testTarget(
            name: "APTranscriptionTests",
            dependencies: ["APTranscription", "APModels"],
            swiftSettings: concurrency
        ),
    ]
)
