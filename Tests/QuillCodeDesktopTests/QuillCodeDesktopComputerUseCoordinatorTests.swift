import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
import QuillComputerUseKit
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopComputerUseCoordinatorTests: XCTestCase {
    func testInstallAndStatusProjectionDoNotSpawnForegroundLookups() async {
        let application = ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let backend = ForegroundRecordingComputerUseBackend(application: application)
        let coordinator = QuillCodeDesktopComputerUseCoordinator(backend: backend)
        let model = QuillCodeWorkspaceModel()

        coordinator.install(on: model)
        for _ in 0..<1_000 {
            coordinator.refreshStatus(on: model)
        }
        await Task.yield()
        XCTAssertEqual(backend.statusReadCount, 1_001)
        XCTAssertEqual(backend.lookupCount, 0)
        XCTAssertNil(model.root.topBar.computerUseForegroundApplication)

        await coordinator.refreshForegroundApplication(on: model)

        XCTAssertEqual(backend.lookupCount, 1)
        XCTAssertEqual(model.root.topBar.computerUseForegroundApplication, application)
    }

    func testSurfaceProjectionNeverPollsComputerUseBackend() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = QuillCodePaths(home: root.appendingPathComponent("state", isDirectory: true))
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let backend = ForegroundRecordingComputerUseBackend(
            application: ComputerUseApplication(name: "Terminal")
        )
        let computerUseCoordinator = QuillCodeDesktopComputerUseCoordinator(backend: backend)
        let controller = QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            computerUseCoordinator: computerUseCoordinator,
            browserLiveDOMCapturer: nil,
            automationNotifier: ComputerUseNoopNotifier(),
            updateController: QuillCodeDesktopUpdateController(configuration: nil, installResultURL: nil),
            installationLocationController: QuillCodeDesktopInstallationLocationController(
                configuration: nil
            ),
            workspaceRoot: root
        )
        defer { controller.tasks.cancelAll() }

        XCTAssertEqual(backend.statusReadCount, 1)
        for _ in 0..<1_000 {
            controller.refresh()
        }

        XCTAssertEqual(backend.statusReadCount, 1)
        XCTAssertEqual(backend.lookupCount, 0)
    }

    func testApplicationActivationObservationIsIdempotent() {
        let notificationCenter = NotificationCenter()
        let activationNotification = Notification.Name("test-application-activated")
        let coordinator = QuillCodeDesktopComputerUseCoordinator(
            applicationActivationNotificationCenter: notificationCenter,
            applicationActivationNotification: activationNotification
        )
        var activationCount = 0

        coordinator.startApplicationActivationObservation {
            activationCount += 1
        }
        coordinator.startApplicationActivationObservation {
            XCTFail("A repeated installation must not replace the live activation handler.")
        }
        notificationCenter.post(name: activationNotification, object: nil)

        XCTAssertEqual(activationCount, 1)
    }

    func testLateForegroundLookupCannotOverwriteNewerApplication() async {
        let backend = ControlledForegroundComputerUseBackend()
        let coordinator = QuillCodeDesktopComputerUseCoordinator(backend: backend)
        let model = QuillCodeWorkspaceModel()
        let oldApplication = ComputerUseApplication(
            name: "Old App",
            bundleIdentifier: "example.old"
        )
        let newApplication = ComputerUseApplication(
            name: "New App",
            bundleIdentifier: "example.new"
        )

        let oldLookup = Task { @MainActor in
            await coordinator.refreshForegroundApplication(on: model)
        }
        await backend.waitForRequestCount(1)
        let newLookup = Task { @MainActor in
            await coordinator.refreshForegroundApplication(on: model)
        }
        await backend.waitForRequestCount(2)

        await backend.resumeRequest(at: 1, with: newApplication)
        let newChanged = await newLookup.value
        await backend.resumeRequest(at: 0, with: oldApplication)
        let oldChanged = await oldLookup.value

        XCTAssertTrue(newChanged)
        XCTAssertFalse(oldChanged)
        XCTAssertEqual(model.root.topBar.computerUseForegroundApplication, newApplication)
    }

    func testCancelledForegroundLookupCannotMutateModel() async {
        let backend = ControlledForegroundComputerUseBackend()
        let coordinator = QuillCodeDesktopComputerUseCoordinator(backend: backend)
        let model = QuillCodeWorkspaceModel()
        let application = ComputerUseApplication(
            name: "Cancelled App",
            bundleIdentifier: "example.cancelled"
        )

        let lookup = Task { @MainActor in
            await coordinator.refreshForegroundApplication(on: model)
        }
        await backend.waitForRequestCount(1)
        lookup.cancel()
        await backend.resumeRequest(at: 0, with: application)
        let changed = await lookup.value

        XCTAssertFalse(changed)
        XCTAssertNil(model.root.topBar.computerUseForegroundApplication)
    }

    func testOpenSystemSettingsRequestsPermissionForExactDestination() {
        let backend = PermissionRecordingComputerUseBackend()
        let opener = ComputerUseSettingsRecordingOpener()
        let coordinator = QuillCodeDesktopComputerUseCoordinator(
            backend: backend,
            systemSettingsOpener: opener
        )

        XCTAssertTrue(coordinator.openSystemSettings(.screenRecording))
        XCTAssertEqual(backend.screenRecordingRequestCount, 1)
        XCTAssertEqual(backend.accessibilityRequestCount, 0)
        XCTAssertEqual(opener.screenRecordingOpenCount, 1)

        XCTAssertTrue(coordinator.openSystemSettings(.accessibility))
        XCTAssertEqual(backend.screenRecordingRequestCount, 1)
        XCTAssertEqual(backend.accessibilityRequestCount, 1)
        XCTAssertEqual(opener.accessibilityOpenCount, 1)
    }
}

