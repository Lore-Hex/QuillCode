import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopUpdateControllerTests: XCTestCase {
    func testManualCheckShowsAvailableUpdateThenInstallsAndTerminates() async throws {
        let release = makeRelease(version: "0.2.0", build: "7")
        let checker = UpdateCheckerSpy(result: .updateAvailable(release))
        let preparer = UpdatePreparerSpy(release: release)
        let installer = UpdateInstallerSpy()
        let defaults = makeDefaults()
        var terminationCount = 0
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            preparer: preparer,
            installer: installer,
            defaults: defaults,
            automaticCheckDelay: .zero,
            installResultURL: temporaryInstallResultURL(),
            terminateApplication: { terminationCount += 1 }
        )

        controller.checkForUpdates()
        try await waitUntil { controller.state == .updateAvailable(release) }
        XCTAssertTrue(controller.isPresented)

        controller.updateAndRelaunch()
        try await waitUntil { terminationCount == 1 }

        let prepareCallCount = await preparer.callCount
        let installCallCount = await installer.callCount
        XCTAssertEqual(prepareCallCount, 1)
        XCTAssertEqual(installCallCount, 1)
    }

    func testRecentSuccessfulAutomaticCheckSuppressesNetworkWork() async throws {
        let defaults = makeDefaults()
        defaults.set(Date(), forKey: "QuillCodeUpdater.lastSuccessfulCheck.tester")
        let checker = UpdateCheckerSpy(result: .upToDate(latestVersion: "0.1.0", latestBuild: "42"))
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: defaults,
            automaticCheckDelay: .zero,
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()
        try await Task.sleep(for: .milliseconds(50))

        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 0)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
    }

    func testBackgroundFailureStaysQuietButManualFailureIsVisible() async throws {
        let checker = UpdateCheckerSpy(error: .invalidResponse)
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticCheckDelay: .zero,
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()
        try await waitUntil { await checker.callCount == 1 }
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)

        controller.checkForUpdates()
        try await waitUntil {
            if case .failed = controller.state { return true }
            return false
        }
        XCTAssertTrue(controller.isPresented)
    }

    func testOversizedInstallResultIsDiscardedWithoutPresenting() throws {
        let resultURL = temporaryInstallResultURL()
        try FileManager.default.createDirectory(
            at: resultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 64 * 1_024 + 1).write(to: resultURL)
        let controller = QuillCodeDesktopUpdateController(
            configuration: nil,
            defaults: makeDefaults(),
            automaticCheckDelay: .zero,
            installResultURL: resultURL
        )

        controller.startAutomaticChecks()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resultURL.path))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "QuillCodeDesktopUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryInstallResultURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("UpdateResult.json")
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for updater state")
    }
}

private actor UpdateCheckerSpy: QuillCodeDesktopUpdateChecking {
    private let result: QuillCodeDesktopUpdateCheckResult?
    private let error: QuillCodeDesktopUpdateError?
    private(set) var callCount = 0

    init(result: QuillCodeDesktopUpdateCheckResult) {
        self.result = result
        self.error = nil
    }

    init(error: QuillCodeDesktopUpdateError) {
        self.result = nil
        self.error = error
    }

    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult {
        callCount += 1
        if let error { throw error }
        return result!
    }
}

private actor UpdatePreparerSpy: QuillCodeDesktopUpdatePreparing {
    private let release: QuillCodeDesktopUpdateRelease
    private(set) var callCount = 0

    init(release: QuillCodeDesktopUpdateRelease) {
        self.release = release
    }

    func prepare(
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopPreparedUpdate {
        callCount += 1
        return QuillCodeDesktopPreparedUpdate(
            release: self.release,
            applicationURL: URL(fileURLWithPath: "/tmp/Quill Cowork.app"),
            workspaceURL: URL(fileURLWithPath: "/tmp/quill-cowork-update")
        )
    }
}

private actor UpdateInstallerSpy: QuillCodeDesktopUpdateInstalling {
    private(set) var callCount = 0

    func stageAndLaunch(
        preparedUpdate: QuillCodeDesktopPreparedUpdate,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws {
        callCount += 1
    }
}
