import Darwin
import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopApplicationRelocationTests: XCTestCase {
    func testPackagedSmokeRequestRequiresAbsoluteApplicationsAndJSONReportPaths() throws {
        let request = try XCTUnwrap(
            QuillCodeDesktopRelocationSmokeRequest(arguments: [
                "Quill Cowork",
                "--native-relocation-smoke",
                "--relocation-smoke-applications", "/tmp/Quill Applications",
                "--relocation-smoke-report", "/tmp/relocation report.json",
            ])
        )
        XCTAssertEqual(request.applicationsURL.path, "/tmp/Quill Applications")
        XCTAssertEqual(request.reportURL.path, "/tmp/relocation report.json")

        let invalidArguments = [
            [
                "--native-relocation-smoke",
                "--relocation-smoke-applications", "relative",
                "--relocation-smoke-report", "/tmp/report.json",
            ],
            [
                "--native-relocation-smoke",
                "--relocation-smoke-applications", "/tmp/Applications",
                "--relocation-smoke-report", "relative.json",
            ],
            [
                "--native-relocation-smoke",
                "--relocation-smoke-applications", "/tmp/Applications",
                "--relocation-smoke-report", "/tmp/report.txt",
            ],
        ]
        for arguments in invalidArguments {
            XCTAssertNil(QuillCodeDesktopRelocationSmokeRequest(arguments: arguments))
        }
    }

    func testInstallNewRequestRoundTripsRollbackPathWithoutShellParsing() throws {
        let root = URL(fileURLWithPath: "/tmp/Quill Cowork install; untouched")
        let request = makeRequest(
            root: root,
            source: root.appendingPathComponent("Mounted Quill Cowork.app"),
            incoming: root.appendingPathComponent(
                ".Quill Cowork.update-\(UUID().uuidString.lowercased()).app"
            ),
            destination: root.appendingPathComponent("Quill Cowork.app"),
            resultURL: root.appendingPathComponent("UpdateResult.json")
        )

        let parsed = try XCTUnwrap(
            QuillCodeDesktopUpdateHelperRequest.parse(
                arguments: [request.helperURL.path] + request.arguments,
                executableURL: request.helperURL
            )
        )

        XCTAssertEqual(parsed.activationMode, .installNew)
        XCTAssertEqual(parsed.rollbackApplicationURL, request.rollbackApplicationURL)
        XCTAssertEqual(parsed.incomingApplicationURL, request.incomingApplicationURL)
        XCTAssertEqual(parsed.destinationApplicationURL, request.destinationApplicationURL)
    }

    func testHelperInstallsIntoEmptyDestinationAfterStableRelaunch() throws {
        let fixture = try makeFixture(suffix: "success")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try makeFakeApplication(
            at: fixture.source,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try makeFakeApplication(
            at: fixture.incoming,
            version: "0.2.0",
            build: "2",
            executableScript: """
            #!/bin/sh
            if [ "$1" = "--quillcode-update-handshake" ] && [ -n "$2" ]; then
              printf 'ready\n' > "$2"
            fi
            sleep 1
            exit 0
            """
        )
        let request = makeRequest(
            root: fixture.workspace,
            source: fixture.source,
            incoming: fixture.incoming,
            destination: fixture.destination,
            resultURL: fixture.resultURL
        )

        XCTAssertEqual(
            QuillCodeDesktopUpdateHelper.run(request, environment: fixture.environment),
            0
        )
        XCTAssertEqual(try bundleBuild(at: fixture.destination), "2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try installResult(at: fixture.resultURL).status, .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.path))
    }

    func testHelperRemovesFailedInstallAndReopensMountedCopy() throws {
        let fixture = try makeFixture(suffix: "rollback")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let rollbackMarker = fixture.root.appendingPathComponent("rollback-launched")
        try makeFakeApplication(
            at: fixture.source,
            version: "0.2.0",
            build: "2",
            executableScript: """
            #!/bin/sh
            printf 'ready' > '\(rollbackMarker.path)'
            exit 0
            """
        )
        try makeFakeApplication(
            at: fixture.incoming,
            version: "0.2.0",
            build: "2",
            executableScript: """
            #!/bin/sh
            if [ "$1" = "--quillcode-update-handshake" ] && [ -n "$2" ]; then
              printf 'ready\n' > "$2"
            fi
            exit 0
            """
        )
        let request = makeRequest(
            root: fixture.workspace,
            source: fixture.source,
            incoming: fixture.incoming,
            destination: fixture.destination,
            resultURL: fixture.resultURL
        )

        XCTAssertEqual(
            QuillCodeDesktopUpdateHelper.run(request, environment: fixture.environment),
            1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        try waitForFile(rollbackMarker)
        let result = try installResult(at: fixture.resultURL)
        XCTAssertEqual(result.status, .failure)
        XCTAssertTrue(result.message.contains("original copy was reopened"))
    }

    func testHelperRejectsInstallWhenDestinationAppearsBeforeActivation() throws {
        let fixture = try makeFixture(suffix: "race")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try makeFakeApplication(
            at: fixture.source,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try makeFakeApplication(
            at: fixture.incoming,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try makeFakeApplication(
            at: fixture.destination,
            version: "9.0.0",
            build: "900",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let request = makeRequest(
            root: fixture.workspace,
            source: fixture.source,
            incoming: fixture.incoming,
            destination: fixture.destination,
            resultURL: fixture.resultURL
        )

        XCTAssertEqual(
            QuillCodeDesktopUpdateHelper.run(request, environment: fixture.environment),
            1
        )
        XCTAssertEqual(try bundleBuild(at: fixture.destination), "900")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertEqual(try installResult(at: fixture.resultURL).status, .failure)
    }

    func testHelperDoesNotClaimNonUUIDStagingApplication() throws {
        let fixture = try makeFixture(suffix: "unowned")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unownedIncoming = fixture.root.appendingPathComponent(
            ".Quill Cowork.update-not-owned.app",
            isDirectory: true
        )
        try makeFakeApplication(
            at: fixture.source,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try makeFakeApplication(
            at: unownedIncoming,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let request = makeRequest(
            root: fixture.workspace,
            source: fixture.source,
            incoming: unownedIncoming,
            destination: fixture.destination,
            resultURL: fixture.resultURL
        )

        XCTAssertEqual(
            QuillCodeDesktopUpdateHelper.run(request, environment: fixture.environment),
            1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: unownedIncoming.path))
        XCTAssertEqual(try installResult(at: fixture.resultURL).status, .failure)
    }

    func testHelperRejectsSymlinkedRollbackApplicationAndRemovesOwnedStaging() throws {
        let fixture = try makeFixture(suffix: "symlink")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let realSource = fixture.root.appendingPathComponent("Real Source.app", isDirectory: true)
        try makeFakeApplication(
            at: realSource,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.source,
            withDestinationURL: realSource
        )
        try makeFakeApplication(
            at: fixture.incoming,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let request = makeRequest(
            root: fixture.workspace,
            source: fixture.source,
            incoming: fixture.incoming,
            destination: fixture.destination,
            resultURL: fixture.resultURL
        )

        XCTAssertEqual(
            QuillCodeDesktopUpdateHelper.run(request, environment: fixture.environment),
            1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incoming.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: realSource.path))
        XCTAssertEqual(try installResult(at: fixture.resultURL).status, .failure)
    }

    private func makeFixture(suffix: String) throws -> RelocationFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "QuillCodeRelocationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let workspace = cacheRoot.appendingPathComponent("install-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let resultURL = root.appendingPathComponent("UpdateResult.json")
        return RelocationFixture(
            root: root,
            workspace: workspace,
            source: root.appendingPathComponent("Mounted Quill Cowork.app", isDirectory: true),
            incoming: root.appendingPathComponent(
                ".Quill Cowork.update-\(UUID().uuidString.lowercased()).app",
                isDirectory: true
            ),
            destination: root.appendingPathComponent("Quill Cowork.app", isDirectory: true),
            resultURL: resultURL,
            environment: QuillCodeDesktopUpdateHelperEnvironment(
                cacheRootURL: cacheRoot,
                resultURL: resultURL,
                parentExitTimeout: 0.1,
                launchHandshakeTimeout: 1,
                launchStabilityDuration: 0.15
            )
        )
    }

    private func makeRequest(
        root: URL,
        source: URL,
        incoming: URL,
        destination: URL,
        resultURL: URL
    ) -> QuillCodeDesktopUpdateHelperRequest {
        QuillCodeDesktopUpdateHelperRequest(
            parentProcessID: Int32.max,
            helperURL: root.appendingPathComponent("install-helper"),
            incomingApplicationURL: incoming,
            destinationApplicationURL: destination,
            handshakeURL: root.appendingPathComponent("launch-install.ack"),
            resultURL: resultURL,
            logURL: root.appendingPathComponent("install.log"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork",
            expectedVersion: "0.2.0",
            expectedBuild: "2",
            expectedCommit: String(repeating: "a", count: 40),
            activationMode: .installNew,
            rollbackApplicationURL: source
        )
    }

    private func bundleBuild(at applicationURL: URL) throws -> String {
        let bundle = try XCTUnwrap(Bundle(url: applicationURL))
        return try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    private func installResult(at url: URL) throws -> QuillCodeDesktopUpdateInstallResult {
        try JSONDecoder().decode(
            QuillCodeDesktopUpdateInstallResult.self,
            from: Data(contentsOf: url)
        )
    }

    private func waitForFile(_ url: URL) throws {
        let deadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            usleep(10_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

private struct RelocationFixture {
    var root: URL
    var workspace: URL
    var source: URL
    var incoming: URL
    var destination: URL
    var resultURL: URL
    var environment: QuillCodeDesktopUpdateHelperEnvironment
}