private final class ForegroundRecordingComputerUseBackend: @unchecked Sendable,
    ComputerUseBackend,
    ComputerUseForegroundApplicationProviding
{
    private(set) var statusReadCount = 0
    private(set) var lookupCount = 0
    let application: ComputerUseApplication

    init(application: ComputerUseApplication) {
        self.application = application
    }

    var status: ComputerUseStatus {
        statusReadCount += 1
        return .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true)
    }

    func foregroundApplication() async -> ComputerUseApplication? {
        lookupCount += 1
        return application
    }

    func screenshot() async throws -> ComputerScreenshot {
        ComputerScreenshot(width: 1, height: 1, pngBase64: "")
    }

    func leftClick(x: Int, y: Int) async throws {}
    func type(_ text: String) async throws {}
    func scroll(dx: Int, dy: Int) async throws {}
    func moveCursor(x: Int, y: Int) async throws {}
    func pressKey(_ key: String) async throws {}
}

private struct ComputerUseNoopNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}

private final class PermissionRecordingComputerUseBackend: @unchecked Sendable,
    ComputerUseBackend,
    ComputerUsePermissionRequesting
{
    var screenRecordingRequestCount = 0
    var accessibilityRequestCount = 0

    var status: ComputerUseStatus {
        .permissionStatus(screenRecordingGranted: false, accessibilityGranted: false)
    }

    func requestScreenRecordingAccess() -> Bool {
        screenRecordingRequestCount += 1
        return false
    }

    func requestAccessibilityAccess() -> Bool {
        accessibilityRequestCount += 1
        return false
    }

    func screenshot() async throws -> ComputerScreenshot {
        ComputerScreenshot(width: 1, height: 1, pngBase64: "")
    }

    func leftClick(x: Int, y: Int) async throws {}
    func type(_ text: String) async throws {}
    func scroll(dx: Int, dy: Int) async throws {}
    func moveCursor(x: Int, y: Int) async throws {}
    func pressKey(_ key: String) async throws {}
}

private actor ControlledForegroundComputerUseBackend: ComputerUseBackend,
    ComputerUseForegroundApplicationProviding
{
    private var continuations: [CheckedContinuation<ComputerUseApplication?, Never>] = []

    nonisolated var status: ComputerUseStatus {
        .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true)
    }

    func foregroundApplication() async -> ComputerUseApplication? {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeRequest(at index: Int, with application: ComputerUseApplication?) {
        continuations[index].resume(returning: application)
    }

    func screenshot() async throws -> ComputerScreenshot {
        ComputerScreenshot(width: 1, height: 1, pngBase64: "")
    }

    func leftClick(x: Int, y: Int) async throws {}
    func type(_ text: String) async throws {}
    func scroll(dx: Int, dy: Int) async throws {}
    func moveCursor(x: Int, y: Int) async throws {}
    func pressKey(_ key: String) async throws {}
}

private final class ComputerUseSettingsRecordingOpener: QuillCodeDesktopComputerUseSettingsOpening {
    var screenRecordingOpenCount = 0
    var accessibilityOpenCount = 0

    func open(_ destination: MacSystemSettingsOpener.Destination) -> Bool {
        switch destination {
        case .screenRecording:
            screenRecordingOpenCount += 1
        case .accessibility:
            accessibilityOpenCount += 1
        }
        return true
    }
}
