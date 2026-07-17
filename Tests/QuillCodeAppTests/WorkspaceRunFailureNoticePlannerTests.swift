import XCTest
@testable import QuillCodeApp

final class WorkspaceRunFailureNoticePlannerTests: XCTestCase {
    private struct SecretBearingError: Error, CustomStringConvertible {
        var description: String { "auth failed for key sk-tr-v1-abcdef123456ZZ hitting the gateway" }
    }

    private struct NoisyMultilineError: Error, CustomStringConvertible {
        var description: String { "first line\nsecond line\n" + String(repeating: "x", count: 2_000) }
    }

    /// A plain error whose message we assemble at runtime, so a fake secret-shaped string never
    /// appears as a complete literal in the committed source (GitHub push protection blocks those).
    private struct MessageError: Error, CustomStringConvertible {
        let description: String
    }

    func testNoticeRedactsTransportSecretShapes() {
        // The shapes a real HTTP/provider run error tends to carry — assembled from split literals.
        let gh = "ghp_" + "0123456789abcdefABCDEF0123456789xyzQ"
        let bearer = "AbC123dEf456ghI789"
        let error = MessageError(
            description: "POST https://svc:hunter2pass@api.example/v1 401 "
                + "(Authorization: Bearer \(bearer), token=leaked-query-value, \(gh))"
        )

        let summary = WorkspaceRunFailureNoticePlanner.noticeSummary(for: error)

        for leaked in ["hunter2pass", bearer, "leaked-query-value", gh] {
            XCTAssertFalse(summary.contains(leaked), "a durable failure notice must not persist \(leaked): \(summary)")
        }
        XCTAssertTrue(summary.contains("[redacted]"), summary)
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
