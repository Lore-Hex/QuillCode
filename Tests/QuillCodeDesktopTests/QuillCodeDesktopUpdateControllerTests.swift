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
            installationInspector: UpdateInstallationInspectorStub(.available),
            defaults: defaults,
            automaticSchedule: makeAutomaticSchedule(),
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

    func testReadOnlyLocationStopsBeforeDownloadAndKeepsManualInstaller() async throws {
        var release = makeRelease(version: "0.2.0", build: "7")
        release.installerAsset = makeManualInstallerAsset()
        let preparer = UpdatePreparerSpy(release: release)
        let installer = UpdateInstallerSpy()
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: UpdateCheckerSpy(result: .updateAvailable(release)),
            preparer: preparer,
            installer: installer,
            installationInspector: UpdateInstallationInspectorStub(.requiresRelocation),
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL()
        )

        controller.checkForUpdates()
        try await waitUntil { controller.state == .updateAvailable(release) }
        XCTAssertTrue(controller.updateRequiresManualInstallation)
        XCTAssertEqual(release.manualInstallationURL, makeManualInstallerAsset().url)

        controller.updateAndRelaunch()

        XCTAssertEqual(
            controller.state,
            .failed(
                message: QuillCodeDesktopUpdateError.installationUnavailable.localizedDescription,
                release: release
            )
        )
        let prepareCallCount = await preparer.callCount
        let installCallCount = await installer.callCount
        XCTAssertEqual(prepareCallCount, 0)
        XCTAssertEqual(installCallCount, 0)
    }

    func testRecentSuccessfulAutomaticCheckSuppressesNetworkWork() async throws {
        let defaults = makeDefaults()
        defaults.set(Date(), forKey: "QuillCodeUpdater.lastSuccessfulCheck.tester")
        let checker = UpdateCheckerSpy(result: .upToDate(latestVersion: "0.1.0", latestBuild: "42"))
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: defaults,
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()
        try await Task.sleep(for: .milliseconds(50))

        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 0)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
    }

    func testAutomaticStartupRunsInterruptedUpdateRecoveryOnlyOnce() async throws {
        let recovery = UpdateRecoverySpy()
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: UpdateCheckerSpy(
                result: .upToDate(latestVersion: "0.1.0", latestBuild: "42")
            ),
            recovery: recovery,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(initialDelay: 60),
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()
        controller.startAutomaticChecks()

        try await waitUntil { await recovery.callCount == 1 }
        let recoveryCallCount = await recovery.callCount
        XCTAssertEqual(recoveryCallCount, 1)
    }

    func testBackgroundFailureStaysQuietButManualFailureIsVisible() async throws {
        let checker = UpdateCheckerSpy(error: .invalidResponse)
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
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
        try Data(
            repeating: 0x41,
            count: QuillCodeDesktopUpdateInstallResult.maximumEncodedBytes + 1
        ).write(to: resultURL)
        let controller = QuillCodeDesktopUpdateController(
            configuration: nil,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: resultURL
        )

        controller.startAutomaticChecks()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resultURL.path))
    }

    func testDanglingInstallResultSymlinkIsDiscardedWithoutPresenting() throws {
        let resultURL = temporaryInstallResultURL()
        try FileManager.default.createDirectory(
            at: resultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: resultURL,
            withDestinationURL: resultURL.deletingLastPathComponent()
                .appendingPathComponent("missing-result.json")
        )
        let controller = QuillCodeDesktopUpdateController(
            configuration: nil,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: resultURL
        )

        controller.startAutomaticChecks()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
        XCTAssertThrowsError(
            try FileManager.default.destinationOfSymbolicLink(atPath: resultURL.path)
        )
    }

    func testAutomaticChecksContinueWhileAppRemainsOpen() async throws {
        let checker = UpdateCheckerSpy(
            result: .upToDate(latestVersion: "0.1.0", latestBuild: "42")
        )
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(testerInterval: 0.02),
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()

        try await waitUntil { await checker.callCount >= 2 }
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
    }

    func testAutomaticFailureRetriesQuietly() async throws {
        let checker = UpdateCheckerSpy(responses: [
            .failure(.invalidResponse),
            .success(.upToDate(latestVersion: "0.1.0", latestBuild: "42")),
        ])
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(failureRetryInterval: 0.02),
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()

        try await waitUntil { await checker.callCount >= 2 }
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isPresented)
    }

    func testDismissedAutomaticReleaseStaysHiddenAfterRestartAndManualCheckOverridesDeferral() async throws {
        let release = makeRelease(version: "0.2.0", build: "7")
        let defaults = makeDefaults()
        var controller: QuillCodeDesktopUpdateController? = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: UpdateCheckerSpy(result: .updateAvailable(release)),
            defaults: defaults,
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL()
        )

        controller?.startAutomaticChecks()
        try await waitUntil {
            controller?.state == .updateAvailable(release) && controller?.isPresented == true
        }
        controller?.dismiss()
        XCTAssertFalse(try XCTUnwrap(controller).isPresented)

        weak let releasedController = controller
        controller = nil
        try await waitUntil { releasedController == nil }

        let restartedChecker = UpdateCheckerSpy(result: .updateAvailable(release))
        let restartedController = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: restartedChecker,
            defaults: defaults,
            now: { Date().addingTimeInterval(61) },
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL()
        )
        restartedController.startAutomaticChecks()
        try await waitUntil { await restartedChecker.callCount >= 1 }
        XCTAssertEqual(restartedController.state, .updateAvailable(release))
        XCTAssertFalse(restartedController.isPresented)

        restartedController.checkForUpdates()
        try await waitUntil { await restartedChecker.callCount >= 2 }
        try await waitUntil {
            restartedController.state == .updateAvailable(release) && restartedController.isPresented
        }
    }

    func testNewAutomaticReleaseBypassesPersistedDeferral() async throws {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let oldRelease = makeRelease(version: "0.2.0", build: "7")
        let newRelease = makeRelease(version: "0.2.0", build: "8")
        QuillCodeDesktopUpdateReminderStore(defaults: defaults).recordDeferral(
            oldRelease,
            configuration: configuration,
            now: Date()
        )
        let controller = QuillCodeDesktopUpdateController(
            configuration: configuration,
            checker: UpdateCheckerSpy(result: .updateAvailable(newRelease)),
            defaults: defaults,
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()

        try await waitUntil { controller.state == .updateAvailable(newRelease) }
        XCTAssertTrue(controller.isPresented)
    }

    func testReminderDeadlineRepresentsCachedReleaseBeforeLongChannelInterval() async throws {
        let release = makeRelease(version: "0.2.0", build: "7")
        let checker = UpdateCheckerSpy(result: .updateAvailable(release))
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        QuillCodeDesktopUpdateReminderStore(
            defaults: defaults,
            reminderInterval: 0.08
        ).recordDeferral(
            release,
            configuration: configuration,
            now: Date()
        )
        let controller = QuillCodeDesktopUpdateController(
            configuration: configuration,
            checker: checker,
            defaults: defaults,
            automaticSchedule: makeAutomaticSchedule(testerInterval: 1),
            reminderInterval: 0.08,
            installResultURL: temporaryInstallResultURL()
        )

        controller.startAutomaticChecks()
        try await waitUntil { await checker.callCount >= 1 }
        XCTAssertFalse(controller.isPresented)

        try await waitUntil(timeout: .milliseconds(500)) { controller.isPresented }
        let callCount = await checker.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testManualSuccessReschedulesPendingAutomaticCheck() async throws {
        let checker = UpdateCheckerSpy(
            result: .upToDate(latestVersion: "0.1.0", latestBuild: "42")
        )
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(initialDelay: 0.05),
            installResultURL: temporaryInstallResultURL()
        )
        controller.startAutomaticChecks()

        controller.checkForUpdates()
        try await waitUntil {
            if case .upToDate = controller.state { return true }
            return false
        }
        try await Task.sleep(for: .milliseconds(100))

        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 1)
    }

    func testManualCheckDoesNotInterruptActiveDownload() async throws {
        let release = makeRelease(version: "0.2.0", build: "7")
        let checker = UpdateCheckerSpy(result: .updateAvailable(release))
        let preparer = UpdatePreparerSpy(release: release, delay: .milliseconds(100))
        let installer = UpdateInstallerSpy()
        var terminationCount = 0
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            preparer: preparer,
            installer: installer,
            installationInspector: UpdateInstallationInspectorStub(.available),
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL(),
            terminateApplication: { terminationCount += 1 }
        )

        controller.checkForUpdates()
        try await waitUntil { controller.state == .updateAvailable(release) }
        controller.updateAndRelaunch()
        try await waitUntil {
            if case .downloading = controller.state { return true }
            return false
        }

        controller.checkForUpdates()

        XCTAssertEqual(controller.state, .downloading(release))
        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 1)
        try await waitUntil { terminationCount == 1 }
    }

    func testCancelIsIgnoredAfterActivationStarts() async throws {
        let release = makeRelease(version: "0.2.0", build: "7")
        let checker = UpdateCheckerSpy(result: .updateAvailable(release))
        let installer = UpdateInstallerSpy(delay: .milliseconds(100))
        var terminationCount = 0
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            preparer: UpdatePreparerSpy(release: release),
            installer: installer,
            installationInspector: UpdateInstallationInspectorStub(.available),
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL(),
            terminateApplication: { terminationCount += 1 }
        )

        controller.checkForUpdates()
        try await waitUntil { controller.state == .updateAvailable(release) }
        controller.updateAndRelaunch()
        try await waitUntil {
            if case .installing = controller.state { return true }
            return false
        }

        controller.cancelCurrentOperation()

        XCTAssertEqual(controller.state, .installing(release))
        try await waitUntil { terminationCount == 1 }
    }

    func testPreparationProgressAdvancesAndClearsBeforeActivation() async throws {
        let release = makeRelease(version: "0.2.0", build: "7")
        let progressUpdates: [QuillCodeDesktopUpdatePreparationProgress] = [
            .downloading(receivedBytes: 5_000, totalBytes: 10_000),
            .verifying,
            .extracting,
            .validatingApplication,
        ]
        let progressGate = UpdatePreparationProgressGate()
        let preparer = UpdatePreparerSpy(
            release: release,
            progressUpdates: progressUpdates,
            progressGate: progressGate
        )
        let installer = UpdateInstallerSpy(delay: .milliseconds(100))
        var terminationCount = 0
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: UpdateCheckerSpy(result: .updateAvailable(release)),
            preparer: preparer,
            installer: installer,
            installationInspector: UpdateInstallationInspectorStub(.available),
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL(),
            terminateApplication: { terminationCount += 1 }
        )

        controller.checkForUpdates()
        try await waitUntil { controller.state == .updateAvailable(release) }
        controller.updateAndRelaunch()

        try await waitUntil {
            controller.preparationProgress == .downloading(
                receivedBytes: 5_000,
                totalBytes: 10_000
            )
        }
        XCTAssertEqual(controller.preparationProgress?.downloadFraction, 0.5)
        await progressGate.advance()
        try await waitUntil { controller.preparationProgress == .verifying }
        await progressGate.advance()
        try await waitUntil { controller.preparationProgress == .extracting }
        await progressGate.advance()
        try await waitUntil { controller.preparationProgress == .validatingApplication }
        await progressGate.advance()
        try await waitUntil {
            if case .installing = controller.state { return true }
            return false
        }
        XCTAssertNil(controller.preparationProgress)
        try await waitUntil { terminationCount == 1 }
    }

    func testVisibleInstallFailureDefersAutomaticNetworkWork() async throws {
        let resultURL = temporaryInstallResultURL()
        try FileManager.default.createDirectory(
            at: resultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let result = QuillCodeDesktopUpdateInstallResult.failure(message: "The previous build was restored.")
        try JSONEncoder().encode(result).write(to: resultURL)
        let checker = UpdateCheckerSpy(
            result: .upToDate(latestVersion: "0.1.0", latestBuild: "42")
        )
        let controller = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(busyRetryInterval: 0.02),
            installResultURL: resultURL
        )

        controller.startAutomaticChecks()
        try await Task.sleep(for: .milliseconds(75))

        XCTAssertEqual(
            controller.state,
            .failed(message: "The previous build was restored.", release: nil)
        )
        XCTAssertTrue(controller.isPresented)
        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 0)
    }

    func testAutomaticSchedulerDoesNotRetainControllerBetweenChecks() async throws {
        let checker = UpdateCheckerSpy(
            result: .upToDate(latestVersion: "0.1.0", latestBuild: "42")
        )
        weak var weakController: QuillCodeDesktopUpdateController?
        var controller: QuillCodeDesktopUpdateController? = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            defaults: makeDefaults(),
            automaticSchedule: makeAutomaticSchedule(),
            installResultURL: temporaryInstallResultURL()
        )
        weakController = controller
        controller?.startAutomaticChecks()
        try await waitUntil { await checker.callCount == 1 }

        controller = nil

        try await waitUntil { weakController == nil }
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

    private func makeAutomaticSchedule(
        initialDelay: TimeInterval = 0,
        testerInterval: TimeInterval = 60,
        failureRetryInterval: TimeInterval = 60,
        busyRetryInterval: TimeInterval = 60
    ) -> QuillCodeDesktopUpdateSchedule {
        QuillCodeDesktopUpdateSchedule(
            initialDelay: initialDelay,
            testerInterval: testerInterval,
            stableInterval: 60,
            failureRetryInterval: failureRetryInterval,
            busyRetryInterval: busyRetryInterval
        )
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
    private var responses: [Result<QuillCodeDesktopUpdateCheckResult, QuillCodeDesktopUpdateError>]
    private(set) var callCount = 0

    init(result: QuillCodeDesktopUpdateCheckResult) {
        self.responses = [.success(result)]
    }

    init(error: QuillCodeDesktopUpdateError) {
        self.responses = [.failure(error)]
    }

    init(responses: [Result<QuillCodeDesktopUpdateCheckResult, QuillCodeDesktopUpdateError>]) {
        self.responses = responses
    }

    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult {
        callCount += 1
        guard let response = responses.first else {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        if responses.count > 1 {
            responses.removeFirst()
        }
        return try response.get()
    }
}

private actor UpdatePreparerSpy: QuillCodeDesktopUpdatePreparing {
    private let release: QuillCodeDesktopUpdateRelease
    private let delay: Duration?
    private let progressUpdates: [QuillCodeDesktopUpdatePreparationProgress]
    private let progressGate: UpdatePreparationProgressGate?
    private(set) var callCount = 0

    init(
        release: QuillCodeDesktopUpdateRelease,
        delay: Duration? = nil,
        progressUpdates: [QuillCodeDesktopUpdatePreparationProgress] = [],
        progressGate: UpdatePreparationProgressGate? = nil
    ) {
        self.release = release
        self.delay = delay
        self.progressUpdates = progressUpdates
        self.progressGate = progressGate
    }

    func prepare(
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        progress: @escaping @Sendable (QuillCodeDesktopUpdatePreparationProgress) -> Void
    ) async throws -> QuillCodeDesktopPreparedUpdate {
        callCount += 1
        for update in progressUpdates {
            progress(update)
            if let progressGate {
                await progressGate.wait()
            }
        }
        if let delay {
            try await Task.sleep(for: delay)
        }
        return QuillCodeDesktopPreparedUpdate(
            release: self.release,
            applicationURL: URL(fileURLWithPath: "/tmp/Quill Cowork.app"),
            workspaceURL: URL(fileURLWithPath: "/tmp/quill-cowork-update")
        )
    }
}

private actor UpdatePreparationProgressGate {
    private var permits = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func advance() {
        guard !waiters.isEmpty else {
            permits += 1
            return
        }
        waiters.removeFirst().resume()
    }
}

private actor UpdateInstallerSpy: QuillCodeDesktopUpdateInstalling {
    private let delay: Duration?
    private(set) var callCount = 0

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    func stageAndLaunch(
        preparedUpdate: QuillCodeDesktopPreparedUpdate,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws {
        callCount += 1
        if let delay {
            try await Task.sleep(for: delay)
        }
    }
}

private struct UpdateInstallationInspectorStub: QuillCodeDesktopUpdateInstallationInspecting {
    let value: QuillCodeDesktopUpdateInstallationAvailability

    init(_ value: QuillCodeDesktopUpdateInstallationAvailability) {
        self.value = value
    }

    func availability(
        for configuration: QuillCodeDesktopUpdateConfiguration
    ) -> QuillCodeDesktopUpdateInstallationAvailability {
        value
    }
}

private actor UpdateRecoverySpy: QuillCodeDesktopUpdateRecovering {
    private(set) var callCount = 0

    func recoverInterruptedUpdate(configuration: QuillCodeDesktopUpdateConfiguration) async {
        callCount += 1
    }
}
