import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopApplicationServicesTests: XCTestCase {
    func testNotificationOwnershipRequiresCanonicalPackagedApplicationLayout() {
        let applicationURL = URL(
            fileURLWithPath: "/Applications/Quill Cowork.app",
            isDirectory: true
        )
        let executableURL = applicationURL
            .appendingPathComponent("Contents/MacOS/Quill Cowork")

        XCTAssertTrue(QuillCodeDesktopPackagedProcessIdentity.ownsNotificationCenter(
            bundleIdentifier: "co.lorehex.QuillCowork",
            bundleURL: applicationURL,
            executableURL: executableURL,
            expectedBundleIdentifier: "co.lorehex.QuillCowork"
        ))
        XCTAssertFalse(QuillCodeDesktopPackagedProcessIdentity.ownsNotificationCenter(
            bundleIdentifier: "co.lorehex.QuillCowork",
            bundleURL: URL(fileURLWithPath: "/tmp/.build/debug", isDirectory: true),
            executableURL: URL(fileURLWithPath: "/tmp/.build/debug/Quill Cowork"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork"
        ))
    }

    func testNotificationOwnershipRejectsMismatchedIdentityAndEscapedExecutable() {
        let applicationURL = URL(
            fileURLWithPath: "/Applications/Quill Cowork.app",
            isDirectory: true
        )

        XCTAssertFalse(QuillCodeDesktopPackagedProcessIdentity.ownsNotificationCenter(
            bundleIdentifier: "co.example.Lookalike",
            bundleURL: applicationURL,
            executableURL: applicationURL.appendingPathComponent("Contents/MacOS/Quill Cowork"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork"
        ))
        XCTAssertFalse(QuillCodeDesktopPackagedProcessIdentity.ownsNotificationCenter(
            bundleIdentifier: "co.lorehex.QuillCowork",
            bundleURL: applicationURL,
            executableURL: URL(fileURLWithPath: "/tmp/Quill Cowork"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork"
        ))
    }

    func testApplicationServicesStartAtFirstWindowBoundaryAndRemainIdempotent() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = QuillCodePaths(home: root.appendingPathComponent("state", isDirectory: true))
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let recovery = ApplicationServiceRecoverySpy()
        let checker = ApplicationServiceUpdateCheckerSpy()
        let updateController = QuillCodeDesktopUpdateController(
            configuration: makeConfiguration(),
            checker: checker,
            recovery: recovery,
            defaults: makeDefaults(),
            automaticSchedule: QuillCodeDesktopUpdateSchedule(
                initialDelay: 60,
                testerInterval: 60,
                stableInterval: 60,
                failureRetryInterval: 60,
                busyRetryInterval: 60
            ),
            installResultURL: nil
        )
        var installationConfiguration = makeConfiguration()
        installationConfiguration.applicationURL = URL(
            fileURLWithPath: "/Volumes/Quill Cowork/Quill Cowork.app",
            isDirectory: true
        )
        let installationController = QuillCodeDesktopInstallationLocationController(
            configuration: installationConfiguration,
            inspector: ApplicationServiceInstallationInspector(),
            defaults: makeDefaults()
        )
        let controller = QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            browserLiveDOMCapturer: nil,
            automationNotifier: ApplicationServiceNoopNotifier(),
            updateController: updateController,
            installationLocationController: installationController,
            startupMode: .recovery,
            workspaceRoot: root
        )

        XCTAssertFalse(installationController.isPresented)
        XCTAssertFalse(controller.postWindowApplicationServicesStarted)
        let preWindowRecoveryCallCount = await recovery.callCount
        XCTAssertEqual(preWindowRecoveryCallCount, 0)

        controller.completeStartupIfAllowed()
        controller.completeStartupIfAllowed()

        XCTAssertTrue(installationController.isPresented)
        XCTAssertTrue(controller.postWindowApplicationServicesStarted)
        XCTAssertFalse(controller.automaticWorkspaceServicesStarted)
        try await waitUntil { await recovery.callCount == 1 }
        let checkerCallCount = await checker.callCount
        XCTAssertEqual(checkerCallCount, 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "QuillCodeDesktopApplicationServicesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            if clock.now >= deadline {
                return XCTFail("Timed out waiting for application services")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor ApplicationServiceRecoverySpy: QuillCodeDesktopUpdateRecovering {
    private(set) var callCount = 0

    func recoverInterruptedUpdate(configuration: QuillCodeDesktopUpdateConfiguration) async {
        callCount += 1
    }
}

private actor ApplicationServiceUpdateCheckerSpy: QuillCodeDesktopUpdateChecking {
    private(set) var callCount = 0

    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult {
        callCount += 1
        return .upToDate(latestVersion: configuration.currentVersion, latestBuild: configuration.currentBuild)
    }
}

private struct ApplicationServiceInstallationInspector: QuillCodeDesktopUpdateInstallationInspecting {
    func availability(
        for configuration: QuillCodeDesktopUpdateConfiguration
    ) -> QuillCodeDesktopUpdateInstallationAvailability {
        .requiresRelocation
    }
}

private struct ApplicationServiceNoopNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
