import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeRuntimeSurfaceTests: XCTestCase {
    func testLocalExecutionContextUsesProjectPathOrFallback() {
        XCTAssertEqual(
            ExecutionContextSurface.local(path: "/workspace"),
            ExecutionContextSurface(kind: .local, label: "Local", detail: "/workspace")
        )
        XCTAssertEqual(
            ExecutionContextSurface.local(path: ""),
            ExecutionContextSurface(kind: .local, label: "Local", detail: "No project")
        )
        XCTAssertEqual(
            ExecutionContextSurface.local(path: nil),
            ExecutionContextSurface(kind: .local, label: "Local", detail: "No project")
        )
    }

    func testProjectExecutionContextUsesConnectionKind() {
        let localProject = ProjectRef(name: "QuillCode", path: "/repo")
        XCTAssertEqual(ExecutionContextSurface.project(localProject), .local(path: "/repo"))

        let sshProject = ProjectRef(
            name: "Feather",
            path: "quill@feather.local:/Quill",
            connection: .ssh(path: "/Quill", host: "feather.local", user: "quill")
        )
        XCTAssertEqual(
            ExecutionContextSurface.project(sshProject),
            ExecutionContextSurface(kind: .sshRemote, label: "SSH Remote", detail: "feather.local")
        )

        let bareSSHProject = ProjectRef(
            name: "Bare SSH",
            path: "ssh://example/Quill",
            connection: ProjectConnection(kind: .ssh, path: "/Quill")
        )
        XCTAssertEqual(
            ExecutionContextSurface.project(bareSSHProject),
            ExecutionContextSurface(kind: .sshRemote, label: "SSH Remote", detail: "ssh")
        )
    }

    func testRuntimeIssueDecodesOlderPayloadWithoutDiagnostics() throws {
        let data = """
        {
          "severity": "warning",
          "title": "Old issue",
          "message": "Older renderer payload",
          "actionLabel": "Retry"
        }
        """.data(using: .utf8)!

        let issue = try JSONDecoder().decode(RuntimeIssueSurface.self, from: data)

        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Old issue")
        XCTAssertEqual(issue.message, "Older renderer payload")
        XCTAssertEqual(issue.actionLabel, "Retry")
        XCTAssertNil(issue.recovery)
        XCTAssertTrue(issue.diagnostics.isEmpty)
    }

    func testRuntimeIssueEncodesAndDecodesRecoveryTelemetry() throws {
        let issue = RuntimeIssueSurface(
            severity: .warning,
            title: "TrustedRouter sign-in needed",
            message: "Sign in first.",
            actionLabel: "Open Settings",
            recovery: RuntimeRecoveryTelemetry(
                route: .settings,
                reason: .trustedRouterSignInRequired,
                commandID: "settings"
            )
        )

        let decoded = try JSONDecoder().decode(
            RuntimeIssueSurface.self,
            from: try JSONEncoder().encode(issue)
        )

        XCTAssertEqual(decoded.recovery, issue.recovery)
        XCTAssertEqual(decoded.allDiagnostics, [
            RuntimeDiagnosticSurface(label: "Recovery route", value: "settings"),
            RuntimeDiagnosticSurface(label: "Recovery reason", value: "trustedrouter-sign-in-required"),
            RuntimeDiagnosticSurface(label: "Recovery command", value: "settings")
        ])
    }

    func testRuntimeIssueCopiesDiagnosticsWithoutMutatingOriginal() {
        let original = RuntimeIssueSurface(
            severity: .error,
            title: "Missing key",
            message: "Sign in first."
        )
        let diagnostic = RuntimeDiagnosticSurface(label: "Model", value: "trustedrouter/fast")

        let enriched = original.withDiagnostics([diagnostic])

        XCTAssertTrue(original.diagnostics.isEmpty)
        XCTAssertEqual(enriched.diagnostics, [diagnostic])
        XCTAssertEqual(enriched.allDiagnostics, [diagnostic])
    }
}
