@testable import QuillCodeCLI
import XCTest

final class AppServerRemoteWorkspacePathTests: XCTestCase {
    func testUnixPathsNormalizeWithinWorkspaceAndRejectEscapes() throws {
        let workspace = try AppServerRemoteWorkspacePath(
            cwd: "/srv/project",
            fallbackCWDURI: nil
        )

        XCTAssertEqual(workspace.root.nativePath, "/srv/project")
        XCTAssertEqual(workspace.root.uri, "file:///srv/project")
        XCTAssertEqual(
            try workspace.resolve("Sources/../README.md"),
            .init(
                nativePath: "/srv/project/README.md",
                uri: "file:///srv/project/README.md",
                relativePath: "README.md"
            )
        )
        XCTAssertEqual(try workspace.resolve("/srv/project/Tests").relativePath, "Tests")
        XCTAssertThrowsError(try workspace.resolve("../secret"))
        XCTAssertThrowsError(try workspace.resolve("/etc/passwd"))
    }

    func testWindowsPathsUseTargetNativeSyntaxAndRejectDifferentDrive() throws {
        let workspace = try AppServerRemoteWorkspacePath(
            cwd: #"C:\work\quillcode"#,
            fallbackCWDURI: nil
        )

        XCTAssertEqual(workspace.root.nativePath, #"C:\work\quillcode"#)
        XCTAssertEqual(workspace.root.uri, "file:///C:/work/quillcode")
        XCTAssertEqual(
            try workspace.resolve(#"Sources\Main.swift"#),
            .init(
                nativePath: #"C:\work\quillcode\Sources\Main.swift"#,
                uri: "file:///C:/work/quillcode/Sources/Main.swift",
                relativePath: "Sources/Main.swift"
            )
        )
        XCTAssertThrowsError(try workspace.resolve(#"D:\outside.txt"#))
        XCTAssertThrowsError(try workspace.resolve(#"..\outside.txt"#))
    }

    func testFileURIFallbackAndCanonicalContainmentAreCrossPlatform() throws {
        let unix = try AppServerRemoteWorkspacePath(
            cwd: "",
            fallbackCWDURI: "file:///home/quill/My%20Project"
        )
        XCTAssertEqual(unix.root.nativePath, "/home/quill/My Project")
        XCTAssertTrue(unix.contains(canonicalURI: "file:///home/quill/My%20Project/a.swift"))
        XCTAssertTrue(unix.contains(canonicalURI: "file:///home/quill/My%20Project/sub/../a.swift"))
        XCTAssertEqual(
            unix.canonical("file:///home/quill/My%20Project/sub/../a.swift"),
            .init(
                nativePath: "/home/quill/My Project/a.swift",
                uri: "file:///home/quill/My%20Project/a.swift",
                relativePath: "a.swift"
            )
        )
        XCTAssertFalse(unix.contains(canonicalURI: "file:///home/quill/My%20Project-evil/a.swift"))
        XCTAssertFalse(unix.contains(canonicalURI: "file:///home/quill/My%20Project/%2E%2E/secret"))
        XCTAssertFalse(unix.contains(canonicalURI: "file://remote-host/home/quill/My%20Project/a.swift"))

        let windows = try AppServerRemoteWorkspacePath(
            cwd: "file:///C:/Users/quill/Project",
            fallbackCWDURI: nil
        )
        XCTAssertEqual(windows.root.nativePath, #"C:\Users\quill\Project"#)
        XCTAssertTrue(windows.contains(canonicalURI: "file:///c:/users/QUILL/project/a.swift"))
        XCTAssertTrue(windows.contains(canonicalURI: "file:///C:/Users/quill/Project/sub/../a.swift"))
        XCTAssertFalse(windows.contains(canonicalURI: "file:///C:/Users/quill/Project/%2E%2E/secret"))
        XCTAssertFalse(windows.contains(canonicalURI: "file:///D:/Users/quill/Project/a.swift"))
    }

    func testWorkspaceRootsNormalizeDotSegmentsAndRejectRootEscapes() throws {
        let normalized = try AppServerRemoteWorkspacePath(
            cwd: "/srv/projects/../quillcode",
            fallbackCWDURI: nil
        )
        XCTAssertEqual(normalized.root.nativePath, "/srv/quillcode")

        XCTAssertThrowsError(try AppServerRemoteWorkspacePath(
            cwd: "/../etc",
            fallbackCWDURI: nil
        ))
        XCTAssertThrowsError(try AppServerRemoteWorkspacePath(
            cwd: "file://remote-host/srv/quillcode",
            fallbackCWDURI: nil
        ))
    }
}
