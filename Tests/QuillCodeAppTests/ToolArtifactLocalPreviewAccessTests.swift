import Foundation
import XCTest
@testable import QuillCodeApp

final class ToolArtifactLocalPreviewAccessTests: XCTestCase {
    func testConfigurationRequiresReadableRootForManagedProjectFiles() {
        let project = URL(fileURLWithPath: "/Users/example/Project")
        let configuration = ToolArtifactLocalPreviewAccessConfiguration(
            projectRoots: [project],
            readableProjectRoots: []
        )

        XCTAssertFalse(configuration.permits(path: "/Users/example/Project/report.json"))
        XCTAssertTrue(configuration.permits(path: "/Users/example/ProjectSibling/report.json"))
        XCTAssertTrue(configuration.permits(path: "/private/tmp/report.json"))
    }

    func testConfigurationPermitsFilesBelowReadableProjectRoot() {
        let project = URL(fileURLWithPath: "/Users/example/Project")
        let configuration = ToolArtifactLocalPreviewAccessConfiguration(
            projectRoots: [project],
            readableProjectRoots: [project]
        )

        XCTAssertTrue(configuration.permits(path: "/Users/example/Project/Results/report.json"))
    }

    func testToolArtifactSuppressesLocalPreviewUntilProjectIsReadable() {
        let project = URL(fileURLWithPath: "/Users/example/Project")
        let artifact = ToolArtifactState(value: "/Users/example/Project/report.json")
        defer { ToolArtifactLocalPreviewAccess.reset() }

        ToolArtifactLocalPreviewAccess.configure(projectRoots: [project], readableProjectRoots: [])
        XCTAssertFalse(artifact.canLoadLocalPreview)

        ToolArtifactLocalPreviewAccess.configure(projectRoots: [project], readableProjectRoots: [project])
        XCTAssertTrue(artifact.canLoadLocalPreview)
    }
}
