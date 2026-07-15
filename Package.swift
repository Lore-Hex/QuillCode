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
        .library(name: "QuillCodeCLI", targets: ["QuillCodeCLI"]),
        .executable(name: "quill-code", targets: ["quill-code"]),
        .executable(name: "quill-code-desktop", targets: ["quill-code-desktop"]),
        .executable(
            name: "quillcode-linux-computer-use-smoke",
            targets: ["quillcode-linux-computer-use-smoke"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Lore-Hex/trusted-router-swift.git", from: "0.4.1"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.5"),
        .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3")
    ],
    targets: [
        .target(name: "QuillCodeCore"),
        .target(name: "QuillCodeSafety", dependencies: ["QuillCodeCore"]),
        .target(name: "CQuillPTY"),
        .target(
            name: "QuillCodeTools",
            dependencies: [
                "QuillCodeCore",
                "CQuillPTY",
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(
            name: "QuillCodePersistence",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeSafety",
                .product(name: "TOML", package: "swift-toml")
            ]
        ),
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
        .target(
            name: "QuillCodeCLI",
            dependencies: [
                "QuillCodeCore",
                "QuillCodeSafety",
                "QuillCodeTools",
                "QuillCodePersistence",
                "QuillCodeAgent",
                "CQuillPTY"
            ]
        ),
        .executableTarget(
            name: "quill-code",
            dependencies: ["QuillCodeCLI"]
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
        .testTarget(
            name: "QuillCodeCLITests",
            dependencies: [
                "QuillCodeCLI",
                "QuillCodeAgent",
                "QuillCodeCore",
                "QuillCodePersistence",
                "QuillCodeTools"
            ]
        ),
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
