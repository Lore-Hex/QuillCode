import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceHTMLToolCardRendererTests: XCTestCase {
    func testHTMLRendererIncludesToolCardOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "QuillCode")
        model.selectProject(projectID)
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card""#))
        XCTAssertTrue(html.contains(#"data-status="done""#))
        XCTAssertTrue(html.contains(#"data-density="collapsed""#))
        XCTAssertTrue(html.contains(#"data-execution-context="local""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-execution-context""#))
        XCTAssertTrue(html.contains(#"data-execution-context-kind="local">Local"#))
        XCTAssertTrue(html.contains("host.shell.run"))
        XCTAssertTrue(html.contains(#"data-testid="message-copy""#))
        XCTAssertTrue(html.contains(#"data-testid="message-use-as-draft""#))
        XCTAssertTrue(html.contains(#"data-testid="message-retry""#))
        XCTAssertTrue(html.contains(#"data-command-id="retry-last-turn""#))
        XCTAssertTrue(html.contains(#"data-testid="message-feedback-up""#))
        XCTAssertTrue(html.contains(#"data-testid="message-feedback-down""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-copy""#))
        XCTAssertTrue(html.contains("Copy output"))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-output""#))
        XCTAssertTrue(html.contains("Show details"))
    }

    func testHTMLToolCardRendererIncludesApprovalActions() {
        let card = ToolCardState(
            id: "shell-review",
            title: ToolDefinition.shellRun.name,
            subtitle: "Ready to run · whoami",
            status: .review,
            inputJSON: ToolArguments.json(["cmd": "whoami"]),
            actions: [
                ToolCardActionSurface(
                    title: "Run",
                    kind: .approve,
                    requestID: "approval-html",
                    style: .primary
                ),
                ToolCardActionSurface(
                    title: "Edit",
                    kind: .edit,
                    requestID: "approval-html",
                    style: .secondary
                ),
                ToolCardActionSurface(
                    title: "Skip",
                    kind: .deny,
                    requestID: "approval-html",
                    style: .secondary
                )
            ],
            isExpanded: true
        )

        let html = WorkspaceHTMLToolCardRenderer.render(card, timelineItemID: "timeline-approval")

        XCTAssertTrue(html.contains(#"data-testid="tool-card-actions""#))
        XCTAssertTrue(html.contains(#"data-review-state="ready""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-status">Ready"#))
        XCTAssertTrue(html.contains(#"aria-label="host.shell.run, ready to run, expanded"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-action" data-action-kind="approve" data-action-style="primary" data-request-id="approval-html">Run"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-action" data-action-kind="edit" data-action-style="secondary" data-request-id="approval-html">Edit"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-action" data-action-kind="deny" data-action-style="secondary" data-request-id="approval-html">Skip"#))
        XCTAssertTrue(html.contains(#"data-timeline-id="timeline-approval""#))
    }

    func testHTMLRendererIncludesToolCardArtifacts() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifacts""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact-label""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact-detail""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-previews""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-content""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-details""#))
        XCTAssertTrue(html.contains(#"data-density="collapsed""#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-details" open"#))
        XCTAssertTrue(html.contains(#"data-kind="file""#))
        XCTAssertTrue(html.contains("hello.txt"))
        XCTAssertTrue(html.contains("hello world"))
    }

    func testHTMLRendererIncludesImageArtifactPreview() throws {
        let screenshotPath = "/tmp/quillcode-preview/screenshot.png"
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: #"{"width":1280,"height":720}"#, artifacts: [screenshotPath])
        let thread = ChatThread(
            title: "Screenshot",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.computer.screenshot queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.computer.screenshot completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-previews""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview""#))
        XCTAssertTrue(html.contains(#"src="file:///tmp/quillcode-preview/screenshot.png""#))
        XCTAssertTrue(html.contains(#"alt="screenshot.png""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · PNG"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-label">screenshot.png"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-detail">/tmp/quillcode-preview"#))
    }

    func testHTMLRendererIncludesDocumentArtifactPreview() throws {
        let documentPath = "/tmp/quillcode-preview/reports/briefing.pdf"
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"briefing.pdf"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote briefing.pdf\n", artifacts: [documentPath])
        let thread = ChatThread(
            title: "Document artifact",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.file.write queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.file.write completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-previews""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview""#))
        XCTAssertTrue(html.contains(#"data-kind="pdf""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">PDF · PDF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">briefing.pdf"#))
        XCTAssertTrue(html.contains(#"href="file:///tmp/quillcode-preview/reports/briefing.pdf""#))
    }

    func testHTMLRendererIncludesAppshotArtifactPreview() throws {
        let appshotPath = "/tmp/quillcode-preview/appshots/checkout.appshot.json"
        let call = ToolCall(name: "host.appshot.capture", argumentsJSON: #"{"name":"checkout"}"#)
        let result = ToolResult(ok: true, stdout: "Captured checkout.appshot.json\n", artifacts: [appshotPath])
        let thread = ChatThread(
            title: "Appshot artifact",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.appshot.capture queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.appshot.capture completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview""#))
        XCTAssertTrue(html.contains(#"data-kind="appshot""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Appshot · APPSHOT"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">checkout.appshot.json"#))
        XCTAssertTrue(html.contains(#"href="file:///tmp/quillcode-preview/appshots/checkout.appshot.json""#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-text-preview-label">checkout.appshot.json"#))
    }

    func testHTMLRendererKeepsToolCardsInTranscriptOrder() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())
        let userIndex = try XCTUnwrap(html.range(of: "run whoami")?.lowerBound)
        let toolIndex = try XCTUnwrap(html.range(of: "host.shell.run")?.lowerBound)
        let answerIndex = try XCTUnwrap(html.range(of: "You are `")?.lowerBound)

        XCTAssertLessThan(userIndex, toolIndex)
        XCTAssertLessThan(toolIndex, answerIndex)
    }
}
