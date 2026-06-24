import Foundation
import XCTest
@testable import QuillCodeApp

final class WorkspaceBrowserLocationResolverTests: XCTestCase {
    func testResolvesExplicitHTTPAndFileURLs() throws {
        let tempRoot = try makeTempDirectory()
        let file = tempRoot.appendingPathComponent("preview.html")
        try "<h1>Preview</h1>".write(to: file, atomically: true, encoding: .utf8)
        let resolver = WorkspaceBrowserLocationResolver(workspaceRoot: tempRoot)

        XCTAssertEqual(resolver.resolve(" https://example.com/path ")?.absoluteString, "https://example.com/path")
        XCTAssertEqual(resolver.resolve("http://localhost:5173")?.absoluteString, "http://localhost:5173")
        XCTAssertEqual(resolver.resolve(file.absoluteString)?.absoluteString, file.absoluteString)
    }

    func testResolvesLocalhostShorthand() {
        let resolver = WorkspaceBrowserLocationResolver()

        XCTAssertEqual(resolver.resolve("localhost:3000")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(resolver.resolve("127.0.0.1:8080/app")?.absoluteString, "http://127.0.0.1:8080/app")
        XCTAssertEqual(resolver.resolve("[::1]:5173")?.absoluteString, "http://[::1]:5173")
    }

    func testResolvesProjectRelativeFilesInsideWorkspaceOnly() throws {
        let fixtureRoot = try makeTempDirectory()
        let tempRoot = fixtureRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let inside = tempRoot.appendingPathComponent("public/preview.html")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "<h1>Inside</h1>".write(to: inside, atomically: true, encoding: .utf8)
        let outside = fixtureRoot.appendingPathComponent("outside.html")
        try "<h1>Outside</h1>".write(to: outside, atomically: true, encoding: .utf8)
        let resolver = WorkspaceBrowserLocationResolver(workspaceRoot: tempRoot)

        XCTAssertEqual(resolver.resolve("public/preview.html")?.path, inside.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertNil(resolver.resolve("../outside.html"))
        XCTAssertNil(resolver.resolve("missing.html"))
    }

    func testResolvesAbsoluteExistingFilesAndDomainShorthand() throws {
        let tempRoot = try makeTempDirectory()
        let file = tempRoot.appendingPathComponent("absolute.html")
        try "<h1>Absolute</h1>".write(to: file, atomically: true, encoding: .utf8)
        let resolver = WorkspaceBrowserLocationResolver()

        XCTAssertEqual(resolver.resolve(file.path)?.path, file.standardizedFileURL.path)
        XCTAssertEqual(resolver.resolve("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(resolver.resolve("example.com/docs")?.absoluteString, "https://example.com/docs")
        XCTAssertNil(resolver.resolve("not-a-target"))
        XCTAssertNil(resolver.resolve("missing.html"))
        XCTAssertNil(resolver.resolve("   "))
    }

    func testFetchEligibilityAndErrorMessages() {
        XCTAssertTrue(WorkspaceBrowserLocationResolver.canFetchSnapshot(for: URL(string: "http://example.com")!))
        XCTAssertTrue(WorkspaceBrowserLocationResolver.canFetchSnapshot(for: URL(string: "https://example.com")!))
        XCTAssertFalse(WorkspaceBrowserLocationResolver.canFetchSnapshot(for: URL(string: "file:///tmp/index.html")!))

        XCTAssertEqual(
            WorkspaceBrowserLocationResolver.snapshotFetchMessage(for: BrowserPageFetchFailure.httpStatus(503)),
            "The page returned HTTP 503."
        )
        let error = NSError(domain: "QuillCode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network unavailable"])
        XCTAssertEqual(WorkspaceBrowserLocationResolver.snapshotFetchMessage(for: error), "Network unavailable")
    }

}
