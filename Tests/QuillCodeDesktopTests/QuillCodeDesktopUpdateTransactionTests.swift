import Foundation
import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdateTransactionTests: XCTestCase {
    func testRecoveryDiscardsPreparedReplacementWhenPreviousBuildStillRuns() throws {
        let fixture = try makeFixture(suffix: "before-activation")
        defer { fixture.remove() }
        var configuration = makeConfiguration(currentBuild: "1")
        configuration.applicationURL = fixture.destination

        let protected = try XCTUnwrap(
            QuillCodeDesktopUpdateRecovery.reconcileInterruptedTransactions(
                configuration: configuration,
                cacheRoot: fixture.cacheRoot
            )
        )

        XCTAssertEqual(protected, [])
        XCTAssertEqual(try bundleBuild(at: fixture.destination), "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testRecoveryRetiresRollbackOnlyAfterReplacementRuns() throws {
        let fixture = try makeFixture(suffix: "after-activation")
        defer { fixture.remove() }
        let temporary = fixture.root.appendingPathComponent("swap-temporary.app", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.destination, to: temporary)
        try FileManager.default.moveItem(at: fixture.incoming, to: fixture.destination)
        try FileManager.default.moveItem(at: temporary, to: fixture.incoming)
        var configuration = makeConfiguration(currentBuild: "2")
        configuration.applicationURL = fixture.destination

        let protected = try XCTUnwrap(
            QuillCodeDesktopUpdateRecovery.reconcileInterruptedTransactions(
                configuration: configuration,
                cacheRoot: fixture.cacheRoot
            )
        )

        XCTAssertEqual(protected, [])
        XCTAssertEqual(try bundleBuild(at: fixture.destination), "2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testRecoveryPreservesAmbiguousInterruptedTransaction() throws {
        let fixture = try makeFixture(suffix: "ambiguous")
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.destination)
        var configuration = makeConfiguration(currentBuild: "1")
        configuration.applicationURL = fixture.destination
        let transaction = try QuillCodeDesktopUpdateTransaction.read(
            fromWorkspace: fixture.workspace,
            cacheRoot: fixture.cacheRoot
        )
        XCTAssertTrue(transaction.hasValidRecoveryLayout(
            workspace: fixture.workspace,
            cacheRoot: fixture.cacheRoot,
            configuration: configuration
        ))

        let protected = try XCTUnwrap(
            QuillCodeDesktopUpdateRecovery.reconcileInterruptedTransactions(
                configuration: configuration,
                cacheRoot: fixture.cacheRoot
            )
        )

        XCTAssertEqual(protected, [fixture.incoming.standardizedFileURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testRecoveryPreservesPayloadWhenDestinationNoLongerMatchesRunningBuild() throws {
        let fixture = try makeFixture(suffix: "externally-replaced-destination")
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.destination)
        try makeFakeApplication(
            at: fixture.destination,
            version: "0.1.0",
            build: "3",
            commit: String(repeating: "c", count: 40),
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        var configuration = makeConfiguration(currentBuild: "1")
        configuration.applicationURL = fixture.destination

        let protected = try XCTUnwrap(
            QuillCodeDesktopUpdateRecovery.reconcileInterruptedTransactions(
                configuration: configuration,
                cacheRoot: fixture.cacheRoot
            )
        )

        XCTAssertEqual(protected, [fixture.incoming.standardizedFileURL])
        XCTAssertEqual(try bundleBuild(at: fixture.destination), "3")
        XCTAssertEqual(try bundleBuild(at: fixture.incoming), "2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testRecoveryStopsCleanupWhenTransactionRecordIsDamaged() throws {
        let fixture = try makeFixture(suffix: "damaged")
        defer { fixture.remove() }
        try Data("not-json".utf8).write(
            to: fixture.workspace.appendingPathComponent(
                QuillCodeDesktopUpdateTransaction.fileName
            ),
            options: .atomic
        )
        var configuration = makeConfiguration(currentBuild: "1")
        configuration.applicationURL = fixture.destination

        let protected = try QuillCodeDesktopUpdateRecovery.reconcileInterruptedTransactions(
            configuration: configuration,
            cacheRoot: fixture.cacheRoot
        )

        XCTAssertNil(protected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testHelperRefusesReplacementWithoutDurableRecoveryRecord() throws {
        let fixture = try makeFixture(suffix: "missing-record")
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.workspace.appendingPathComponent(
                QuillCodeDesktopUpdateTransaction.fileName
            )
        )
        let environment = QuillCodeDesktopUpdateHelperEnvironment(
            cacheRootURL: fixture.cacheRoot,
            resultURL: fixture.request.resultURL,
            parentExitTimeout: 0.1,
            launchHandshakeTimeout: 0.1,
            launchStabilityDuration: 0.1
        )

        XCTAssertEqual(QuillCodeDesktopUpdateHelper.run(fixture.request, environment: environment), 1)
        XCTAssertEqual(try bundleBuild(at: fixture.destination), "1")
        XCTAssertEqual(try bundleBuild(at: fixture.incoming), "2")
    }

    func testCancellationCleanupRemovesOnlyValidatedUnactivatedReplacement() throws {
        let fixture = try makeFixture(suffix: "cancelled-before-helper")
        defer { fixture.remove() }

        XCTAssertTrue(QuillCodeDesktopUpdateTransaction.discardUnactivated(
            fixture.request,
            cacheRoot: fixture.cacheRoot
        ))

        XCTAssertEqual(try bundleBuild(at: fixture.destination), "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testCancellationCleanupPreservesTamperedReplacement() throws {
        let fixture = try makeFixture(suffix: "tampered-before-helper")
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.incoming)
        try makeFakeApplication(
            at: fixture.incoming,
            version: "0.1.0",
            build: "3",
            executableScript: "#!/bin/sh\nexit 0\n"
        )

        XCTAssertFalse(QuillCodeDesktopUpdateTransaction.discardUnactivated(
            fixture.request,
            cacheRoot: fixture.cacheRoot
        ))

        XCTAssertEqual(try bundleBuild(at: fixture.destination), "1")
        XCTAssertEqual(try bundleBuild(at: fixture.incoming), "3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    private func makeFixture(suffix: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let workspace = cacheRoot.appendingPathComponent("workspace-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        let incoming = root.appendingPathComponent(
            ".Quill Cowork.update-\(UUID().uuidString.lowercased()).app",
            isDirectory: true
        )
        try makeFakeApplication(
            at: destination,
            version: "0.1.0",
            build: "1",
            commit: String(repeating: "b", count: 40),
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try makeFakeApplication(
            at: incoming,
            version: "0.1.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let request = QuillCodeDesktopUpdateHelperRequest(
            parentProcessID: Int32.max,
            helperURL: workspace.appendingPathComponent("helper"),
            incomingApplicationURL: incoming,
            destinationApplicationURL: destination,
            handshakeURL: workspace.appendingPathComponent("launch-\(suffix).ack"),
            resultURL: root.appendingPathComponent("UpdateResult.json"),
            logURL: workspace.appendingPathComponent("install.log"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork",
            expectedVersion: "0.1.0",
            expectedBuild: "2",
            expectedCommit: String(repeating: "a", count: 40),
            activationMode: .replaceExisting,
            rollbackApplicationURL: nil
        )
        try QuillCodeDesktopUpdateTransaction.persist(for: request, cacheRoot: cacheRoot)
        return Fixture(
            root: root,
            cacheRoot: cacheRoot,
            workspace: workspace,
            destination: destination,
            incoming: incoming,
            request: request
        )
    }

    private func bundleBuild(at applicationURL: URL) throws -> String {
        let bundle = try XCTUnwrap(Bundle(url: applicationURL))
        return try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    private struct Fixture {
        var root: URL
        var cacheRoot: URL
        var workspace: URL
        var destination: URL
        var incoming: URL
        var request: QuillCodeDesktopUpdateHelperRequest

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
