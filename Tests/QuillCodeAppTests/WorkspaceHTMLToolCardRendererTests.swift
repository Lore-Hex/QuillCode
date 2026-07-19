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
        XCTAssertTrue(html.contains(#"data-tool-name="host.shell.run""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-title">Run</strong>"#))
        XCTAssertTrue(html.contains(#"data-execution-context="local""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-execution-context""#))
        XCTAssertTrue(html.contains(#"data-execution-context-kind="local">Local"#))
        XCTAssertTrue(html.contains("host.shell.run"))
        XCTAssertTrue(html.contains(#"data-testid="message-copy""#))
        XCTAssertTrue(html.contains(#"data-testid="message-use-as-draft""#))
        XCTAssertTrue(html.contains(#"data-testid="message-retry""#))
        XCTAssertTrue(html.contains(#"data-command-id="retry-last-turn""#))
        XCTAssertFalse(html.contains(#"data-testid="message-feedback-up""#))
        XCTAssertFalse(html.contains(#"data-testid="message-feedback-down""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-copy""#))
        XCTAssertTrue(html.contains("Copy output"))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-output""#))
        XCTAssertTrue(html.contains("Show details"))
        XCTAssertTrue(html.contains(#"class="tool-details-summary hit-target-row""#))
        XCTAssertTrue(html.contains(#"aria-label="Show details""#))
        XCTAssertTrue(html.contains(#"class="tool-details-summary-chevron" aria-hidden="true">›</span>"#))
        XCTAssertTrue(html.contains(#"class="tool-details-summary-label">Show details</span>"#))
        XCTAssertTrue(html.contains(#"class="tool-details-summary-hint">Raw tool data</span>"#))
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
        XCTAssertTrue(html.contains(#"data-testid="tool-card-title">Run</strong>"#))
        XCTAssertTrue(html.contains(#"data-tool-name="host.shell.run""#))
        XCTAssertTrue(html.contains(#"aria-label="Run, ready to run, preview"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-details" open"#))
        XCTAssertTrue(html.contains("Show input"))
        XCTAssertTrue(html.contains("Copy input"))
        XCTAssertTrue(html.contains(#"class="tool-details-summary hit-target-row""#))
        XCTAssertTrue(html.contains(#"class="tool-details-summary-label">Show input</span>"#))
        XCTAssertFalse(html.contains(#"class="tool-details-summary-hint">Raw tool data</span>"#))
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
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-metadata""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-meta">Type: Text"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-meta">1 line"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-meta">Size: 12 bytes"#))
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
        XCTAssertFalse(html.contains(#"data-testid="tool-card-image-preview-sequence""#))
    }

    func testHTMLRendererIncludesLocalImageDimensionsWhenReadable() throws {
        let root = try makeTempDirectory()
        let screenshot = root.appendingPathComponent("screenshot.png")
        let logo = root.appendingPathComponent("logo.svg")
        let diagram = root.appendingPathComponent("diagram.bmp")
        let preview = root.appendingPathComponent("preview.webp")
        let scan = root.appendingPathComponent("scan.tiff")
        let icon = root.appendingPathComponent("app.ico")
        try pngHeader(width: 1024, height: 768).write(to: screenshot)
        try #"<svg viewBox="0 0 320 180" xmlns="http://www.w3.org/2000/svg"></svg>"#
            .write(to: logo, atomically: true, encoding: .utf8)
        try bmpHeader(width: 640, height: 360).write(to: diagram)
        try webpVP8XHeader(width: 512, height: 288).write(to: preview)
        try tiffHeader(width: 300, height: 200).write(to: scan)
        try icoHeader().write(to: icon)
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let result = ToolResult(
            ok: true,
            stdout: "captured screenshot\n",
            artifacts: [screenshot.path, logo.path, diagram.path, preview.path, scan.path, icon.path]
        )
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
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · SVG · 320 x 180 px"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · BMP · 640 x 360 px"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · WEBP · 512 x 288 px"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · TIFF · 300 x 200 px"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · ICO · 256 x 256 px"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-sequence">Image 1 of 6"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-sequence">Image 6 of 6"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-label">logo.svg"#))
    }

    func testHTMLRendererIncludesDocumentArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let document = reports.appendingPathComponent("briefing.pdf")
        let pdfBytes = pdfFixture(title: "Quarterly Plan", pageCount: 2)
        try pdfBytes.write(to: document, atomically: true, encoding: .isoLatin1)
        let byteCount = pdfBytes.data(using: .isoLatin1)?.count ?? 0
        let markdown = reports.appendingPathComponent("setup.md")
        try "# Setup\n\nRun the installer.\n".write(to: markdown, atomically: true, encoding: .utf8)
        let mdx = reports.appendingPathComponent("component.mdx")
        try """
        # Component Guide

        import { Callout } from "./Callout"

        <Callout tone="info">Ship the preview.</Callout>
        """.write(to: mdx, atomically: true, encoding: .utf8)
        let rtf = reports.appendingPathComponent("summary.rtf")
        let rtfText = #"{\rtf1\ansi{\info{\title Launch Notes}}{\fonttbl{\f0 Helvetica;}}\f0 Hello world.}"#
        try rtfText.write(to: rtf, atomically: true, encoding: .utf8)
        let htmlDocument = reports.appendingPathComponent("dashboard.html")
        let htmlText = """
        <!doctype html>
        <html><head><title>Quill Dashboard</title><style>body{}</style></head>
        <body><h1>Launch Readiness</h1><a href="/logs">Logs</a><script></script></body></html>
        """
        try htmlText.write(to: htmlDocument, atomically: true, encoding: .utf8)
        let diff = reports.appendingPathComponent("refactor.diff")
        let diffText = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,2 +1,3 @@
        -let title = "Old"
        +let title = "QuillCode"
        +let subtitle = "Fast"
        diff --git a/Tests/AppTests.swift b/Tests/AppTests.swift
        --- a/Tests/AppTests.swift
        +++ b/Tests/AppTests.swift
        @@ -4,2 +4,3 @@
        +XCTAssertEqual(title, "QuillCode")
        """
        try diffText.write(to: diff, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"briefing.pdf"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote briefing.pdf and setup.md\n", artifacts: [
            document.path,
            markdown.path,
            mdx.path,
            rtf.path,
            htmlDocument.path,
            diff.path
        ])
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
        XCTAssertTrue(html.contains(#"data-kind="markdown""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Markdown · MD"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">setup.md"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Markdown · MDX"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">component.mdx"#))
        XCTAssertTrue(html.contains(#"data-kind="document""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Document · RTF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">summary.rtf"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rtf-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rtf-preview-title">Launch Notes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rtf-preview-meta">Format: RTF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rtf-preview-meta">Encoding: ANSI"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Document · HTML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">dashboard.html"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-html-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-html-preview-title">Quill Dashboard"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-html-preview-meta">Format: HTML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-html-preview-meta">1 link"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-html-preview-meta">1 script"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · DIFF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">refactor.diff"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview-meta">Format: Unified diff"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview-meta">2 files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview-meta">2 hunks"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview-meta">+3 / -1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview-file-item">Sources/App.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-diff-preview-file-item">Tests/AppTests.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview-title">Setup"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview-title">Component Guide"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview-meta">1 heading"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">setup.md"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">component.mdx"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-meta">Type: MDX"#))
        XCTAssertTrue(html.contains("# Setup"))
        XCTAssertTrue(html.contains("&lt;Callout tone=&quot;info&quot;&gt;Ship the preview.&lt;/Callout&gt;"))
        XCTAssertTrue(html.contains(#"href="\#(document.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-preview-title">Quarterly Plan"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-preview-meta">Version: PDF 1.7"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-preview-meta">2 pages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-preview-meta">Size: \#(byteCount) bytes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-page-preview""#))
        XCTAssertTrue(html.contains(#"type="application/pdf""#))
        XCTAssertTrue(html.contains(#"data="\#(document.standardizedFileURL.absoluteString)#page=1""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pdf-page-preview-fallback""#))
    }

    func testHTMLRendererIncludesMediaArtifactPreviews() throws {
        let root = try makeTempDirectory()
        let mediaDirectory = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let audio = mediaDirectory.appendingPathComponent("voice-note.mp3")
        let video = mediaDirectory.appendingPathComponent("demo.mp4")
        let audioBytes = ID3MediaFixture.mp3(title: "Morning Notes", artist: "Quill")
        var videoBytes = Data([0x00, 0x00, 0x00, 0x18])
        videoBytes.append(Data("ftypmp42".utf8))
        try audioBytes.write(to: audio)
        try videoBytes.write(to: video)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"media"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote media\n", artifacts: [audio.path, video.path])
        let thread = ChatThread(
            title: "Media artifacts",
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

        XCTAssertTrue(html.contains(#"data-kind="audio""#))
        XCTAssertTrue(html.contains(#"data-kind="video""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Audio · MP3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Video · MP4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">voice-note.mp3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">demo.mp4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview-title">Morning Notes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview-meta">Format: MP3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview-meta">Artist: Quill"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview-meta">Size: \#(audioBytes.count) bytes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview-meta">Format: MP4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-media-preview-meta">Size: \#(videoBytes.count) bytes"#))
        XCTAssertTrue(html.contains(#"<audio class="artifact-media-player" data-testid="tool-card-media-player" controls preload="metadata" src="\#(audio.absoluteString)"></audio>"#))
        XCTAssertTrue(html.contains(#"<video class="artifact-media-player" data-testid="tool-card-media-player" controls preload="metadata" src="\#(video.absoluteString)"></video>"#))
    }

    func testHTMLRendererIncludesArchiveArtifactPreviews() throws {
        let root = try makeTempDirectory()
        let packagesDirectory = root.appendingPathComponent("packages", isDirectory: true)
        try FileManager.default.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
        let zip = packagesDirectory.appendingPathComponent("source.zip")
        let tar = packagesDirectory.appendingPathComponent("sources.tar")
        let gzip = packagesDirectory.appendingPathComponent("report.txt.gz")
        let tarGz = packagesDirectory.appendingPathComponent("logs.tar.gz")
        let xz = packagesDirectory.appendingPathComponent("report.txt.xz")
        let tarXZ = packagesDirectory.appendingPathComponent("logs.tar.xz")
        let bzip = packagesDirectory.appendingPathComponent("report.txt.bz2")
        let tarBzip = packagesDirectory.appendingPathComponent("logs.tar.bz2")
        let zstd = packagesDirectory.appendingPathComponent("report.txt.zst")
        let tarZstd = packagesDirectory.appendingPathComponent("logs.tar.zst")
        try OfficePackageFixture.zipPackage(fileNames: [
            "Sources/App.swift",
            "Sources/Model.swift",
            "Tests/AppTests.swift",
            "README.md"
        ]).write(to: zip)
        try TarArchiveFixture.tarArchive(entries: [
            ("Sources/App.swift", Data("print(\"hi\")".utf8)),
            ("Sources/Model.swift", Data("struct Model {}".utf8)),
            ("Tests/AppTests.swift", Data("import XCTest".utf8))
        ]).write(to: tar)
        try GzipArchiveFixture.gzipArchive(
            originalName: "report.txt",
            compressedBytes: Data("compressed".utf8),
            uncompressedByteCount: 2_048
        ).write(to: gzip)
        try GzipArchiveFixture.gzipArchive(
            originalName: "logs.tar",
            compressedBytes: Data("compressed tar".utf8),
            uncompressedByteCount: 8_192
        ).write(to: tarGz)
        try XZArchiveFixture.xzArchive().write(to: xz)
        try XZArchiveFixture.xzArchive().write(to: tarXZ)
        try Bzip2ArchiveFixture.bzip2Archive().write(to: bzip)
        try Bzip2ArchiveFixture.bzip2Archive().write(to: tarBzip)
        try ZstandardArchiveFixture.zstandardArchive().write(to: zstd)
        try ZstandardArchiveFixture.zstandardArchive().write(to: tarZstd)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"packages"}"#)
        let result = ToolResult(
            ok: true,
            stdout: "Wrote archives\n",
            artifacts: [
                zip.path,
                tar.path,
                gzip.path,
                tarGz.path,
                xz.path,
                tarXZ.path,
                bzip.path,
                tarBzip.path,
                zstd.path,
                tarZstd.path
            ]
        )
        let thread = ChatThread(
            title: "Archive artifacts",
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

        XCTAssertTrue(html.contains(#"data-kind="archive""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · ZIP"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · TAR"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · GZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · TAR.GZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · XZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · TAR.XZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · BZ2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · TAR.BZ2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · ZST"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Archive · TAR.ZST"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">source.zip"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">sources.tar"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">report.txt.gz"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">logs.tar.gz"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">report.txt.xz"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">logs.tar.xz"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">report.txt.bz2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">logs.tar.bz2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">report.txt.zst"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">logs.tar.zst"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: ZIP"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">4 entries"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">3 top-level items"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Entries: Sources/App.swift, Sources/Model.swift, Tests/AppTests.swift, +1 more"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-entries""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-entry-title">Contents"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-entry-item">Sources/App.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-entry-item">Sources/Model.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-entry-item">Tests/AppTests.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: TAR"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">3 entries"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">2 top-level items"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Entries: Sources/App.swift, Sources/Model.swift, Tests/AppTests.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: GZIP"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">1 entry"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Entries: report.txt"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Uncompressed: 2 KB"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: TAR.GZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Entries: logs.tar"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Uncompressed: 8 KB"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: XZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Entries: report.txt"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: TAR.XZ"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: BZIP2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: TAR.BZ2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: ZSTD"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-archive-preview-meta">Format: TAR.ZST"#))
        XCTAssertTrue(html.contains(#"href="\#(zip.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(tar.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(gzip.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(tarGz.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(xz.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(tarXZ.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(bzip.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(tarBzip.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(zstd.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"href="\#(tarZstd.standardizedFileURL.absoluteString)""#))
    }

    func testHTMLRendererIncludesOfficeArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let spreadsheet = reports.appendingPathComponent("budget.xlsx")
        let spreadsheetEntries = [
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/worksheets/sheet1.xml",
            "xl/worksheets/sheet2.xml",
            "xl/styles.xml"
        ]
        let spreadsheetBytes = OfficePackageFixture.zipPackage(fileNames: spreadsheetEntries)
        try spreadsheetBytes.write(to: spreadsheet)
        let byteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: spreadsheetBytes.count))
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"budget.xlsx"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote budget.xlsx\n", artifacts: [spreadsheet.path])
        let thread = ChatThread(
            title: "Spreadsheet artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview""#))
        XCTAssertTrue(html.contains(#"data-kind="spreadsheet""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Spreadsheet · XLSX"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">budget.xlsx"#))
        XCTAssertTrue(html.contains(#"href="\#(spreadsheet.standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-meta">Format: Office Open XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-meta">7 package entries"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-meta">2 sheets"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-meta">Size: \#(byteSize)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-contents""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-content-title">Contents"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-content-item">Sheet 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-office-preview-content-item">Sheet 2"#))
    }

    func testHTMLRendererIncludesDelimitedTableArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let csv = reports.appendingPathComponent("revenue.csv")
        try """
        Quarter,Revenue,Notes
        Q1,12000,Launch
        Q2,18500,"Expansion, EU"
        Q3,22400,Retention
        """.write(to: csv, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"revenue.csv"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote revenue.csv\n", artifacts: [csv.path])
        let thread = ChatThread(
            title: "CSV artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="spreadsheet""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Spreadsheet · CSV"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">revenue.csv"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-table-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-table-preview-meta">Format: CSV"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-table-preview-meta">4 rows, 3 columns"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-table-preview-header">Quarter"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-table-preview-header">Revenue"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-table-preview-cell">Expansion, EU"#))
    }

    func testHTMLRendererIncludesJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("build-report.json")
        let jsonText = """
        {
          "artifacts": ["app.log", "coverage.json"],
          "commit": "abc1234",
          "durationMs": 1284,
          "generatedAt": "2026-07-18T10:00:00Z",
          "platform": "macOS",
          "status": "passed",
          "summary": {"tests": 42, "failures": 0}
        }
        """
        try jsonText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"build-report.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote build-report.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "JSON artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">build-report.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-preview-meta">Root: Object"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-preview-meta">7 keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-preview-key-title">Top keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-preview-key-item">artifacts"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-preview-key-item">status"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">build-report.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-content">"#))
    }

    func testHTMLRendererIncludesNPMLockfileArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("package-lock.json")
        try """
        {
          "name": "quillcode-web",
          "version": "0.1.0",
          "lockfileVersion": 3,
          "packages": {
            "": {"name": "quillcode-web", "version": "0.1.0"},
            "node_modules/@playwright/test": {
              "version": "1.55.0",
              "resolved": "https://registry.npmjs.org/@playwright/test/-/test-1.55.0.tgz",
              "dev": true
            },
            "node_modules/lucide-react": {
              "version": "0.468.0",
              "resolved": "https://registry.npmjs.org/lucide-react/-/lucide-react-0.468.0.tgz"
            }
          },
          "dependencies": {
            "@playwright/test": {"version": "1.55.0"},
            "lucide-react": {"version": "0.468.0"}
          }
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"package-lock.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote package-lock.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "npm lockfile artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">package-lock.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview-meta">Format: npm lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview-meta">2 dependencies"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview-package-item">@playwright/test@1.55.0 · dev"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview-package-item">lucide-react@0.468.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-npm-lockfile-preview-host-item">registry.npmjs.org"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesDenoLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("deno.lock")
        try """
        {
          "version": "4",
          "specifiers": {
            "jsr:@std/assert@1": "jsr:@std/assert@1.0.0",
            "npm:zod@3": "npm:zod@3.22.4"
          },
          "jsr": {
            "@std/assert@1.0.0": {"integrity": "sha512-abc"}
          },
          "npm": {
            "zod@3.22.4": {"integrity": "sha512-jkl"}
          },
          "remote": {
            "https://deno.land/std@0.224.0/path/mod.ts": "sha256-111"
          }
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"deno.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote deno.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Deno lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · DENO-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">deno.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">Format: Deno lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">Lockfile: 4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">1 remote module"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">1 npm package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">1 jsr package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-meta">2 specifiers"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-package-item">jsr:@std/assert@1.0.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-package-item">npm:zod@3.22.4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-deno-lock-preview-host-item">deno.land"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">deno.lock"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesBunLockfileArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("bun.lock")
        try """
        {
          // JSONC comments and trailing commas are accepted.
          "lockfileVersion": 1,
          "workspaces": {
            "": {
              "dependencies": {
                "react": "catalog:",
                "zod": "^3.22.4",
              }
            }
          },
          "catalog": {
            "react": "^19.0.0"
          },
          "packages": {
            "react@19.0.0": ["react", "https://registry.npmjs.org/react/-/react-19.0.0.tgz"],
            "zod@3.22.4": ["zod", "https://registry.npmjs.org/zod/-/zod-3.22.4.tgz"]
          }
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"bun.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote bun.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Bun lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · BUN-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">bun.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-meta">Format: Bun text lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-meta">Lockfile: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-meta">1 workspace"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-meta">2 dependencies"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-meta">1 catalog entry"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-package-item">react"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-package-item">zod"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-bun-lockfile-preview-host-item">registry.npmjs.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">bun.lock"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesSwiftPMPackageResolvedArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("Package.resolved")
        try """
        {
          "pins": [
            {
              "identity": "swift-argument-parser",
              "kind": "remoteSourceControl",
              "location": "https://github.com/apple/swift-argument-parser.git",
              "state": {
                "revision": "26c13a1f7f961c8db7957e457602f3f9fdb69023",
                "version": "1.5.0"
              }
            },
            {
              "identity": "trusted-router-swift",
              "kind": "remoteSourceControl",
              "location": "https://github.com/Lore-Hex/trusted-router-swift.git",
              "state": {
                "branch": "main",
                "revision": "abcdef1234567890"
              }
            }
          ],
          "version": 2
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"Package.resolved"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote Package.resolved\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "SwiftPM resolved artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · SPM"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">Package.resolved"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-meta">Format: SwiftPM resolved packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-meta">2 pins"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-meta">1 versioned"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-meta">1 branch"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-pin-item">swift-argument-parser@1.5.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-pin-item">trusted-router-swift · main"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-swiftpm-resolved-preview-host-item">github.com"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">Package.resolved"#))
    }

    func testHTMLRendererIncludesCargoLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("Cargo.lock")
        try """
        version = 3

        [[package]]
        name = "anyhow"
        version = "1.0.86"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        checksum = "b3dd4a5f5f927c364bdd2f4d3d4f99aa971ec8e4"

        [[package]]
        name = "trusted-router"
        version = "0.2.0"
        source = "git+https://github.com/Lore-Hex/trusted-router-rs?rev=abc#abcdef1234567890"
        checksum = "d41d8cd98f00b204e9800998ecf8427e"
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"Cargo.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote Cargo.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Cargo lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · CARGO-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">Cargo.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-meta">Format: Cargo lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-meta">2 sources"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-package-item">anyhow@1.0.86"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-package-item">trusted-router@0.2.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-source-item">https://github.com/rust-lang/crates.io-index"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cargo-lock-preview-source-item">https://github.com/Lore-Hex/trusted-router-rs"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">Cargo.lock"#))
    }

    func testHTMLRendererIncludesYarnLockfileArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("yarn.lock")
        try """
        "@babel/code-frame@^7.0.0":
          version "7.26.2"
          resolved "https://registry.yarnpkg.com/@babel/code-frame/-/code-frame-7.26.2.tgz#abcdef"
          integrity sha512-codeframe

        left-pad@^1.3.0:
          version "1.3.0"
          resolved "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz"
          integrity sha512-leftpad
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"yarn.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote yarn.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Yarn lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · YARN-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">yarn.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-meta">Format: Yarn lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-meta">2 resolved"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-package-item">@babel/code-frame@7.26.2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-package-item">left-pad@1.3.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-host-item">registry.yarnpkg.com"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yarn-lockfile-preview-host-item">registry.npmjs.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">yarn.lock"#))
    }

    func testHTMLRendererIncludesPNPMLockfileArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("pnpm-lock.yaml")
        try """
        lockfileVersion: '9.0'

        importers:
          .:
            dependencies:
              '@playwright/test':
                specifier: ^1.55.0
                version: 1.55.0

        packages:
          /@playwright/test@1.55.0:
            resolution:
              integrity: sha512-playwright
              tarball: https://registry.npmjs.org/@playwright/test/-/test-1.55.0.tgz
          /lucide-react@0.468.0:
            resolution:
              integrity: sha512-lucide
              tarball: https://registry.yarnpkg.com/lucide-react/-/lucide-react-0.468.0.tgz
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"pnpm-lock.yaml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote pnpm-lock.yaml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "pnpm lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · PNPM-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">pnpm-lock.yaml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-meta">Format: pnpm lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-meta">Lockfile: 9.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-package-item">@playwright/test@1.55.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-package-item">lucide-react@0.468.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-importer-item">."#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-host-item">registry.npmjs.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pnpm-lockfile-preview-host-item">registry.yarnpkg.com"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-yaml-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">pnpm-lock.yaml"#))
    }

    func testHTMLRendererIncludesComposerLockfileArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("composer.lock")
        try """
        {
          "content-hash": "abcdef1234567890",
          "plugin-api-version": "2.6.0",
          "packages": [
            {
              "name": "guzzlehttp/guzzle",
              "version": "7.9.2",
              "dist": {
                "type": "zip",
                "url": "https://api.github.com/repos/guzzle/guzzle/zipball/abc"
              }
            }
          ],
          "packages-dev": [
            {
              "name": "phpunit/phpunit",
              "version": "11.4.3",
              "dist": {
                "type": "zip",
                "url": "https://repo.packagist.org/p2/phpunit/phpunit.json"
              }
            }
          ]
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"composer.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote composer.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Composer lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · COMPOSER-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">composer.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-meta">Format: Composer lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-meta">Plugin API: 2.6.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-meta">1 package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-meta">1 dev package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-package-item">guzzlehttp/guzzle@7.9.2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-package-item">phpunit/phpunit@11.4.3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-host-item">api.github.com"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-composer-lockfile-preview-host-item">repo.packagist.org"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">composer.lock"#))
    }

    func testHTMLRendererIncludesGoSumArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("go.sum")
        try """
        github.com/charmbracelet/lipgloss v1.1.0 h1:lipgloss
        github.com/charmbracelet/lipgloss v1.1.0/go.mod h1:lipglossmod
        golang.org/x/sys v0.34.0 h1:sys
        golang.org/x/sys v0.34.0/go.mod h1:sysmod
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"go.sum"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote go.sum\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Go checksum artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · GOSUM"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">go.sum"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-meta">Format: Go checksum database"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-meta">2 modules"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-meta">4 checksums"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-meta">2 go.mod checksums"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-module-item">github.com/charmbracelet/lipgloss"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-module-item">golang.org/x/sys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-host-item">github.com"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-sum-preview-host-item">golang.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">go.sum"#))
    }

    func testHTMLRendererIncludesPythonRequirementsArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("requirements.txt")
        try """
        --index-url https://pypi.org/simple
        requests==2.32.3 --hash=sha256:abc
        rich>=13.7,<14
        uvicorn @ https://files.pythonhosted.org/packages/uvicorn.whl
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"requirements.txt"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote requirements.txt\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Python requirements artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · REQUIREMENTS"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">requirements.txt"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-meta">Format: Python requirements"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-meta">3 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-meta">1 pinned"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-meta">1 ranged"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-meta">1 option"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-meta">1 hash"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-package-item">requests==2.32.3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-package-item">rich&gt;=13.7"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-package-item">uvicorn"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-host-item">pypi.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-python-requirements-preview-host-item">files.pythonhosted.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">requirements.txt"#))
    }

    func testHTMLRendererIncludesPoetryLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("poetry.lock")
        try """
        [[package]]
        name = "requests"
        version = "2.32.3"
        optional = false
        files = [{file = "requests-2.32.3.tar.gz", hash = "sha256:aaa"}]

        [[package]]
        name = "pytest"
        version = "8.3.4"
        category = "dev"
        source = { type = "legacy", url = "https://packages.example.com/simple" }
        files = [{file = "pytest-8.3.4.tar.gz", hash = "sha256:bbb"}]
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"poetry.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote poetry.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Poetry lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · POETRY-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">poetry.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-meta">Format: Poetry lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-meta">2 versioned"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-meta">1 dev package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-meta">1 source"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-meta">2 hashes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-package-item">pytest@8.3.4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-package-item">requests@2.32.3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-poetry-lock-preview-source-item">packages.example.com"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">poetry.lock"#))
    }

    func testHTMLRendererIncludesPipfileLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("Pipfile.lock")
        try """
        {
          "_meta": {
            "hash": { "sha256": "abc" },
            "pipfile-spec": 6,
            "sources": [
              { "name": "pypi", "url": "https://pypi.org/simple", "verify_ssl": true }
            ]
          },
          "default": {
            "requests": { "version": "==2.32.3", "hashes": ["sha256:aaa"] },
            "uvicorn": { "version": "==0.35.0" }
          },
          "develop": {
            "pytest": { "version": "==8.3.4", "hashes": ["sha256:bbb"] }
          }
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"Pipfile.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote Pipfile.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Pipfile lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · PIPFILE-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">Pipfile.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">Format: Pipfile lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">3 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">2 default"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">1 develop"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">3 pinned"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">1 source"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-meta">2 hashes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-package-item">pytest==8.3.4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-package-item">requests==2.32.3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-package-item">uvicorn==0.35.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pipfile-lock-preview-source-item">pypi.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">Pipfile.lock"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesUVLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("uv.lock")
        try """
        version = 1
        requires-python = ">=3.12"

        [[package]]
        name = "anyio"
        version = "4.7.0"
        source = { registry = "https://pypi.org/simple" }
        dependencies = [
            { name = "idna" },
        ]
        sdist = { url = "https://files.pythonhosted.org/packages/anyio.tar.gz", hash = "sha256:aaa" }

        [[package]]
        name = "idna"
        version = "3.10"
        source = { registry = "https://pypi.org/simple" }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"uv.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote uv.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "uv lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · UV-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">uv.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">Format: uv lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">Python: &gt;=3.12"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">2 versioned"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">1 dependency"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">2 sources"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-meta">1 hash"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-package-item">anyio@4.7.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-package-item">idna@3.10"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-source-item">pypi.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-uv-lock-preview-source-item">files.pythonhosted.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">uv.lock"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-toml-preview""#))
    }

    func testHTMLRendererIncludesGemfileLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("Gemfile.lock")
        try """
        GEM
          remote: https://rubygems.org/
          specs:
            actionpack (7.1.3)
              actionview (= 7.1.3)
            nokogiri (1.16.2-arm64-darwin)

        PLATFORMS
          arm64-darwin-23

        DEPENDENCIES
          rails (~> 7.1)

        BUNDLED WITH
           2.5.6
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"Gemfile.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote Gemfile.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "gemfile lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · GEMFILE-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">Gemfile.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-meta">Format: Bundler lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-meta">Bundler: 2.5.6"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-meta">2 gems"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-meta">1 dependency"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-meta">1 platform"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-meta">1 source"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-package-item">actionpack@7.1.3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-package-item">nokogiri@1.16.2-arm64-darwin"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-gemfile-lock-preview-source-item">rubygems.org"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">Gemfile.lock"#))
    }

    func testHTMLRendererIncludesPodfileLockArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("Podfile.lock")
        try """
        PODS:
          - Alamofire (5.8.1)
          - Firebase/Auth (10.24.0)

        DEPENDENCIES:
          - Alamofire (~> 5.8)

        SPEC REPOS:
          trunk:
            - Alamofire

        SPEC CHECKSUMS:
          Alamofire: 1111111111111111111111111111111111111111

        COCOAPODS: 1.15.2
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"Podfile.lock"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote Podfile.lock\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "podfile lock artifact",
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

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · PODFILE-LOCK"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">Podfile.lock"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-meta">Format: CocoaPods lockfile"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-meta">CocoaPods: 1.15.2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-meta">2 pods"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-meta">1 dependency"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-meta">1 source"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-meta">1 checksum"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-pod-item">Alamofire@5.8.1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-pod-item">Firebase/Auth@10.24.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-podfile-lock-preview-source-item">trunk"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">Podfile.lock"#))
    }

    func testHTMLRendererIncludesCycloneDXArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("bom.json")
        try """
        {
          "bomFormat": "CycloneDX",
          "specVersion": "1.6",
          "metadata": {
            "component": {
              "type": "application",
              "name": "QuillCode",
              "version": "0.1.0"
            }
          },
          "components": [
            {
              "type": "library",
              "name": "trusted-router-swift",
              "version": "1.2.3"
            },
            {
              "type": "library",
              "name": "Yams",
              "version": "5.1.3"
            }
          ],
          "services": [
            { "name": "TrustedRouter" }
          ],
          "dependencies": [
            { "ref": "pkg:generic/quillcode@0.1.0", "dependsOn": ["pkg:swift/lore-hex/trusted-router-swift@1.2.3"] }
          ],
          "vulnerabilities": [
            { "id": "CVE-0000-0001", "ratings": [{ "severity": "high" }] }
          ]
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"bom.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote bom.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "CycloneDX artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">bom.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">Format: CycloneDX"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">Spec: 1.6"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">Root: QuillCode@0.1.0 · application"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">2 components"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">1 service"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">1 dependency"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">Vulnerabilities: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-meta">High: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-component-title">Components"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cyclonedx-preview-component-item">trusted-router-swift@1.2.3 · library"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesSPDXArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("sbom.spdx.json")
        try """
        {
          "spdxVersion": "SPDX-2.3",
          "SPDXID": "SPDXRef-DOCUMENT",
          "name": "QuillCode SBOM",
          "documentNamespace": "https://lorehex.example/spdx/quillcode-2026",
          "creationInfo": {
            "creators": [
              "Tool: quill-code"
            ]
          },
          "packages": [
            {
              "name": "QuillCode",
              "SPDXID": "SPDXRef-Package-QuillCode",
              "versionInfo": "0.1.0",
              "licenseConcluded": "Apache-2.0"
            },
            {
              "name": "trusted-router-swift",
              "SPDXID": "SPDXRef-Package-TrustedRouterSwift",
              "versionInfo": "1.2.3",
              "licenseDeclared": "MIT"
            }
          ],
          "files": [
            { "fileName": "Sources/QuillCodeApp/App.swift", "SPDXID": "SPDXRef-File-App" }
          ],
          "relationships": [
            {
              "spdxElementId": "SPDXRef-DOCUMENT",
              "relationshipType": "DESCRIBES",
              "relatedSpdxElement": "SPDXRef-Package-QuillCode"
            }
          ],
          "hasExtractedLicensingInfos": [
            { "licenseId": "LicenseRef-Lore-Hex-Notice", "extractedText": "Do not render this text" }
          ]
        }
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"sbom.spdx.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote sbom.spdx.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "SPDX artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">sbom.spdx.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">Format: SPDX"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">Spec: SPDX-2.3"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">Document: QuillCode SBOM"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">1 file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">1 relationship"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-meta">1 extracted license"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-package-title">Packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-package-item">QuillCode@0.1.0 · SPDXRef-Package-QuillCode"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-license-title">Licenses"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spdx-preview-license-item">Apache-2.0"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesIstanbulArtifactPreview() throws {
        let root = try makeTempDirectory()
        let coverageDirectory = root.appendingPathComponent("coverage", isDirectory: true)
        try FileManager.default.createDirectory(at: coverageDirectory, withIntermediateDirectories: true)
        let coverage = coverageDirectory.appendingPathComponent("coverage-final.json")
        let coverageText = """
        {
          "/workspace/Sources/QuillCodeApp/Workspace.swift": {
            "statementMap": {
              "0": {"start": {"line": 10}, "end": {"line": 10}},
              "1": {"start": {"line": 11}, "end": {"line": 11}}
            },
            "s": {"0": 1, "1": 0},
            "fnMap": {"0": {"name": "render"}},
            "f": {"0": 1},
            "branchMap": {"0": {"type": "if"}},
            "b": {"0": [1, 0]}
          }
        }
        """
        try coverageText.write(to: coverage, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"coverage/coverage-final.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote coverage/coverage-final.json\n", artifacts: [coverage.path])
        let thread = ChatThread(
            title: "Istanbul artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">coverage-final.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-istanbul-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-istanbul-preview-meta">Format: Istanbul JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-istanbul-preview-meta">1 source file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-istanbul-preview-meta">Lines: 50% (1/2)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-istanbul-preview-file-title">Source files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-istanbul-preview-file-item">QuillCodeApp/Workspace.swift · 50%"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesCoveragePyArtifactPreview() throws {
        let root = try makeTempDirectory()
        let coverageDirectory = root.appendingPathComponent("coverage", isDirectory: true)
        try FileManager.default.createDirectory(at: coverageDirectory, withIntermediateDirectories: true)
        let coverage = coverageDirectory.appendingPathComponent("coverage.json")
        let coverageText = """
        {
          "meta": {"format": 2, "version": "7.6.1", "branch_coverage": true},
          "files": {
            "src/quillcode/app.py": {
              "summary": {
                "covered_lines": 3,
                "num_statements": 4,
                "covered_branches": 1,
                "num_branches": 2
              }
            },
            "tests/test_app.py": {
              "summary": {
                "covered_lines": 2,
                "num_statements": 2,
                "covered_branches": 0,
                "num_branches": 0
              }
            }
          },
          "totals": {
            "covered_lines": 5,
            "num_statements": 6,
            "covered_branches": 1,
            "num_branches": 2
          }
        }
        """
        try coverageText.write(to: coverage, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"coverage/coverage.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote coverage/coverage.json\n", artifacts: [coverage.path])
        let thread = ChatThread(
            title: "coverage.py artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">coverage.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview-meta">Format: coverage.py JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview-meta">Version: 7.6.1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview-meta">2 source files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview-meta">Lines: 83.3% (5/6)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview-file-title">Source files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-coverage-py-preview-file-item">quillcode/app.py · 75%"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesPytestJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("report.json")
        let reportText = """
        {
          "duration": 12.345,
          "exitcode": 1,
          "summary": {
            "total": 5,
            "passed": 2,
            "failed": 1,
            "error": 1,
            "skipped": 1
          },
          "tests": [
            {"nodeid": "tests/test_app.py::test_renders_prompt", "outcome": "passed"},
            {"nodeid": "tests/test_app.py::test_writes_file", "outcome": "failed"},
            {"nodeid": "tests/test_cli.py::test_bootstrap", "outcome": "error"}
          ]
        }
        """
        try reportText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/report.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/report.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "pytest artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">report.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-meta">Format: pytest JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-meta">Exit code: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-meta">Duration: 12.3s"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-meta">5 tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-meta">Failed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-failure-title">Failures"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pytest-json-preview-failure-item">tests/test_app.py::test_writes_file"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesJestJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("jest-results.json")
        let reportText = """
        {
          "success": false,
          "numTotalTests": 4,
          "numPassedTests": 2,
          "numFailedTests": 1,
          "numPendingTests": 1,
          "numTotalTestSuites": 2,
          "numFailedTestSuites": 1,
          "testResults": [
            {
              "name": "/repo/tests/app.test.ts",
              "perfStats": {"runtime": 1234},
              "assertionResults": [
                {"ancestorTitles": ["App"], "title": "renders prompt", "status": "passed"},
                {"ancestorTitles": ["App"], "title": "writes a file", "status": "failed"}
              ]
            }
          ]
        }
        """
        try reportText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/jest-results.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/jest-results.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Jest artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">jest-results.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-meta">Format: Jest JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-meta">Result: failed"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-meta">Runtime: 1.23s"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-meta">4 tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-meta">Failed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-failure-title">Failures"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jest-json-preview-failure-item">App &gt; writes a file"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesESLintJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("eslint-results.json")
        let reportText = """
        [
          {
            "filePath": "/repo/Sources/App.ts",
            "messages": [
              {"ruleId": "no-console", "severity": 1, "message": "Unexpected console statement."},
              {"ruleId": "@typescript-eslint/no-floating-promises", "severity": 2, "message": "Promise must be handled."}
            ],
            "errorCount": 1,
            "warningCount": 1,
            "fixableErrorCount": 0,
            "fixableWarningCount": 0
          }
        ]
        """
        try reportText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/eslint-results.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/eslint-results.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "ESLint artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">eslint-results.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-meta">Format: ESLint JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-meta">1 file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-meta">2 messages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-meta">Errors: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-meta">Warnings: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-file-title">Files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-file-item">repo/Sources/App.ts"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-rule-title">Rules"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-rule-item">no-console"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-eslint-json-preview-rule-item">@typescript-eslint/no-floating-promises"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesStylelintJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("stylelint-results.json")
        let reportText = """
        [
          {
            "source": "/repo/Sources/App.css",
            "deprecations": [{"text": "Deprecated rule"}],
            "invalidOptionWarnings": [{"text": "Invalid option"}],
            "parseErrors": [],
            "errored": true,
            "warnings": [
              {"rule": "color-no-invalid-hex", "severity": "error", "text": "Unexpected invalid hex color"},
              {"rule": "selector-class-pattern", "severity": "warning", "text": "Expected kebab-case"}
            ]
          }
        ]
        """
        try reportText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/stylelint-results.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/stylelint-results.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Stylelint artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">stylelint-results.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-meta">Format: Stylelint JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-meta">1 file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-meta">Warnings: 2"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-meta">Errors: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-meta">Deprecations: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-meta">Invalid options: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-source-title">Sources"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-source-item">repo/Sources/App.css"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-rule-title">Rules"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-rule-item">color-no-invalid-hex"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-stylelint-json-preview-rule-item">selector-class-pattern"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesRuboCopJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("rubocop-results.json")
        let reportText = """
        {
          "metadata": {"rubocop_version": "1.64.1"},
          "files": [
            {
              "path": "/repo/app/models/user.rb",
              "offenses": [
                {
                  "severity": "convention",
                  "message": "Prefer single-quoted strings.",
                  "cop_name": "Style/StringLiterals",
                  "correctable": true
                },
                {
                  "severity": "warning",
                  "message": "Method has too many lines.",
                  "cop_name": "Metrics/MethodLength",
                  "correctable": false
                }
              ]
            }
          ],
          "summary": {"offense_count": 2}
        }
        """
        try reportText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/rubocop-results.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/rubocop-results.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "RuboCop artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">rubocop-results.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-meta">Format: RuboCop JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-meta">1 file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-meta">2 offenses"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-meta">Warnings: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-meta">Convention: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-meta">Correctable: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-file-title">Files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-file-item">app/models/user.rb"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-cop-title">Cops"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-cop-item">Style/StringLiterals"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-rubocop-json-preview-cop-item">Metrics/MethodLength"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesGolangCILintJSONArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("golangci-lint-results.json")
        let reportText = """
        {
          "Issues": [
            {
              "FromLinter": "errcheck",
              "Text": "Error return value is not checked",
              "Severity": "error",
              "Pos": {
                "Filename": "/repo/cmd/server/main.go",
                "Line": 42,
                "Column": 5
              }
            },
            {
              "FromLinter": "govet",
              "Text": "printf call has possible formatting directive",
              "Severity": "warning",
              "Pos": {
                "Filename": "/repo/internal/http/handler.go",
                "Line": 17,
                "Column": 12
              }
            }
          ],
          "Report": {"Error": ""}
        }
        """
        try reportText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/golangci-lint-results.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/golangci-lint-results.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "golangci-lint artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">golangci-lint-results.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-meta">Format: golangci-lint JSON"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-meta">2 issues"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-meta">2 files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-meta">2 linters"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-meta">Errors: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-meta">Warnings: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-file-title">Files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-file-item">cmd/server/main.go"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-file-item">internal/http/handler.go"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-linter-title">Linters"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-linter-item">errcheck"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-golangci-lint-json-preview-linter-item">govet"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesTAPArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let report = reports.appendingPathComponent("test.tap")
        let tapText = """
        TAP version 13
        1..4
        ok 1 - loads app
        not ok 2 - writes file
        ok 3 - optional browser # SKIP no browser
        not ok 4 - planned support # TODO implement later
        Bail out! database unavailable
        """
        try tapText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/test.tap"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/test.tap\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "TAP artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · TAP"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">test.tap"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-meta">Format: TAP"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-meta">Plan: 1..4"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-meta">4 assertions"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-meta">Failed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-meta">Bail out: database unavailable"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-failure-title">Failures"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-tap-preview-failure-item">2 - writes file"#))
    }

    func testHTMLRendererIncludesHARArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let trace = reports.appendingPathComponent("network.har")
        let harText = """
        {
          "log": {
            "version": "1.2",
            "creator": {"name": "QuillCode", "version": "1.0"},
            "entries": [
              {
                "request": {"method": "GET", "url": "https://api.trustedrouter.com/v1/models"},
                "response": {"status": 200}
              },
              {
                "request": {"method": "POST", "url": "https://quillos.cloud/api/relay"},
                "response": {"status": 201}
              },
              {
                "request": {"method": "GET", "url": "https://api.trustedrouter.com/v1/chat/completions"},
                "response": {"status": 429}
              }
            ]
          }
        }
        """
        try harText.write(to: trace, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"network.har"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote network.har\n", artifacts: [trace.path])
        let thread = ChatThread(
            title: "HAR artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · HAR"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">network.har"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-meta">Format: HAR"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-meta">3 entries"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-meta">Methods: GET, POST"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-meta">Statuses: 2xx, 4xx"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-host-title">Hosts"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-host-item">api.trustedrouter.com"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-har-preview-host-item">quillos.cloud"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesLCOVArtifactPreview() throws {
        let root = try makeTempDirectory()
        let coverageDirectory = root.appendingPathComponent("coverage", isDirectory: true)
        try FileManager.default.createDirectory(at: coverageDirectory, withIntermediateDirectories: true)
        let coverage = coverageDirectory.appendingPathComponent("lcov.info")
        let lcovText = """
        SF:/workspace/Sources/QuillCodeApp/Workspace.swift
        DA:10,3
        DA:11,0
        DA:12,5
        LF:3
        LH:2
        BRF:2
        BRH:1
        FNF:1
        FNH:1
        end_of_record
        """
        try lcovText.write(to: coverage, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"coverage/lcov.info"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote coverage/lcov.info\n", artifacts: [coverage.path])
        let thread = ChatThread(
            title: "Coverage artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · LCOV"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">lcov.info"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-meta">Format: LCOV"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-meta">1 source file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-meta">Lines: 66.7% (2/3)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-meta">Branches: 50% (1/2)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-meta">Functions: 100% (1/1)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-source-title">Source files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-lcov-preview-source-item">QuillCodeApp/Workspace.swift · 66.7%"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesGoCoverageArtifactPreview() throws {
        let root = try makeTempDirectory()
        let coverageDirectory = root.appendingPathComponent("coverage", isDirectory: true)
        try FileManager.default.createDirectory(at: coverageDirectory, withIntermediateDirectories: true)
        let coverage = coverageDirectory.appendingPathComponent("cover.out")
        let coverageText = """
        mode: set
        github.com/lore/QuillCode/internal/runtime/runner.go:10.1,12.2 3 1
        github.com/lore/QuillCode/internal/runtime/runner.go:14.1,15.2 2 0
        """
        try coverageText.write(to: coverage, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"coverage/cover.out"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote coverage/cover.out\n", artifacts: [coverage.path])
        let thread = ChatThread(
            title: "Go coverage artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · GOCOVER"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">cover.out"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-meta">Format: Go coverage"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-meta">Mode: set"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-meta">1 source file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-meta">2 blocks"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-meta">Statements: 60% (3/5)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-source-title">Source files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-go-coverage-preview-source-item">runtime/runner.go · 60%"#))
    }

    func testHTMLRendererIncludesSARIFArtifactPreview() throws {
        let root = try makeTempDirectory()
        let reportsDirectory = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let report = reportsDirectory.appendingPathComponent("scan.sarif.json")
        let sarifText = """
        {
          "version": "2.1.0",
          "runs": [
            {
              "tool": {
                "driver": {
                  "name": "CodeQL",
                  "rules": [
                    {"id": "swift/hardcoded-credential"},
                    {"id": "swift/path-injection"}
                  ]
                }
              },
              "results": [
                {"ruleId": "swift/hardcoded-credential", "level": "error"},
                {"ruleId": "swift/path-injection", "level": "warning"},
                {"ruleId": "swift/style", "level": "note"}
              ]
            }
          ]
        }
        """
        try sarifText.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"reports/scan.sarif.json"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote reports/scan.sarif.json\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "SARIF artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · SARIF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">scan.sarif.json"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">Format: SARIF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">Version: 2.1.0"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">1 run"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">3 results"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">Errors: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">Warnings: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-meta">Notes: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-tool-title">Tools"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-tool-item">CodeQL"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-rule-title">Rules"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-rule-item">swift/hardcoded-credential"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-sarif-preview-rule-item">swift/path-injection"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-json-preview""#))
    }

    func testHTMLRendererIncludesJSONLinesArtifactPreview() throws {
        let root = try makeTempDirectory()
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let events = logs.appendingPathComponent("events.jsonl")
        let jsonLinesText = """
        {"event":"started","level":"info","runId":"run_123"}
        {"event":"tool.completed","level":"info","tool":"shell.run"}
        {"event":"finished","level":"info","durationMs":1284}
        """
        try jsonLinesText.write(to: events, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"events.jsonl"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote events.jsonl\n", artifacts: [events.path])
        let thread = ChatThread(
            title: "JSON Lines artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · JSONL"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">events.jsonl"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-lines-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-lines-preview-meta">Format: JSONL"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-lines-preview-meta">3 records"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-lines-preview-key-title">Observed keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-lines-preview-key-item">durationMs"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-json-lines-preview-key-item">tool"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">events.jsonl"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-content">"#))
    }

    func testHTMLRendererIncludesTOMLArtifactPreview() throws {
        let root = try makeTempDirectory()
        let quillDirectory = root.appendingPathComponent(".quillcode", isDirectory: true)
        try FileManager.default.createDirectory(at: quillDirectory, withIntermediateDirectories: true)
        let config = quillDirectory.appendingPathComponent("config.toml")
        let tomlText = """
        model = "trustedrouter/fast"
        approval_policy = "auto"
        disabled = false
        extra_roots = ["../shared"]

        [tools.shell]
        timeout_seconds = 120

        [mcp_servers.filesystem]
        command = "quill-mcp"
        args = ["--root", "."]
        """
        try tomlText.write(to: config, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"config.toml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote config.toml\n", artifacts: [config.path])
        let thread = ChatThread(
            title: "TOML artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · TOML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">config.toml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview-meta">Format: TOML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview-meta">6 top-level keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview-meta">4 tables"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview-key-title">Top-level keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview-key-item">approval_policy"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-toml-preview-key-item">tools"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">config.toml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-content">"#))
    }

    func testHTMLRendererIncludesINIArtifactPreview() throws {
        let root = try makeTempDirectory()
        let configDirectory = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let ini = configDirectory.appendingPathComponent("quillcode.ini")
        try """
        ; QuillCode mock configuration
        root = /tmp/quillcode
        model = trustedrouter/fast

        [trustedrouter]
        base_url = https://api.trustedrouter.com/v1
        timeout = 60

        [workspace]
        auto_save = true
        default_branch = main

        [tools]
        shell = enabled
        browser = enabled
        computer_use = review
        """.write(to: ini, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"quillcode.ini"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote quillcode.ini\n", artifacts: [ini.path])
        let thread = ChatThread(
            title: "INI artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · INI"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">quillcode.ini"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-meta">Format: INI"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-meta">3 sections"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-meta">9 keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-section-title">Sections"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-section-item">trustedrouter"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-section-item">workspace"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-ini-preview-section-item">tools"#))
    }

    func testHTMLRendererIncludesDotenvArtifactPreviewWithoutValues() throws {
        let root = try makeTempDirectory()
        let dotenv = root.appendingPathComponent(".env")
        try """
        TRUSTEDROUTER_API_KEY=sk-secret-value
        QUILLCODE_MODEL=trustedrouter/fast
        export QUILLCODE_DEBUG=true
        EMPTY_VALUE=
        """.write(to: dotenv, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":".env"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote .env\n", artifacts: [dotenv.path])
        let thread = ChatThread(
            title: "Dotenv artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · ENV"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">.env"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview-meta">Format: DOTENV"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview-meta">4 variables"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview-meta">1 exported"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview-key-title">Variable names"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview-key-item">TRUSTEDROUTER_API_KEY"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-dotenv-preview-key-item">QUILLCODE_MODEL"#))
        XCTAssertFalse(html.contains("sk-secret-value"))
    }

    func testHTMLRendererIncludesYAMLArtifactPreview() throws {
        let root = try makeTempDirectory()
        let workflows = root
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
        try FileManager.default.createDirectory(at: workflows, withIntermediateDirectories: true)
        let workflow = workflows.appendingPathComponent("ci.yml")
        let yamlText = """
        name: CI
        on: [push, pull_request]

        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - run: swift test
        """
        try yamlText.write(to: workflow, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"ci.yml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote ci.yml\n", artifacts: [workflow.path])
        let thread = ChatThread(
            title: "YAML artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · YML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">ci.yml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview-meta">Format: YML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview-meta">Root: Mapping"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview-meta">3 keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview-key-title">Top-level keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview-key-item">jobs"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-yaml-preview-key-item">name"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">ci.yml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-content">"#))
    }

    func testHTMLRendererIncludesPropertyListArtifactPreview() throws {
        let root = try makeTempDirectory()
        let plist = root.appendingPathComponent("Info.plist")
        let payload: [String: Any] = [
            "CFBundleIdentifier": "co.lorehex.QuillCode",
            "CFBundleName": "QuillCode",
            "CFBundleURLTypes": [
                [
                    "CFBundleURLName": "TrustedRouter",
                    "CFBundleURLSchemes": ["quillcode"]
                ]
            ],
            "LSMinimumSystemVersion": "14.0",
            "NSPrincipalClass": "NSApplication"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: plist)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"Info.plist"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote Info.plist\n", artifacts: [plist.path])
        let thread = ChatThread(
            title: "Property list artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · PLIST"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">Info.plist"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview-meta">Format: XML PLIST"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview-meta">Root: Dictionary"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview-meta">5 keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview-key-title">Top-level keys"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview-key-item">CFBundleIdentifier"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-plist-preview-key-item">NSPrincipalClass"#))
    }

    func testHTMLRendererIncludesXMLArtifactPreview() throws {
        let root = try makeTempDirectory()
        let manifest = root.appendingPathComponent("manifest.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <project xmlns="https://quillcode.dev/schema" name="QuillCode" version="1.0">
          <module name="QuillCodeApp">
            <target platform="macOS" />
            <target platform="Linux" />
          </module>
          <dependencies>
            <dependency id="TrustedRouterSwift" />
          </dependencies>
          <settings>
            <setting key="model" value="trustedrouter/fast" />
          </settings>
        </project>
        """.write(to: manifest, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"manifest.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote manifest.xml\n", artifacts: [manifest.path])
        let thread = ChatThread(
            title: "XML artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">manifest.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-meta">Format: XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-meta">Root: project"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-meta">8 elements"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-meta">8 attributes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-meta">1 namespace"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-child-title">Root children"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-child-item">dependencies"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-child-item">module"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xml-preview-child-item">settings"#))
    }

    func testHTMLRendererIncludesJUnitArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("TEST-QuillCode.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="QuillCodeAppTests" tests="3" failures="1" errors="1" skipped="1" time="1.25">
          <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testRendersArtifacts" />
          <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testStreamsOutput">
            <failure message="expected streamed output" />
          </testcase>
          <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testTimeout">
            <error message="timed out" />
          </testcase>
          <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testSkipped">
            <skipped />
          </testcase>
        </testsuite>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"TEST-QuillCode.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote TEST-QuillCode.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "JUnit artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">TEST-QuillCode.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">Format: JUnit XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">1 suite"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">3 tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">Failures: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">Errors: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">Skipped: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-meta">Duration: 1.25 s"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-suite-title">Suites"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-suite-item">QuillCodeAppTests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-failure-title">Failing tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-failure-item">QuillCodeAppTests.WorkspaceTests.testStreamsOutput"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-junit-preview-failure-item">QuillCodeAppTests.WorkspaceTests.testTimeout"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesCheckstyleArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("checkstyle-result.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <checkstyle version="10.12.0">
          <file name="/repo/Sources/App.swift">
            <error line="12" column="5" severity="error" message="Use let" source="swiftlint:prefer_let" />
            <error line="24" column="1" severity="warning" message="Line length" source="swiftlint:line_length" />
          </file>
        </checkstyle>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"checkstyle-result.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote checkstyle-result.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Checkstyle artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">checkstyle-result.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-meta">Format: Checkstyle XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-meta">1 file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-meta">2 issues"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-meta">Errors: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-meta">Warnings: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-file-title">Files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-file-item">repo/Sources/App.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-source-title">Sources"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-source-item">swiftlint:prefer_let"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-checkstyle-preview-source-item">swiftlint:line_length"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesPMDArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("pmd-result.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <pmd version="7.0.0">
          <file name="/repo/src/main/java/App.java">
            <violation beginline="12" endline="12" rule="UnusedPrivateField" priority="3" />
            <violation beginline="22" endline="22" rule="SystemPrintln" priority="2" />
          </file>
        </pmd>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"pmd-result.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote pmd-result.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "PMD artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">pmd-result.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-meta">Format: PMD XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-meta">1 file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-meta">2 violations"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-meta">Priority 2: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-meta">Priority 3: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-file-title">Files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-file-item">main/java/App.java"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-rule-title">Rules"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-rule-item">UnusedPrivateField"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-pmd-preview-rule-item">SystemPrintln"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesSpotBugsArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("spotbugs-result.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <BugCollection version="4.8.6">
          <BugInstance type="NP_NULL_ON_SOME_PATH" priority="1" category="CORRECTNESS">
            <Class classname="com.example.service.UserService" />
          </BugInstance>
          <BugInstance type="DM_DEFAULT_ENCODING" priority="2" category="I18N">
            <Class classname="com.example.web.AdminController" />
          </BugInstance>
        </BugCollection>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"spotbugs-result.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote spotbugs-result.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "SpotBugs artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">spotbugs-result.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-meta">Format: SpotBugs XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-meta">2 bugs"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-meta">2 classes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-meta">Priority 1: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-meta">Priority 2: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-type-title">Types"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-type-item">NP_NULL_ON_SOME_PATH"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-type-item">DM_DEFAULT_ENCODING"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-category-title">Categories"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-category-item">CORRECTNESS"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-category-item">I18N"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-class-title">Classes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-class-item">example.service.UserService"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-spotbugs-preview-class-item">example.web.AdminController"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesTRXArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("results.trx")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <TestRun id="run-1" name="QuillCode .NET Tests" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
          <Results>
            <UnitTestResult testName="QuillCode.Tests.AppTests.RendersPrompt" outcome="Passed" duration="00:00:01.1000000" />
            <UnitTestResult testName="QuillCode.Tests.AppTests.WritesFile" outcome="Failed" duration="00:00:02.2500000" />
            <UnitTestResult testName="QuillCode.Tests.CliTests.IsSkipped" outcome="NotExecuted" duration="00:00:00.0000000" />
          </Results>
        </TestRun>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"results.trx"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote results.trx\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "TRX artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · TRX"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">results.trx"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">Format: TRX"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">Run: QuillCode .NET Tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">3 tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">Passed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">Failed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">Not executed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-meta">Duration: 3.35 s"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-failure-title">Failing tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-trx-preview-failure-item">QuillCode.Tests.AppTests.WritesFile"#))
    }

    func testHTMLRendererIncludesXUnitArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("xunit-results.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <assemblies>
          <assembly name="/workspace/bin/Debug/net8.0/QuillCode.Tests.dll" total="3" passed="1" failed="1" skipped="1" time="3.50">
            <collection name="QuillCode app tests">
              <test name="QuillCode.Tests.AppTests.RendersPrompt" result="Pass" time="1.25" />
              <test name="QuillCode.Tests.AppTests.WritesFile" result="Fail" time="2.00" />
              <test name="QuillCode.Tests.CliTests.IsSkipped" result="Skip" time="0.25" />
            </collection>
          </assembly>
        </assemblies>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"xunit-results.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote xunit-results.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "xUnit artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">xunit-results.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">Format: xUnit XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">1 assembly"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">1 collection"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">3 tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">Passed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">Failed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">Skipped: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-meta">Duration: 3.5 s"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-assembly-title">Assemblies"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-assembly-item">QuillCode.Tests.dll"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-failure-title">Failing tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-xunit-preview-failure-item">QuillCode.Tests.AppTests.WritesFile"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesNUnitArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("TestResult.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <test-run id="2" name="QuillCode NUnit Tests" total="3" passed="1" failed="1" inconclusive="0" skipped="1" duration="3.50">
          <test-suite type="Assembly" name="QuillCode.Tests.dll">
            <test-case id="0-1001" fullname="QuillCode.Tests.AppTests.RendersPrompt" result="Passed" duration="1.25" />
            <test-case id="0-1002" fullname="QuillCode.Tests.AppTests.WritesFile" result="Failed" duration="2.00" />
            <test-case id="0-1003" fullname="QuillCode.Tests.CliTests.IsSkipped" result="Skipped" duration="0.25" />
          </test-suite>
        </test-run>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"TestResult.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote TestResult.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "NUnit artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">TestResult.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">Format: NUnit XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">Run: QuillCode NUnit Tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">3 tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">Passed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">Failed: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">Skipped: 1"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-meta">Duration: 3.5 s"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-failure-title">Failing tests"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-nunit-preview-failure-item">QuillCode.Tests.AppTests.WritesFile"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesCoberturaArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("coverage.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <coverage line-rate="0.75" branch-rate="0.5" lines-covered="3" lines-valid="4" branches-covered="1" branches-valid="2" version="1.9">
          <packages>
            <package name="QuillCodeApp">
              <classes>
                <class name="Workspace" filename="Sources/QuillCodeApp/Workspace.swift" />
                <class name="ToolCard" filename="Sources/QuillCodeApp/ToolCard.swift" />
              </classes>
            </package>
          </packages>
        </coverage>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"coverage.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote coverage.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Cobertura artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">coverage.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-meta">Format: Cobertura XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-meta">Version: 1.9"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-meta">1 package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-meta">2 classes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-meta">Lines: 75% (3/4)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-meta">Branches: 50% (1/2)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-package-title">Packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-package-item">QuillCodeApp"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-class-title">Classes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-class-item">Workspace · Sources/QuillCodeApp/Workspace.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-cobertura-preview-class-item">ToolCard · Sources/QuillCodeApp/ToolCard.swift"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesCloverArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("clover.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <coverage generated="1780000000" clover="4.5.0">
          <project name="QuillCode">
            <file name="Workspace.swift" path="Sources/QuillCodeApp/Workspace.swift" />
            <file name="ShellToolExecutor.swift" path="Sources/QuillCodeTools/ShellToolExecutor.swift" />
            <metrics packages="2" files="2" classes="3" methods="10" coveredmethods="8" statements="20" coveredstatements="15" conditionals="6" coveredconditionals="3" elements="36" coveredelements="26" />
          </project>
        </coverage>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"clover.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote clover.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "Clover artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">clover.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">Format: Clover XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">2 packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">2 files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">3 classes"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">Elements: 72.2% (26/36)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">Methods: 80% (8/10)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">Statements: 75% (15/20)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-meta">Conditionals: 50% (3/6)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-project-title">Projects"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-project-item">QuillCode"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-file-title">Files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-file-item">Sources/QuillCodeApp/Workspace.swift"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-clover-preview-file-item">Sources/QuillCodeTools/ShellToolExecutor.swift"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-cobertura-preview""#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
    }

    func testHTMLRendererIncludesJaCoCoArtifactPreview() throws {
        let root = try makeTempDirectory()
        let report = root.appendingPathComponent("jacoco.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <report name="QuillCode">
          <sessioninfo id="test-host" start="1780000000" dump="1780000100" />
          <package name="dev/quillcode/app">
            <class name="dev/quillcode/app/Workspace" sourcefilename="Workspace.kt" />
            <sourcefile name="Workspace.kt" />
          </package>
          <counter type="BRANCH" missed="2" covered="6" />
          <counter type="LINE" missed="3" covered="17" />
          <counter type="METHOD" missed="1" covered="9" />
          <counter type="CLASS" missed="0" covered="1" />
        </report>
        """.write(to: report, atomically: true, encoding: .utf8)
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"jacoco.xml"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote jacoco.xml\n", artifacts: [report.path])
        let thread = ChatThread(
            title: "JaCoCo artifact",
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

        XCTAssertTrue(html.contains(#"data-kind="data""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Data · XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">jacoco.xml"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">Format: JaCoCo XML"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">Report: QuillCode"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">1 package"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">1 source file"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">1 class"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">Lines: 85% (17/20)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">Branches: 75% (6/8)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">Methods: 90% (9/10)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-meta">Classes: 100% (1/1)"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-package-title">Packages"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-package-item">dev/quillcode/app"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-source-file-title">Source files"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-jacoco-preview-source-file-item">Workspace.kt"#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-xml-preview""#))
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
          "actions": [{"type": "click"}, {"type": "type"}],
          "frames": [{"screenshot": "checkout-start.png"}, {"screenshot": "checkout.png"}],
          "events": [{"name": "navigation"}, {"name": "form-fill"}, {"name": "capture"}],
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
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">2 actions"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">2 frames"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">3 events"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-meta">Captured: 2026-06-21T12:00:00Z"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-preview-image""#))
        XCTAssertTrue(html.contains(#"src="\#(appshots.appendingPathComponent("checkout.png").standardizedFileURL.absoluteString)""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-replay-group""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-replay-title">Actions"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-replay-title">Frames"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-appshot-replay-title">Events"#))
        XCTAssertTrue(html.contains("click"))
        XCTAssertTrue(html.contains("checkout.png"))
        XCTAssertTrue(html.contains("capture"))
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

    private func bmpHeader(width: Int32, height: Int32) -> Data {
        var bytes = Array("BM".utf8)
        bytes.append(contentsOf: littleEndianBytes(UInt32(54)))
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: littleEndianBytes(UInt32(54)))
        bytes.append(contentsOf: littleEndianBytes(UInt32(40)))
        bytes.append(contentsOf: littleEndianBytes(UInt32(bitPattern: width)))
        bytes.append(contentsOf: littleEndianBytes(UInt32(bitPattern: height)))
        bytes.append(contentsOf: [1, 0, 24, 0])
        bytes.append(contentsOf: Array(repeating: UInt8(0), count: 24))
        return Data(bytes)
    }

    private func webpVP8XHeader(width: UInt32, height: UInt32) -> Data {
        var bytes = Array("RIFF".utf8)
        bytes.append(contentsOf: littleEndianBytes(UInt32(30)))
        bytes.append(contentsOf: Array("WEBPVP8X".utf8))
        bytes.append(contentsOf: littleEndianBytes(UInt32(10)))
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: littleEndian24Bytes(width - 1))
        bytes.append(contentsOf: littleEndian24Bytes(height - 1))
        return Data(bytes)
    }

    private func tiffHeader(width: UInt32, height: UInt32) -> Data {
        var bytes = Array("II".utf8)
        bytes.append(contentsOf: [42, 0])
        bytes.append(contentsOf: littleEndianBytes(8))
        bytes.append(contentsOf: [2, 0])
        bytes.append(contentsOf: tiffEntry(tag: 256, value: width))
        bytes.append(contentsOf: tiffEntry(tag: 257, value: height))
        bytes.append(contentsOf: littleEndianBytes(0))
        return Data(bytes)
    }

    private func icoHeader() -> Data {
        var bytes: [UInt8] = [
            0, 0,
            1, 0,
            2, 0,
            16, 16, 0, 0,
            1, 0,
            32, 0
        ]
        bytes.append(contentsOf: littleEndianBytes(4))
        bytes.append(contentsOf: littleEndianBytes(38))
        bytes.append(contentsOf: [
            0, 0, 0, 0,
            1, 0,
            32, 0
        ])
        bytes.append(contentsOf: littleEndianBytes(4))
        bytes.append(contentsOf: littleEndianBytes(42))
        return Data(bytes)
    }

    private func tiffEntry(tag: UInt16, value: UInt32) -> [UInt8] {
        [
            UInt8(tag & 0x00FF),
            UInt8(tag >> 8),
            4, 0,
            1, 0, 0, 0
        ] + littleEndianBytes(value)
    }

    private func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    private func littleEndian24Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF)
        ]
    }

    private func pdfFixture(title: String, pageCount: Int) -> String {
        let pageObjects = (0..<pageCount)
            .map { index in
                "\(index + 3) 0 obj << /Type /Page /Parent 2 0 R >> endobj"
            }
            .joined(separator: "\n")
        let kids = (0..<pageCount)
            .map { "\($0 + 3) 0 R" }
            .joined(separator: " ")
        return """
        %PDF-1.7
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Count \(pageCount) /Kids [\(kids)] >> endobj
        \(pageObjects)
        9 0 obj << /Title (\(title)) >> endobj
        trailer << /Info 9 0 R >>
        %%EOF
        """
    }
}
