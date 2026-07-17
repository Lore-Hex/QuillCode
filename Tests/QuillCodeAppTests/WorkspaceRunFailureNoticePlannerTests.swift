import XCTest
@testable import QuillCodeApp

final class WorkspaceRunFailureNoticePlannerTests: XCTestCase {
    private struct SecretBearingError: Error, CustomStringConvertible {
        var description: String { "auth failed for key sk-tr-v1-abcdef123456ZZ hitting the gateway" }
    }

    private struct NoisyMultilineError: Error, CustomStringConvertible {
        var description: String { "first line\nsecond line\n" + String(repeating: "x", count: 2_000) }
    }

    func testNoticeRedactsSecretsAndCarriesAReadablePrefix() {
        let summary = WorkspaceRunFailureNoticePlanner.noticeSummary(for: SecretBearingError())

        XCTAssertTrue(summary.hasPrefix("Run stopped after an error:"), summary)
        XCTAssertFalse(
            summary.contains("sk-tr-v1-abcdef123456ZZ"),
            "an API key must never persist in a durable failure notice"
        )
        XCTAssertTrue(summary.contains("auth failed"), "the readable cause is kept")
    }

    func testNoticeCollapsesToASingleBoundedLine() {
        let summary = WorkspaceRunFailureNoticePlanner.noticeSummary(for: NoisyMultilineError())

        XCTAssertFalse(summary.contains("\n"), "the notice is a single Activity-row line")
        XCTAssertLessThan(summary.count, 260, "the diagnostic is bounded, not the raw 2k-char error")
    }
}
