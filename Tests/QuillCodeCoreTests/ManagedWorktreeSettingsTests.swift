import Foundation
import XCTest
@testable import QuillCodeCore

final class ManagedWorktreeSettingsTests: XCTestCase {
    func testDefaultsMatchCodexRetentionContract() {
        let settings = ManagedWorktreeSettings()

        XCTAssertNil(settings.rootPath)
        XCTAssertTrue(settings.automaticCleanupEnabled)
        XCTAssertEqual(settings.retentionLimit, 15)
    }

    func testNormalizesRootAndClampsRetentionLimit() {
        XCTAssertEqual(
            ManagedWorktreeSettings(rootPath: "  ~/Code worktrees  ", retentionLimit: 0),
            ManagedWorktreeSettings(rootPath: "~/Code worktrees", retentionLimit: 1)
        )
        XCTAssertNil(ManagedWorktreeSettings(rootPath: "relative/path").rootPath)
        XCTAssertEqual(
            ManagedWorktreeSettings(retentionLimit: 10_000).retentionLimit,
            ManagedWorktreeSettings.retentionLimitRange.upperBound
        )
    }

    func testResolvesDefaultTildeAndAbsoluteRoots() {
        let home = URL(fileURLWithPath: "/Users/quill")
        let fallback = URL(fileURLWithPath: "/state/worktrees")

        XCTAssertEqual(
            ManagedWorktreeSettings().resolvedRoot(defaultRoot: fallback, homeDirectory: home).path,
            fallback.path
        )
        XCTAssertEqual(
            ManagedWorktreeSettings(rootPath: "~/Tasks")
                .resolvedRoot(defaultRoot: fallback, homeDirectory: home).path,
            "/Users/quill/Tasks"
        )
        XCTAssertEqual(
            ManagedWorktreeSettings(rootPath: "/Volumes/Tasks")
                .resolvedRoot(defaultRoot: fallback, homeDirectory: home).path,
            "/Volumes/Tasks"
        )
    }

    func testDecodeUsesDefaultsAndNormalization() throws {
        let partial = try JSONDecoder().decode(
            ManagedWorktreeSettings.self,
            from: Data(#"{"rootPath":" relative/path ","retentionLimit":0}"#.utf8)
        )

        XCTAssertNil(partial.rootPath)
        XCTAssertTrue(partial.automaticCleanupEnabled)
        XCTAssertEqual(partial.retentionLimit, 1)
    }
}
