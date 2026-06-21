import XCTest
import QuillComputerUseKit

final class ComputerUseBackendTests: XCTestCase {
    func testPermissionStatusLabelsReadyState() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: true
        )

        XCTAssertTrue(status.available)
        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertTrue(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Computer Use ready")
    }

    func testPermissionStatusLabelsMissingBothPermissions() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        )

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Needs Screen Recording + Accessibility")
    }

    func testPermissionStatusLabelsMissingScreenRecording() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: true
        )

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Needs Screen Recording")
    }

    func testPermissionStatusLabelsMissingAccessibility() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: false
        )

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Needs Accessibility")
    }

    func testStubBackendRecordsActions() async throws {
        let backend = StubComputerUseBackend()

        _ = try await backend.screenshot()
        try await backend.leftClick(x: 10, y: 20)
        try await backend.type("hello")
        try await backend.scroll(dx: 1, dy: -2)
        try await backend.moveCursor(x: 30, y: 40)
        try await backend.pressKey("return")

        let actions = await backend.actions
        XCTAssertEqual(actions, [
            "screenshot",
            "leftClick:10,20",
            "type:hello",
            "scroll:1,-2",
            "move:30,40",
            "key:return"
        ])
    }

    func testMacBackendReportsCurrentPermissionState() {
        let status = MacComputerUseBackend().status

        XCTAssertEqual(status.available, status.screenRecordingGranted && status.accessibilityGranted)
        XCTAssertFalse(status.message.isEmpty)
    }
}
