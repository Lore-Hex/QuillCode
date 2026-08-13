import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopInstallationLocationTests: XCTestCase {
    func testProductionDependenciesRemainLazyUntilLocationIsInspected() {
        let controller = QuillCodeDesktopInstallationLocationController(
            configuration: makeDiskImageConfiguration(),
            defaults: makeDefaults()
        )

        XCTAssertEqual(controller.materializedDependencies, [])

        controller.startIfNeeded()

        XCTAssertEqual(controller.materializedDependencies, [.inspector])
    }

    func testDisabledLocationControllerNeverMaterializesDependencies() {
        let controller = QuillCodeDesktopInstallationLocationController(
            configuration: nil,
            defaults: makeDefaults()
        )

        controller.startIfNeeded()
        XCTAssertFalse(controller.presentForUpdate())
        controller.moveAndRelaunch()

        XCTAssertEqual(controller.materializedDependencies, [])
    }

    func testWritableApplicationDoesNotPresentReminder() {
        let controller = makeController(availability: .available)

        controller.startIfNeeded()

        XCTAssertFalse(controller.isPresented)
    }

    func testReadOnlyApplicationAlreadyInApplicationsDoesNotPresentReminder() {
        var configuration = makeConfiguration()
        configuration.applicationURL = URL(
            fileURLWithPath: "/Applications/Quill Cowork.app",
            isDirectory: true
        )
        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation
        )

        controller.startIfNeeded()

        XCTAssertFalse(controller.isPresented)
    }

    func testReadOnlyApplicationPresentsAndDismissesOncePerBuild() {
        let defaults = makeDefaults()
        let configuration = makeDiskImageConfiguration(currentBuild: "43")
        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation,
            defaults: defaults
        )

        controller.startIfNeeded()
        XCTAssertTrue(controller.isPresented)

        controller.dismiss()
        XCTAssertFalse(controller.isPresented)
        controller.startIfNeeded()
        XCTAssertFalse(controller.isPresented)

        var nextBuild = configuration
        nextBuild.currentBuild = "44"
        let nextBuildController = makeController(
            configuration: nextBuild,
            availability: .requiresRelocation,
            defaults: defaults
        )
        nextBuildController.startIfNeeded()
        XCTAssertTrue(nextBuildController.isPresented)
    }

    func testPendingUpdateRelocationOverridesEarlierDismissal() {
        let defaults = makeDefaults()
        let configuration = makeDiskImageConfiguration()
        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation,
            defaults: defaults
        )
        controller.startIfNeeded()
        controller.dismiss()
        XCTAssertFalse(controller.isPresented)

        QuillCodeDesktopRelocationUpdateIntentStore(defaults: defaults).record(
            configuration: configuration
        )
        let relaunchedController = makeController(
            configuration: configuration,
            availability: .requiresRelocation,
            defaults: defaults
        )

        relaunchedController.startIfNeeded()

        XCTAssertTrue(relaunchedController.isPresented)
    }

    func testOpenApplicationsDismissesAndOpensConfiguredFolder() {
        let applicationsURL = URL(fileURLWithPath: "/Test Applications", isDirectory: true)
        var openedURL: URL?
        let controller = makeController(
            availability: .requiresRelocation,
            applicationsURL: applicationsURL,
            openApplications: { openedURL = $0 }
        )
        controller.startIfNeeded()
        XCTAssertTrue(controller.isPresented)

        controller.openApplicationsFolder()

        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(openedURL, applicationsURL.standardizedFileURL)
    }

    func testMoveStagesVerifiedCopyAndTerminatesForRelaunch() async throws {
        let relocator = InstallationRelocatorSpy()
        var terminationCount = 0
        let applicationsURL = URL(fileURLWithPath: "/Test Applications", isDirectory: true)
        let controller = makeController(
            availability: .requiresRelocation,
            applicationsURL: applicationsURL,
            relocator: relocator,
            terminateApplication: { terminationCount += 1 }
        )
        controller.startIfNeeded()

        controller.moveAndRelaunch()

        try await waitUntil { terminationCount == 1 }
        XCTAssertEqual(controller.state, .moving)
        XCTAssertTrue(controller.isPresented)
        let calls = await relocator.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.configuration, makeDiskImageConfiguration())
        XCTAssertEqual(call.applicationsURL, applicationsURL.standardizedFileURL)
    }

    func testUpdateRequestedMoveRecordsOneShotContinuationAfterStaging() async throws {
        let defaults = makeDefaults()
        let configuration = makeDiskImageConfiguration()
        let intentStore = QuillCodeDesktopRelocationUpdateIntentStore(defaults: defaults)
        let relocator = InstallationRelocatorSpy()
        var terminationCount = 0
        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation,
            defaults: defaults,
            relocator: relocator,
            terminateApplication: { terminationCount += 1 }
        )

        XCTAssertTrue(controller.presentForUpdate())
        controller.moveAndRelaunch()

        try await waitUntil { terminationCount == 1 }
        XCTAssertTrue(intentStore.hasPendingIntent(configuration: configuration))
        XCTAssertTrue(intentStore.consume(configuration: configuration))
        XCTAssertFalse(intentStore.consume(configuration: configuration))
    }

    func testExpiredUpdateRelocationIntentDoesNotOverrideDismissal() {
        let defaults = makeDefaults()
        let configuration = makeDiskImageConfiguration()
        var date = Date(timeIntervalSince1970: 10_000)
        let intentStore = QuillCodeDesktopRelocationUpdateIntentStore(
            defaults: defaults,
            now: { date }
        )
        intentStore.record(configuration: configuration)
        date.addTimeInterval(QuillCodeDesktopRelocationUpdateIntentStore.maximumAge + 1)

        let controller = makeController(
            configuration: configuration,
            availability: .requiresRelocation,
            defaults: defaults
        )
        controller.startIfNeeded()
        controller.dismiss()
        controller.startIfNeeded()

        XCTAssertFalse(intentStore.hasPendingIntent(configuration: configuration))
        XCTAssertFalse(controller.isPresented)
    }

    func testMoveFailureOffersRetryWithoutTerminating() async throws {
        let relocator = InstallationRelocatorSpy(error: .verificationFailed)
        var terminationCount = 0
        let controller = makeController(
            availability: .requiresRelocation,
            relocator: relocator,
            terminateApplication: { terminationCount += 1 }
        )
        controller.startIfNeeded()

        controller.moveAndRelaunch()

        let expectedMessage = QuillCodeDesktopApplicationRelocationError.verificationFailed
            .localizedDescription
        try await waitUntil { controller.state == .failed(message: expectedMessage) }
        XCTAssertEqual(terminationCount, 0)
        XCTAssertTrue(controller.isPresented)

        await relocator.setError(nil)
        controller.moveAndRelaunch()
        try await waitUntil { terminationCount == 1 }
        let calls = await relocator.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testAnotherRunningCopyStopsBeforeStaging() async {
        let relocator = InstallationRelocatorSpy()
        let controller = makeController(
            availability: .requiresRelocation,
            relocator: relocator,
            hasOtherRunningCopy: { _ in true }
        )
        controller.startIfNeeded()

        controller.moveAndRelaunch()

        XCTAssertEqual(
            controller.state,
            .failed(
                message: QuillCodeDesktopApplicationRelocationError.otherCopyRunning
                    .localizedDescription
            )
        )
        let calls = await relocator.calls
        XCTAssertEqual(calls.count, 0)
    }

    func testMovingStateCannotBeDismissedOrOpenFinder() async throws {
        let relocator = InstallationRelocatorSpy(delay: .milliseconds(120))
        var openedURL: URL?
        var terminationCount = 0
        let controller = makeController(
            availability: .requiresRelocation,
            relocator: relocator,
            openApplications: { openedURL = $0 },
            terminateApplication: { terminationCount += 1 }
        )
        controller.startIfNeeded()
        controller.moveAndRelaunch()
        try await waitUntil { await relocator.calls.count == 1 }

        controller.dismiss()
        controller.openApplicationsFolder()

        XCTAssertTrue(controller.isPresented)
        XCTAssertNil(openedURL)
        try await waitUntil { terminationCount == 1 }
    }

    func testUnavailableConfigurationNeverPresents() {
        let controller = QuillCodeDesktopInstallationLocationController(
            configuration: nil,
            inspector: InstallationLocationInspectorStub(.requiresRelocation),
            defaults: makeDefaults(),
            openApplications: { _ in XCTFail("Should not open Applications") }
        )

        controller.startIfNeeded()
        controller.dismiss()

        XCTAssertFalse(controller.isPresented)
    }

    private func makeController(
        configuration: QuillCodeDesktopUpdateConfiguration? = nil,
        availability: QuillCodeDesktopUpdateInstallationAvailability,
        defaults: UserDefaults? = nil,
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        relocator: any QuillCodeDesktopApplicationRelocating = InstallationRelocatorSpy(),
        openApplications: @escaping @MainActor (URL) -> Void = { _ in },
        hasOtherRunningCopy: @escaping @MainActor (String) -> Bool = { _ in false },
        terminateApplication: @escaping @MainActor () -> Void = {}
    ) -> QuillCodeDesktopInstallationLocationController {
        QuillCodeDesktopInstallationLocationController(
            configuration: configuration ?? makeDiskImageConfiguration(),
            inspector: InstallationLocationInspectorStub(availability),
            relocator: relocator,
            defaults: defaults ?? makeDefaults(),
            applicationsURL: applicationsURL,
            openApplications: openApplications,
            hasOtherRunningCopy: hasOtherRunningCopy,
            terminateApplication: terminateApplication
        )
    }

    private func makeDiskImageConfiguration(
        currentBuild: String = "42"
    ) -> QuillCodeDesktopUpdateConfiguration {
        var configuration = makeConfiguration(currentBuild: currentBuild)
        configuration.applicationURL = URL(
            fileURLWithPath: "/Volumes/Quill Cowork/Quill Cowork.app",
            isDirectory: true
        )
        return configuration
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "InstallationLocationTests.\(UUID().uuidString)") ?? .standard
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            if clock.now >= deadline {
                return XCTFail("Timed out waiting for installation state")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor InstallationRelocatorSpy: QuillCodeDesktopApplicationRelocating {
    struct Call: Sendable {
        var configuration: QuillCodeDesktopUpdateConfiguration
        var applicationsURL: URL
    }

    private(set) var calls: [Call] = []
    private var error: QuillCodeDesktopApplicationRelocationError?
    private let delay: Duration?

    init(
        error: QuillCodeDesktopApplicationRelocationError? = nil,
        delay: Duration? = nil
    ) {
        self.error = error
        self.delay = delay
    }

    func setError(_ error: QuillCodeDesktopApplicationRelocationError?) {
        self.error = error
    }

    func stageAndLaunch(
        configuration: QuillCodeDesktopUpdateConfiguration,
        applicationsURL: URL
    ) async throws {
        calls.append(Call(configuration: configuration, applicationsURL: applicationsURL))
        if let delay {
            try await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
    }
}

private struct InstallationLocationInspectorStub: QuillCodeDesktopUpdateInstallationInspecting {
    var availabilityValue: QuillCodeDesktopUpdateInstallationAvailability

    init(_ availabilityValue: QuillCodeDesktopUpdateInstallationAvailability) {
        self.availabilityValue = availabilityValue
    }

    func availability(
        for configuration: QuillCodeDesktopUpdateConfiguration
    ) -> QuillCodeDesktopUpdateInstallationAvailability {
        availabilityValue
    }
}
