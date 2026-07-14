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
        .library(name: "QuillCodePlatformUI", targets: ["QuillCodePlatformUI"]),
        .library(name: "QuillCodeAgent", targets: ["QuillCodeAgent"]),
        .library(name: "QuillCodeApp", targets: ["QuillCodeApp"]),
        .executable(name: "quill-code", targets: ["quill-code"]),
        .executable(name: "quill-code-desktop", targets: ["quill-code-desktop"]),
        .executable(
            name: "quillcode-linux-computer-use-smoke",
            targets: ["quillcode-linux-computer-use-smoke"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Lore-Hex/trusted-router-swift.git", from: "0.4.1"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.5")
    ],
    targets: [
        .target(name: "QuillCodeCore"),
        .target(name: "QuillCodeSafety", dependencies: ["QuillCodeCore"]),
        .target(name: "CQuillPTY"),
        .target(name: "QuillCodeTools", dependencies: ["QuillCodeCore", "CQuillPTY"]),
        .target(name: "QuillCodePersistence", dependencies: ["QuillCodeCore", "QuillCodeSafety"]),
        .target(name: "QuillComputerUseKit", dependencies: ["QuillCodeCore"]),
        .target(name: "QuillCodePlatformUI", dependencies: ["QuillCodeTools"]),
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
                "QuillComputerUseKit",
                "QuillCodePlatformUI",
                .product(name: "TOMLDecoder", package: "TOMLDecoder")
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
                "QuillCodeApp",
                "QuillCodeAgent",
                "QuillCodeTools",
                "QuillComputerUseKit"
            ]
        ),
        .executableTarget(
            name: "quillcode-linux-computer-use-smoke",
            dependencies: ["QuillComputerUseKit"]
        ),
        .testTarget(name: "QuillCodeCoreTests", dependencies: ["QuillCodeCore"]),
        .testTarget(name: "QuillCodeSafetyTests", dependencies: ["QuillCodeSafety"]),
        .testTarget(name: "QuillCodeToolsTests", dependencies: ["QuillCodeTools"]),
        .testTarget(name: "QuillCodePersistenceTests", dependencies: ["QuillCodePersistence", "QuillCodeSafety"]),
        .testTarget(name: "QuillComputerUseKitTests", dependencies: ["QuillComputerUseKit"]),
        .testTarget(name: "QuillCodePlatformUITests", dependencies: ["QuillCodePlatformUI"]),
        .testTarget(name: "QuillCodeAgentTests", dependencies: ["QuillCodeAgent", "QuillCodeTools", "QuillCodeSafety"]),
        .testTarget(name: "QuillCodeAppTests", dependencies: ["QuillCodeApp", "QuillCodeAgent"]),
        .testTarget(
            name: "QuillCodeDesktopTests",
            dependencies: [
                .target(name: "quill-code-desktop"),
                "QuillCodeApp",
                "QuillCodePersistence"
            ]
        ),
        .testTarget(name: "QuillCodeParityTests", dependencies: ["QuillCodeCore"])
    ]
)
