import XCTest
import QuillComputerUseKit

final class LinuxComputerUseDetectionTests: XCTestCase {
    func testLinuxComputerUseSessionDetectionPrefersWayland() {
        let session = LinuxComputerUseSession.detect(from: [
            "XDG_SESSION_TYPE": "wayland",
            "WAYLAND_DISPLAY": "wayland-0",
            "DISPLAY": ":0"
        ])

        XCTAssertEqual(session, .wayland)
    }

    func testLinuxComputerUseDetectorReportsMissingGraphicalSession() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [:],
            executableLookup: { _ in false }
        ).report()

        XCTAssertEqual(report.session, .none)
        XCTAssertEqual(report.availableHelpers, [])
        XCTAssertEqual(report.missingHelpers, [])
        XCTAssertFalse(report.status.available)
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use needs a graphical Wayland or X11 session."
        )
    }

    func testLinuxComputerUseDetectorReportsMissingWaylandHelpers() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: waylandEnvironment,
            executableLookup: { $0 == "grim" }
        ).report()

        XCTAssertEqual(report.session, .wayland)
        XCTAssertEqual(report.availableHelpers, ["grim"])
        XCTAssertEqual(report.missingHelpers, ["ydotool", "wtype"])
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use detected Wayland but needs helper tools: ydotool, wtype."
        )
    }

    func testLinuxComputerUseDetectorReportsCompleteWaylandHelpersAsReady() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: waylandEnvironment,
            executableLookup: { ["grim", "ydotool"].contains($0) }
        ).report()

        XCTAssertEqual(report.session, .wayland)
        XCTAssertEqual(report.availableHelpers, ["grim", "ydotool"])
        XCTAssertEqual(report.missingHelpers, [])
        XCTAssertTrue(report.status.available)
        XCTAssertTrue(report.status.screenRecordingGranted)
        XCTAssertTrue(report.status.accessibilityGranted)
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use ready (Wayland helpers detected)."
        )
    }

    func testLinuxComputerUseDetectorReportsX11Helpers() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: x11Environment,
            executableLookup: { $0 == "xdotool" }
        ).report()

        XCTAssertEqual(report.session, .x11)
        XCTAssertEqual(report.availableHelpers, ["xdotool"])
        XCTAssertEqual(report.missingHelpers, ["import or scrot"])
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use detected X11 but needs helper tools: import or scrot."
        )
    }

    func testLinuxComputerUseDetectorReportsCompleteX11HelpersAsReady() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: x11Environment,
            executableLookup: { ["scrot", "xdotool"].contains($0) }
        ).report()

        XCTAssertEqual(report.session, .x11)
        XCTAssertEqual(report.availableHelpers, ["scrot", "xdotool"])
        XCTAssertEqual(report.missingHelpers, [])
        XCTAssertTrue(report.status.available)
        XCTAssertTrue(report.status.screenRecordingGranted)
        XCTAssertTrue(report.status.accessibilityGranted)
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use ready (X11 helpers detected)."
        )
    }
}

private let waylandEnvironment = [
    "XDG_SESSION_TYPE": "wayland",
    "WAYLAND_DISPLAY": "wayland-0"
]

private let x11Environment = [
    "XDG_SESSION_TYPE": "x11",
    "DISPLAY": ":0"
]
