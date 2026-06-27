import XCTest

final class ParityWorkspaceRuntimeReviewGateTests: QuillCodeParityTestCase {
    func testNativeReviewPaneDelegatesFileHunkAndLineRendering() throws {
        let paneText = try Self.appSourceText(named: "QuillCodeReviewPaneView.swift")
        let fileRowText = try Self.appSourceText(named: "QuillCodeReviewFileRowView.swift")
        let hunkText = try Self.appSourceText(named: "QuillCodeReviewHunkView.swift")
        let lineText = try Self.appSourceText(named: "QuillCodeReviewLineRowView.swift")
        let actionText = try Self.appSourceText(named: "QuillCodeReviewActionButton.swift")

        XCTAssertTrue(paneText.contains("struct QuillCodeReviewPaneView"), "Review pane shell should remain a focused root view.")
        XCTAssertTrue(paneText.contains("QuillCodeReviewFileRowView("), "Native review pane should compose focused file-row rendering.")
        XCTAssertTrue(fileRowText.contains("struct QuillCodeReviewFileRowView"), "Review file-row rendering should live in a focused file.")
        XCTAssertTrue(fileRowText.contains("QuillCodeReviewHunkView("), "Review file rows should delegate hunk rendering.")
        XCTAssertTrue(hunkText.contains("struct QuillCodeReviewHunkView"), "Review hunk rendering should live in a focused file.")
        XCTAssertTrue(hunkText.contains("QuillCodeReviewLineRowView("), "Review hunk rows should delegate line rendering.")
        XCTAssertTrue(lineText.contains("struct QuillCodeReviewLineRowView"), "Review line rendering should live in a focused file.")
        XCTAssertTrue(lineText.contains("markerColor"), "Line marker styling should live beside line-row rendering.")
        XCTAssertTrue(lineText.contains("lineBackground"), "Line background styling should live beside line-row rendering.")
        XCTAssertTrue(actionText.contains("struct QuillCodeReviewActionButton"), "Review action buttons should live in a focused file.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewFileRowView"), "Native review pane should not own file-row rendering.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewHunkView"), "Native review pane should not own hunk rendering.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewLineRowView"), "Native review pane should not own line rendering.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewActionButton"), "Native review pane should not own action-button rendering.")
    }

    func testWorkspaceSurfaceDelegatesRuntimeIssueBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceRuntimeIssueBuilder"), "Runtime issue classification should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func issue("), "Runtime error classification should be directly testable.")
        XCTAssertTrue(builderText.contains("from error: String"), "Runtime error classification should keep an explicit error input.")
        XCTAssertTrue(builderText.contains("static func rateLimitDiagnostics"), "Rate-limit diagnostics should be directly testable.")
        XCTAssertTrue(builderText.contains("static func providerOutageDiagnostics"), "Provider outage diagnostics should be directly testable.")
        XCTAssertTrue(builderText.contains("static func redactedDiagnosticError"), "Secret redaction should be directly testable.")
        XCTAssertTrue(surfaceText.contains("WorkspaceRuntimeIssueBuilder("), "WorkspaceSurface should delegate runtime issue construction.")
        XCTAssertFalse(surfaceText.contains("static func issue(from error:"), "WorkspaceSurface should not own runtime error classification.")
        XCTAssertFalse(surfaceText.contains("rateLimitDiagnostics(from error:"), "WorkspaceSurface should not own rate-limit diagnostics.")
        XCTAssertFalse(surfaceText.contains("providerOutageDiagnostics(from error:"), "WorkspaceSurface should not own provider outage diagnostics.")
        XCTAssertFalse(surfaceText.contains("redactedDiagnosticError"), "WorkspaceSurface should not own secret redaction.")
    }

    func testWorkspaceSurfaceDelegatesRuntimeAndExecutionContextContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let runtimeText = try Self.appSourceText(named: "QuillCodeRuntimeSurface.swift")
        let runtimeBuilderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")
        let executionBuilderText = try Self.appSourceText(named: "WorkspaceExecutionContextSurfaceBuilder.swift")

        XCTAssertTrue(runtimeText.contains("public enum RuntimeIssueSeverity"), "Runtime issue severity should live with the runtime surface contract.")
        XCTAssertTrue(runtimeText.contains("public enum ExecutionContextKind"), "Execution context kind should live with the runtime surface contract.")
        XCTAssertTrue(runtimeText.contains("public struct ExecutionContextSurface"), "Execution context surface should live beside runtime surface contracts.")
        XCTAssertTrue(runtimeText.contains("public struct RuntimeIssueSurface"), "Runtime issue surface should live beside runtime surface contracts.")
        XCTAssertTrue(runtimeText.contains("public struct RuntimeDiagnosticSurface"), "Runtime diagnostics should live beside runtime surface contracts.")
        XCTAssertTrue(runtimeText.contains("static func local(path:"), "Local execution-context fallback should be directly testable.")
        XCTAssertTrue(runtimeText.contains("static func project"), "Project execution-context mapping should be directly testable.")
        XCTAssertTrue(runtimeText.contains("func withDiagnostics"), "Runtime diagnostics copy semantics should be directly testable.")
        XCTAssertTrue(runtimeBuilderText.contains("RuntimeIssueSurface("), "Runtime issue builder should consume the shared runtime surface contract.")
        XCTAssertTrue(executionBuilderText.contains("ExecutionContextSurface"), "Execution-context builder should consume the shared runtime surface contract.")
        XCTAssertFalse(surfaceText.contains("public enum RuntimeIssueSeverity"), "WorkspaceSurface should not own runtime issue enum contracts.")
        XCTAssertFalse(surfaceText.contains("public enum ExecutionContextKind"), "WorkspaceSurface should not own execution context enum contracts.")
        XCTAssertFalse(surfaceText.contains("public struct ExecutionContextSurface"), "WorkspaceSurface should not own execution context surface contracts.")
        XCTAssertFalse(surfaceText.contains("public struct RuntimeIssueSurface"), "WorkspaceSurface should not own runtime issue surface contracts.")
        XCTAssertFalse(surfaceText.contains("public struct RuntimeDiagnosticSurface"), "WorkspaceSurface should not own runtime diagnostic surface contracts.")
    }

    func testWorkspaceViewDelegatesRuntimeIssueRecoveryPlanning() throws {
        let viewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let mainPaneText = try Self.appSourceText(named: "QuillCodeWorkspaceMainPaneView.swift")
        let plannerText = try Self.appSourceText(named: "QuillCodeRuntimeIssueRecoveryPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct RuntimeIssueRecoveryPlanner"), "Runtime issue recovery routing should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("enum RuntimeIssueRecoveryAction"), "Recovery actions should be explicit instead of view-local closures.")
        XCTAssertTrue(plannerText.contains("case \"Open Settings\", \"Add key\", \"Fix key\""), "Settings recovery labels should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"Retry\""), "Retry recovery routing should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"Switch model\""), "Model-switch recovery routing should be directly testable.")
        XCTAssertTrue(viewText.contains("QuillCodeWorkspaceMainPaneView"), "WorkspaceSwiftUIView should delegate center-pane layout and recovery wiring.")
        XCTAssertTrue(mainPaneText.contains("RuntimeIssueRecoveryPlanner(commands:"), "Workspace main pane should delegate runtime issue recovery planning.")
        XCTAssertFalse(viewText.contains("[\"Open Settings\", \"Add key\", \"Fix key\"]"), "WorkspaceSwiftUIView should not own settings recovery labels.")
        XCTAssertFalse(viewText.contains("actionLabel == \"Retry\""), "WorkspaceSwiftUIView should not own retry recovery labels.")
        XCTAssertFalse(viewText.contains("actionLabel == \"Switch model\""), "WorkspaceSwiftUIView should not own model-picker recovery labels.")
    }
}
