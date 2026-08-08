import XCTest
import QuillCodeApp
import QuillComputerUseKit
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopComputerUseCoordinatorTests: XCTestCase {
    func testOpenSystemSettingsRequestsPermissionForExactDestination() {
        let backend = PermissionRecordingComputerUseBackend()
        let opener = ComputerUseSettingsRecordingOpener()
        let coordinator = QuillCodeDesktopComputerUseCoordinator(
            backend: backend,
            systemSettingsOpener: opener
        )
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(coordinator.openSystemSettings(.screenRecording, model: model))
        XCTAssertEqual(backend.screenRecordingRequestCount, 1)
        XCTAssertEqual(backend.accessibilityRequestCount, 0)
        XCTAssertEqual(opener.screenRecordingOpenCount, 1)

        XCTAssertTrue(coordinator.openSystemSettings(.accessibility, model: model))
        XCTAssertEqual(backend.screenRecordingRequestCount, 1)
        XCTAssertEqual(backend.accessibilityRequestCount, 1)
        XCTAssertEqual(opener.accessibilityOpenCount, 1)
    }
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
