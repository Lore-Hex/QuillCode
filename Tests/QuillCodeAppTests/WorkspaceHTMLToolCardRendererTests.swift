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
        let copyIndex = try XCTUnwrap(html.range(of: #"data-testid="tool-card-copy""#)?.lowerBound)
        let detailsIndex = try XCTUnwrap(html.range(of: #"data-testid="tool-card-details""#)?.lowerBound)
        XCTAssertLessThan(copyIndex, detailsIndex)
    }

    func testHTMLToolCardRendererIncludesApprovalActions() throws {
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
            isExpanded: false,
            density: .peek
        )

        let html = WorkspaceHTMLToolCardRenderer.render(card, timelineItemID: "timeline-approval")

        XCTAssertTrue(html.contains(#"data-testid="tool-card-actions""#))
        XCTAssertTrue(html.contains(#"data-review-state="ready""#))
        XCTAssertTrue(html.contains(#"data-density="peek""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-status">Ready"#))
        XCTAssertTrue(html.contains(#"aria-label="host.shell.run, ready to run, preview"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-details" open"#))
        XCTAssertTrue(html.contains("Show input"))
        XCTAssertTrue(html.contains("Copy input"))
        let detailsIndex = try XCTUnwrap(html.range(of: #"data-testid="tool-card-details""#)?.lowerBound)
        let copyIndex = try XCTUnwrap(html.range(of: #"data-testid="tool-card-copy""#)?.lowerBound)
        let approveActionHTML = #"data-testid="tool-card-action" data-action-kind="approve""#
            + #" data-action-style="primary" data-request-id="approval-html">Run"#
        let editActionHTML = #"data-testid="tool-card-action" data-action-kind="edit""#
            + #" data-action-style="secondary" data-request-id="approval-html">Edit"#
        let denyActionHTML = #"data-testid="tool-card-action" data-action-kind="deny""#
            + #" data-action-style="secondary" data-request-id="approval-html">Skip"#
        XCTAssertLessThan(detailsIndex, copyIndex)
        XCTAssertTrue(html.contains(approveActionHTML))
        XCTAssertTrue(html.contains(editActionHTML))
        XCTAssertTrue(html.contains(denyActionHTML))
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
                ThreadEvent(
                    kind: .toolQueued,
                    summary: "host.computer.screenshot queued",
                    payloadJSON: try JSONHelpers.encodePretty(call)
                ),
                ThreadEvent(
                    kind: .toolCompleted,
                    summary: "host.computer.screenshot completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
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

    func testHTMLRendererIncludesLocalImageDimensionsWhenReadable() throws {
        let root = try makeTempDirectory()
        let screenshot = root.appendingPathComponent("screenshot.png")
        try pngHeader(width: 1024, height: 768).write(to: screenshot)
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: "captured screenshot\n", artifacts: [screenshot.path])
        let thread = ChatThread(
            title: "Screenshot",
            events: [
                ThreadEvent(
                    kind: .toolQueued,
                    summary: "host.computer.screenshot queued",
                    payloadJSON: try JSONHelpers.encodePretty(call)
                ),
                ThreadEvent(
                    kind: .toolCompleted,
                    summary: "host.computer.screenshot completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · PNG · 1024 x 768 px"#))
    }

    func testHTMLRendererIncludesDocumentArtifactPreview() throws {
        let documentPath = "/tmp/quillcode-preview/reports/briefing.pdf"
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"briefing.pdf"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote briefing.pdf\n", artifacts: [documentPath])
        let thread = ChatThread(
            title: "Document artifact",
            events: [
                ThreadEvent(
                    kind: .toolQueued,
                    summary: "host.file.write queued",
                    payloadJSON: try JSONHelpers.encodePretty(call)
                ),
                ThreadEvent(
                    kind: .toolCompleted,
                    summary: "host.file.write completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
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
        let root = try makeTempDirectory()
        let appshots = root.appendingPathComponent("appshots", isDirectory: true)
        try FileManager.default.createDirectory(at: appshots, withIntermediateDirectories: true)
        let appshot = appshots.appendingPathComponent("checkout.appshot.json")
        try """
        {
          "app": "QuillCode",
          "title": "Checkout flow",
          "summary": "Captured checkout page after payment details were entered.",
          "screenshotPath": "checkout.png",
          "viewport": {"width": 1440, "height": 1000},
          "windows": [{"title": "Checkout"}],
          "capturedAt": "2026-06-21T12:00:00Z"
        }
        """.write(to: appshot, atomically: true, encoding: .utf8)
        let call = ToolCall(name: "host.appshot.capture", argumentsJSON: #"{"name":"checkout"}"#)
        let result = ToolResult(ok: true, stdout: "Captured checkout.appshot.json\n", artifacts: [appshot.path])
        let thread = ChatThread(
            title: "Appshot artifact",
            events: [
                ThreadEvent(
                    kind: .toolQueued,
                    summary: "host.appshot.capture queued",
                    payloadJSON: try JSONHelpers.encodePretty(call)
                ),
                ThreadEvent(
                    kind: .toolCompleted,
                    summary: "host.appshot.capture completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
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
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-title">Checkout flow"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-summary">Captured checkout page after payment details were entered."#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">App: QuillCode"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">Viewport: 1440 x 1000"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">1 window"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">Captured: 2026-06-21T12:00:00Z"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-image""#))
        XCTAssertTrue(html.contains(#"src="\#(appshots.appendingPathComponent("checkout.png").standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(appshot.standardizedFileURL.absoluteString)""#))
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

    private func pngHeader(width: UInt32, height: UInt32) -> Data {
        var bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52
        ]
        bytes.append(contentsOf: [
            UInt8((width >> 24) & 0xFF),
            UInt8((width >> 16) & 0xFF),
            UInt8((width >> 8) & 0xFF),
            UInt8(width & 0xFF),
            UInt8((height >> 24) & 0xFF),
            UInt8((height >> 16) & 0xFF),
            UInt8((height >> 8) & 0xFF),
            UInt8(height & 0xFF),
            0x08, 0x02, 0x00, 0x00, 0x00
        ])
        return Data(bytes)
    }
}
