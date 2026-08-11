import AppKit
import Foundation
import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopLaunchLifecycleTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadyUnexpectedExitIsReportedAndGracefulRelaunchDoesNotRepeatIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let first = try fixture.store.beginLaunch(
            metadata: metadata(build: "697"),
            now: referenceDate,
            processIdentifier: 10_001,
            processIsRunning: { _ in false }
        )
        XCTAssertNil(first.unexpectedExit)
        try fixture.store.markReady(launchID: first.currentRecord.launchID)

        let second = try fixture.store.beginLaunch(
            metadata: metadata(build: "698"),
            now: referenceDate.addingTimeInterval(30),
            processIdentifier: 10_002,
            processIsRunning: { _ in false }
        )
        let incident = try XCTUnwrap(second.unexpectedExit)
        XCTAssertEqual(incident.phase, .ready)
        XCTAssertEqual(incident.metadata.build, "697")
        XCTAssertFalse(incident.requiresRecoveryStartup)
        XCTAssertEqual(QuillCodeDesktopStartupMode(unexpectedExit: incident), .normal)
        XCTAssertTrue(incident.userMessage.contains("in-progress command may be incomplete"))

        try fixture.store.finishLaunch(launchID: second.currentRecord.launchID)
        let third = try fixture.store.beginLaunch(
            metadata: metadata(build: "699"),
            now: referenceDate.addingTimeInterval(60),
            processIdentifier: 10_003,
            processIsRunning: { _ in false }
        )
        XCTAssertNil(third.unexpectedExit)
        try fixture.store.finishLaunch(launchID: third.currentRecord.launchID)
    }

    func testStartingUnexpectedExitRequestsRecoveryStartup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try fixture.store.beginLaunch(
            metadata: metadata(build: "697"),
            now: referenceDate,
            processIdentifier: 11_001,
            processIsRunning: { _ in false }
        )
        let recovery = try fixture.store.beginLaunch(
            metadata: metadata(build: "698"),
            now: referenceDate.addingTimeInterval(10),
            processIdentifier: 11_002,
            processIsRunning: { _ in false }
        )
        let incident = try XCTUnwrap(recovery.unexpectedExit)

        XCTAssertEqual(incident.phase, .starting)
        XCTAssertTrue(incident.requiresRecoveryStartup)
        XCTAssertEqual(QuillCodeDesktopStartupMode(unexpectedExit: incident), .recovery)
        XCTAssertTrue(incident.userMessage.contains("background work is paused"))
        XCTAssertTrue(incident.userMessage.contains("saved workspace is available"))
        try fixture.store.finishLaunch(launchID: recovery.currentRecord.launchID)
    }

    func testAutomaticWorkspaceServicesWaitForFirstWindowBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        XCTAssertEqual(QuillCodeDesktopStartupMode(unexpectedExit: nil), .normal)
        let lifecycle = makeLifecycle(fixture: fixture, processIdentifier: 12_001)
        XCTAssertNil(lifecycle.startIfNeeded())
        let controller = makeController(
            fixture: fixture,
            lifecycle: lifecycle,
            startupMode: .normal
        )
        defer {
            controller.tasks.cancelAll()
            lifecycle.finishCurrentLaunch()
        }

        XCTAssertFalse(controller.automaticWorkspaceServicesArePaused)
        XCTAssertFalse(controller.automaticWorkspaceServicesStarted)
        XCTAssertFalse(controller.tasks.isRunning(.automationTicker))
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .starting)

        controller.completeStartupIfAllowed()

        XCTAssertTrue(controller.automaticWorkspaceServicesStarted)
        XCTAssertTrue(controller.tasks.isRunning(.automationTicker))
        XCTAssertTrue(controller.tasks.isRunning(.modelCatalogRefreshTicker))
        XCTAssertTrue(controller.tasks.isRunning(.trustedRouterCreditsRefreshTicker))
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .ready)

        controller.completeStartupIfAllowed()

        XCTAssertTrue(controller.automaticWorkspaceServicesStarted)
        XCTAssertTrue(controller.tasks.isRunning(.automationTicker))
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .ready)
    }

    func testRecoveryStartupKeepsServicesPausedUntilUserResumes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lifecycle = makeLifecycle(fixture: fixture, processIdentifier: 13_001)
        XCTAssertNil(lifecycle.startIfNeeded())
        let controller = makeController(
            fixture: fixture,
            lifecycle: lifecycle,
            startupMode: .recovery
        )
        defer {
            controller.tasks.cancelAll()
            lifecycle.finishCurrentLaunch()
        }

        controller.completeStartupIfAllowed()
        XCTAssertTrue(controller.automaticWorkspaceServicesArePaused)
        XCTAssertFalse(controller.automaticWorkspaceServicesStarted)
        XCTAssertFalse(controller.tasks.isRunning(.automationTicker))
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .starting)

        controller.resumeAutomaticWorkspaceServices()

        XCTAssertFalse(controller.automaticWorkspaceServicesArePaused)
        XCTAssertTrue(controller.automaticWorkspaceServicesStarted)
        XCTAssertTrue(controller.tasks.isRunning(.automationTicker))
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .ready)
    }

    func testProjectBookmarkRestoreWaitsForFirstWindowAndRunsOnceDuringRecovery() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let projectURL = fixture.root.appendingPathComponent("bookmarked-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let suiteName = "QuillCodeDesktopLaunchLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "bookmarks"
        defaults.set([projectURL.path: Data(projectURL.path.utf8)], forKey: storageKey)
        let bookmarkSpy = LaunchLifecycleProjectBookmarkServiceSpy()
        let projectAccessCoordinator = QuillCodeDesktopProjectAccessCoordinator(
            defaults: defaults,
            storageKey: storageKey,
            service: bookmarkSpy.service
        )
        let paths = QuillCodePaths(home: fixture.root.appendingPathComponent("bookmark-state"))
        try JSONProjectStore(fileURL: paths.projectsFile).save([
            ProjectRef(name: "Bookmarked", path: projectURL.path)
        ])
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let controller = QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            browserLiveDOMCapturer: nil,
            automationNotifier: LaunchLifecycleNoopNotifier(),
            projectAccessCoordinator: projectAccessCoordinator,
            updateController: QuillCodeDesktopUpdateController(configuration: nil, installResultURL: nil),
            installationLocationController: QuillCodeDesktopInstallationLocationController(configuration: nil),
            startupMode: .recovery,
            workspaceRoot: fixture.root
        )

        XCTAssertEqual(bookmarkSpy.resolvedPaths, [])

        controller.completeStartupIfAllowed()
        controller.completeStartupIfAllowed()

        XCTAssertEqual(bookmarkSpy.resolvedPaths, [projectURL.path])
        XCTAssertEqual(bookmarkSpy.startedPaths, [projectURL.path])
        XCTAssertTrue(controller.postWindowApplicationServicesStarted)
        XCTAssertFalse(controller.automaticWorkspaceServicesStarted)
    }

    func testRecoveryStartupCanRemainPausedAndStillBecomeReady() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lifecycle = makeLifecycle(fixture: fixture, processIdentifier: 14_001)
        XCTAssertNil(lifecycle.startIfNeeded())
        let controller = makeController(
            fixture: fixture,
            lifecycle: lifecycle,
            startupMode: .recovery
        )
        defer {
            controller.tasks.cancelAll()
            lifecycle.finishCurrentLaunch()
        }

        controller.continueWithAutomaticWorkspaceServicesPaused()

        XCTAssertTrue(controller.automaticWorkspaceServicesArePaused)
        XCTAssertFalse(controller.automaticWorkspaceServicesStarted)
        XCTAssertFalse(controller.tasks.isRunning(.automationTicker))
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .ready)
    }

    func testLivePriorProcessDoesNotProduceFalseCrashReport() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate,
            processIdentifier: 20_001,
            processIsRunning: { _ in false }
        )
        let second = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(5),
            processIdentifier: 20_002,
            processIsRunning: { $0 == 20_001 }
        )

        XCTAssertNil(second.unexpectedExit)
        try fixture.store.finishLaunch(launchID: second.currentRecord.launchID)

        _ = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(10),
            processIdentifier: 20_003,
            processIsRunning: { _ in false }
        )
        let sameProcess = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(15),
            processIdentifier: 20_003,
            processIsRunning: { _ in false }
        )
        XCTAssertNil(sameProcess.unexpectedExit)
        try fixture.store.finishLaunch(launchID: sameProcess.currentRecord.launchID)
    }

    func testOldOwnerCannotDeleteNewerLaunchMarker() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let first = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate,
            processIdentifier: 30_001,
            processIsRunning: { _ in false }
        )
        let second = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(5),
            processIdentifier: 30_002,
            processIsRunning: { _ in false }
        )

        try fixture.store.finishLaunch(launchID: first.currentRecord.launchID)
        XCTAssertEqual(try fixture.store.currentRecord()?.launchID, second.currentRecord.launchID)
        try fixture.store.finishLaunch(launchID: second.currentRecord.launchID)
        XCTAssertNil(try fixture.store.currentRecord())
    }

    func testStaleAndUnsafeRecordsAreNotReported() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(-QuillCodeDesktopUnexpectedExit.maximumIncidentAge - 1),
            processIdentifier: 40_001,
            processIsRunning: { _ in false }
        )
        let staleRelaunch = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate,
            processIdentifier: 40_002,
            processIsRunning: { _ in false }
        )
        XCTAssertNil(staleRelaunch.unexpectedExit)

        try fixture.store.finishLaunch(launchID: staleRelaunch.currentRecord.launchID)
        _ = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(
                QuillCodeDesktopUnexpectedExit.maximumFutureClockSkew + 1
            ),
            processIdentifier: 40_010,
            processIsRunning: { _ in false }
        )
        let futureRelaunch = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate,
            processIdentifier: 40_011,
            processIsRunning: { _ in false }
        )
        XCTAssertNil(futureRelaunch.unexpectedExit)
        try fixture.store.finishLaunch(launchID: futureRelaunch.currentRecord.launchID)

        let unsafeMetadata = QuillCodeDesktopBuildMetadata(
            version: "/Users/private/project",
            build: "697",
            commit: String(repeating: "a", count: 40),
            channel: "tester",
            architecture: "arm64",
            operatingSystem: "macOS 15.0"
        )
        _ = try fixture.store.beginLaunch(
            metadata: unsafeMetadata,
            now: referenceDate,
            processIdentifier: 40_003,
            processIsRunning: { _ in false }
        )
        let unsafeRelaunch = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate.addingTimeInterval(5),
            processIdentifier: 40_004,
            processIsRunning: { _ in false }
        )
        XCTAssertNil(unsafeRelaunch.unexpectedExit)
        try fixture.store.finishLaunch(launchID: unsafeRelaunch.currentRecord.launchID)

        let terminatingRecord = QuillCodeDesktopLaunchRecord(
            processIdentifier: 40_005,
            startedAt: referenceDate,
            phase: .terminating,
            metadata: metadata()
        )
        XCTAssertNil(
            QuillCodeDesktopUnexpectedExit(
                record: terminatingRecord,
                now: referenceDate.addingTimeInterval(5)
            )
        )
    }

    func testSentinelUsesPrivateDirectoryAndFilePermissions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let session = try fixture.store.beginLaunch(
            metadata: metadata(),
            now: referenceDate,
            processIdentifier: 50_001,
            processIsRunning: { _ in false }
        )
        let directoryPermissions = try permissions(
            at: fixture.fileURL.deletingLastPathComponent()
        )
        let filePermissions = try permissions(at: fixture.fileURL)
        let lockPermissions = try permissions(
            at: fixture.fileURL.deletingPathExtension().appendingPathExtension("lock")
        )

        XCTAssertEqual(directoryPermissions, 0o700)
        XCTAssertEqual(filePermissions, 0o600)
        XCTAssertEqual(lockPermissions, 0o600)
        try fixture.store.finishLaunch(launchID: session.currentRecord.launchID)
    }

    func testLifecycleControllerIsIdempotentAndClearsOnTerminationNotification() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let notificationCenter = NotificationCenter()
        let lifecycle = QuillCodeDesktopLaunchLifecycleController(
            store: fixture.store,
            metadata: metadata(),
            notificationCenter: notificationCenter,
            now: { self.referenceDate },
            processIdentifier: 60_001,
            processIsRunning: { _ in false }
        )

        XCTAssertNil(lifecycle.startIfNeeded())
        XCTAssertNil(lifecycle.startIfNeeded())
        lifecycle.markReady()
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .ready)

        notificationCenter.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertNil(try fixture.store.currentRecord())
    }

    func testDesktopControllerRetainsLifecycleForFirstWindowConsumption() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let previous = try fixture.store.beginLaunch(
            metadata: metadata(build: "697"),
            now: referenceDate,
            processIdentifier: 80_001,
            processIsRunning: { _ in false }
        )
        try fixture.store.markReady(launchID: previous.currentRecord.launchID)
        let lifecycle = QuillCodeDesktopLaunchLifecycleController(
            store: fixture.store,
            metadata: metadata(build: "698"),
            notificationCenter: NotificationCenter(),
            now: { self.referenceDate.addingTimeInterval(10) },
            processIdentifier: 80_002,
            processIsRunning: { _ in false }
        )
        _ = lifecycle.startIfNeeded()

        let paths = QuillCodePaths(home: fixture.root.appendingPathComponent("state"))
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let controller = QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            browserLiveDOMCapturer: nil,
            automationNotifier: LaunchLifecycleNoopNotifier(),
            updateController: QuillCodeDesktopUpdateController(configuration: nil, installResultURL: nil),
            installationLocationController: QuillCodeDesktopInstallationLocationController(
                configuration: nil
            ),
            launchLifecycleController: lifecycle,
            workspaceRoot: fixture.root
        )

        XCTAssertEqual(
            controller.launchLifecycleController?.takeUnexpectedExit()?.metadata.build,
            "697"
        )
        XCTAssertNil(controller.launchLifecycleController?.takeUnexpectedExit())
        controller.launchLifecycleController?.markReady()
        XCTAssertEqual(try fixture.store.currentRecord()?.phase, .ready)
        controller.startApplicationServices()
        XCTAssertNil(controller.launchLifecycleController?.takeUnexpectedExit())
        lifecycle.finishCurrentLaunch()
        XCTAssertNil(try fixture.store.currentRecord())
    }

    private func metadata(build: String = "697") -> QuillCodeDesktopBuildMetadata {
        QuillCodeDesktopBuildMetadata(
            version: "0.1.0",
            build: build,
            commit: String(repeating: "a", count: 40),
            channel: "tester",
            architecture: "arm64",
            operatingSystem: "macOS 15.0.0"
        )
    }

    private func makeLifecycle(
        fixture: Fixture,
        processIdentifier: Int32
    ) -> QuillCodeDesktopLaunchLifecycleController {
        QuillCodeDesktopLaunchLifecycleController(
            store: fixture.store,
            metadata: metadata(),
            notificationCenter: NotificationCenter(),
            now: { self.referenceDate },
            processIdentifier: processIdentifier,
            processIsRunning: { _ in false }
        )
    }

    private func makeController(
        fixture: Fixture,
        lifecycle: QuillCodeDesktopLaunchLifecycleController,
        startupMode: QuillCodeDesktopStartupMode
    ) -> QuillCodeDesktopController {
        let paths = QuillCodePaths(home: fixture.root.appendingPathComponent("state"))
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        return QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            browserLiveDOMCapturer: nil,
            automationNotifier: LaunchLifecycleNoopNotifier(),
            updateController: QuillCodeDesktopUpdateController(configuration: nil, installResultURL: nil),
            installationLocationController: QuillCodeDesktopInstallationLocationController(
                configuration: nil
            ),
            launchLifecycleController: lifecycle,
            startupMode: startupMode,
            workspaceRoot: fixture.root
        )
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}

@MainActor
private final class LaunchLifecycleProjectBookmarkServiceSpy {
    private(set) var resolvedPaths: [String] = []
    private(set) var startedPaths: [String] = []

    var service: QuillCodeDesktopProjectBookmarkService {
        QuillCodeDesktopProjectBookmarkService(
            makeBookmark: { Data($0.path.utf8) },
            resolveBookmark: { [weak self] data in
                let path = String(decoding: data, as: UTF8.self)
                self?.resolvedPaths.append(path)
                return QuillCodeDesktopResolvedProjectBookmark(
                    url: URL(fileURLWithPath: path),
                    isStale: false
                )
            },
            startAccessing: { [weak self] url in
                self?.startedPaths.append(url.path)
                return true
            },
            stopAccessing: { _ in }
        )
    }
}

private struct LaunchLifecycleNoopNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}

private struct Fixture {
    let root: URL
    let fileURL: URL
    let store: QuillCodeDesktopLaunchStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = root
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("active-launch.json")
        store = QuillCodeDesktopLaunchStore(fileURL: fileURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
