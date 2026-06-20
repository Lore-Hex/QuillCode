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
        .executable(name: "quill-code", targets: ["quill-code"])
    ],
    dependencies: [],
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
                "QuillComputerUseKit"
            ]
        ),
        .target(
            name: "QuillCodeApp",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeAgent",
                "QuillCodePersistence",
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
        .testTarget(name: "QuillCodeCoreTests", dependencies: ["QuillCodeCore"]),
        .testTarget(name: "QuillCodeSafetyTests", dependencies: ["QuillCodeSafety"]),
        .testTarget(name: "QuillCodeToolsTests", dependencies: ["QuillCodeTools"]),
        .testTarget(name: "QuillCodePersistenceTests", dependencies: ["QuillCodePersistence"]),
        .testTarget(name: "QuillCodeAgentTests", dependencies: ["QuillCodeAgent", "QuillCodeTools"]),
        .testTarget(name: "QuillCodeParityTests", dependencies: ["QuillCodeCore"])
    ]
)
