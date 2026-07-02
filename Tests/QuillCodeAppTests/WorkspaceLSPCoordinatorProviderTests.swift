import Foundation
import XCTest
@testable import QuillCodeApp

final class WorkspaceLSPCoordinatorProviderTests: XCTestCase {
    private let workspace = URL(fileURLWithPath: "/tmp/quillcode-lsp-provider")

    func testDisabledByDefault() {
        let provider = WorkspaceLSPCoordinatorProvider(environment: [:])
        XCTAssertNil(provider.coordinator(forWorkspace: workspace, isRemote: false),
                     "LSP must be off unless QUILLCODE_LSP is set")
    }

    func testEnabledByEnvironmentFlag() {
        let provider = WorkspaceLSPCoordinatorProvider(environment: ["QUILLCODE_LSP": "1"])
        XCTAssertNotNil(provider.coordinator(forWorkspace: workspace, isRemote: false))
    }

    func testRemoteWorkspaceHasNoCoordinatorEvenWhenEnabled() {
        let provider = WorkspaceLSPCoordinatorProvider(environment: ["QUILLCODE_LSP": "1"])
        XCTAssertNil(provider.coordinator(forWorkspace: workspace, isRemote: true),
                     "a remote project's files are not on this machine, so a local server cannot see them")
    }

    func testCoordinatorIsCachedPerWorkspace() {
        let provider = WorkspaceLSPCoordinatorProvider(environment: ["QUILLCODE_LSP": "true"])
        let first = provider.coordinator(forWorkspace: workspace, isRemote: false)
        let second = provider.coordinator(forWorkspace: workspace, isRemote: false)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "the same workspace must reuse one coordinator (and one server)")
    }

    func testDifferentWorkspacesGetDistinctCoordinators() {
        let provider = WorkspaceLSPCoordinatorProvider(environment: ["QUILLCODE_LSP": "yes"])
        let a = provider.coordinator(forWorkspace: URL(fileURLWithPath: "/tmp/ws-a"), isRemote: false)
        let b = provider.coordinator(forWorkspace: URL(fileURLWithPath: "/tmp/ws-b"), isRemote: false)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertFalse(a === b)
    }
}
