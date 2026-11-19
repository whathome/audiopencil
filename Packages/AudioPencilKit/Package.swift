// swift-tools-version: 5.10
// Xcode 15.3 compatibility. Swift 6.2+ uses Package@swift-6.2.swift.

import PackageDescription

let compatibility: [SwiftSetting] = [.define("AUDIOPENCIL_LEGACY_TOOLCHAIN")]

let package = Package(
    name: "AudioPencilKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS("18.0")],
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
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.14.1"),
        // The original repository retains the targets referenced by this older manifest.
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.25.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.25.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        // Bound transitive dependencies too: newer releases can require a newer compiler.
        .package(url: "https://github.com/johnmai-dev/Jinja", exact: "1.3.0"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.1.4"),
        .package(url: "https://github.com/apple/swift-numerics", exact: "1.0.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.4.0"),
    ],
    targets: [
        .target(name: "APCore", resources: [.process("Resources")], swiftSettings: compatibility),
        .target(
            name: "CSpeexDSP",
            exclude: ["COPYING"],
            sources: ["mdf.c", "fftwrap.c", "kiss_fft.c", "kiss_fftr.c"],
            publicHeadersPath: "include",
            cSettings: [.define("FLOATING_POINT"), .define("USE_KISS_FFT"), .define("EXPORT", to: "")]
        ),
        .target(name: "APAudio", dependencies: ["APCore", "CSpeexDSP"], resources: [.process("Resources")], swiftSettings: compatibility),
        .target(name: "APModels", dependencies: ["APCore"], resources: [.process("Resources")], swiftSettings: compatibility),
        .target(
            name: "APTranscription",
            dependencies: [
                "APCore",
                "APModels",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            resources: [.process("Resources")],
            swiftSettings: compatibility
        ),
        .target(
            name: "APSummary",
            dependencies: [
                "APCore", "APModels",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            resources: [.process("Resources")],
            swiftSettings: compatibility
        ),
        .target(name: "APStorage", dependencies: ["APCore"], resources: [.process("Resources")], swiftSettings: compatibility),
        .target(
            name: "APSync",
            dependencies: ["APCore", "APStorage", .product(name: "Yams", package: "Yams")],
            resources: [.process("Resources")],
            swiftSettings: compatibility
        ),
    ]
)
