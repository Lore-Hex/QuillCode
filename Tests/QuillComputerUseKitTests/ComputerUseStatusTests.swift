import XCTest
import QuillComputerUseKit

final class ComputerUseStatusTests: XCTestCase {
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

    func testUnavailableStatusCarriesBackendReasonSeparatelyFromPermissions() {
        let status = ComputerUseStatus.unavailable("Computer Use backend is not running.")

        XCTAssertFalse(status.available)
        XCTAssertFalse(status.screenRecordingGranted)
        XCTAssertFalse(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Computer Use backend is not running.")
        XCTAssertEqual(status.unavailableReason, "Computer Use backend is not running.")
    }

    func testUnsupportedPlatformStatusIsUnavailableWithPlatformReason() {
        let status = ComputerUseStatus.unsupportedPlatform("Linux backend not configured.")

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Unsupported platform: Linux backend not configured.")
        XCTAssertEqual(status.unavailableReason, "Unsupported platform: Linux backend not configured.")
    }

    func testComputerUseStatusDecodesOlderPayloadWithoutUnavailableReason() throws {
        let status = try JSONDecoder().decode(
            ComputerUseStatus.self,
            from: Data("""
            {
              "available": false,
              "screenRecordingGranted": true,
              "accessibilityGranted": false,
              "message": "Needs Accessibility"
            }
            """.utf8)
        )

        XCTAssertFalse(status.available)
        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertFalse(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Needs Accessibility")
        XCTAssertNil(status.unavailableReason)
    }

    func testDefaultBackendFactoryReportsCurrentPlatformState() {
        let status = ComputerUseBackendFactory.platformDefault().backend().status

        XCTAssertEqual(status.available, status.screenRecordingGranted && status.accessibilityGranted)
        XCTAssertFalse(status.message.isEmpty)
    }
}
