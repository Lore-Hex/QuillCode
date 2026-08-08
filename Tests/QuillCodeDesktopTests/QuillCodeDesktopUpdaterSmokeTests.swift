import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdaterSmokeTests: XCTestCase {
    func testRequestRequiresModeAndAbsoluteReportPath() throws {
        let request = try XCTUnwrap(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "/tmp/updater-smoke.json",
        ]))

        XCTAssertEqual(request.reportURL.path, "/tmp/updater-smoke.json")
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: ["Quill Cowork"]))
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "relative.json",
        ]))
    }

    func testReportEncodesReleaseProvenance() throws {
        let report = QuillCodeDesktopUpdaterSmokeReport(
            ok: true,
            sourceVersion: "0.1.0",
            sourceBuild: "642",
            targetVersion: "0.1.0",
            targetBuild: "643",
            targetCommit: String(repeating: "a", count: 40),
            message: "staged"
        )

        let decoded = try JSONDecoder().decode(
            QuillCodeDesktopUpdaterSmokeReport.self,
            from: JSONEncoder().encode(report)
        )
        XCTAssertEqual(decoded, report)
    }
}
