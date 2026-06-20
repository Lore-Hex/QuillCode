// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuillCode",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuillCodeCore", targets: ["QuillCodeCore"]),
        .library(name: "QuillCodeSafety", targets: ["QuillCodeSafety"]),
        .library(name: "QuillCodeTools", targets: ["QuillCodeTools"]),
        .library(name: "QuillCodePersistence", targets: ["QuillCodePersistence"]),
        .library(name: "QuillComputerUseKit", targets: ["QuillComputerUseKit"]),
        .library(name: "QuillCodeAgent", targets: ["QuillCodeAgent"]),
        .library(name: "QuillCodeApp", targets: ["QuillCodeApp"]),
        .executable(name: "quill-code", targets: ["quill-code"]),
        .executable(name: "quill-code-desktop", targets: ["quill-code-desktop"])
    ],
    dependencies: [
        .package(url: "https://github.com/jperla/trusted-router-swift.git", from: "0.4.0")
    ],
    targets: [
        .target(name: "QuillCodeCore"),
        .target(name: "QuillCodeSafety", dependencies: ["QuillCodeCore"]),
        .target(name: "QuillCodeTools", dependencies: ["QuillCodeCore"]),
        .target(name: "QuillCodePersistence", dependencies: ["QuillCodeCore"]),
        .target(name: "QuillComputerUseKit", dependencies: ["QuillCodeCore"]),
        .target(
            name: "QuillCodeAgent",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeSafety",
                "QuillCodeTools",
                "QuillCodePersistence",
                "QuillComputerUseKit",
                .product(name: "TrustedRouter", package: "trusted-router-swift")
            ]
        ),
        .target(
            name: "QuillCodeApp",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeAgent",
                "QuillCodeTools",
                "QuillCodePersistence",
                "QuillCodeSafety",
                "QuillComputerUseKit"
            ]
        ),
        .executableTarget(
            name: "quill-code",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeSafety",
                "QuillCodeTools",
                "QuillCodePersistence",
                "QuillCodeAgent"
            ]
        ),
        .executableTarget(
            name: "quill-code-desktop",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeApp"
            ]
        ),
        .testTarget(name: "QuillCodeCoreTests", dependencies: ["QuillCodeCore"]),
        .testTarget(name: "QuillCodeSafetyTests", dependencies: ["QuillCodeSafety"]),
        .testTarget(name: "QuillCodeToolsTests", dependencies: ["QuillCodeTools"]),
        .testTarget(name: "QuillCodePersistenceTests", dependencies: ["QuillCodePersistence"]),
        .testTarget(name: "QuillCodeAgentTests", dependencies: ["QuillCodeAgent", "QuillCodeTools"]),
        .testTarget(name: "QuillCodeAppTests", dependencies: ["QuillCodeApp", "QuillCodeAgent"]),
        .testTarget(name: "QuillCodeParityTests", dependencies: ["QuillCodeCore"])
    ]
)
