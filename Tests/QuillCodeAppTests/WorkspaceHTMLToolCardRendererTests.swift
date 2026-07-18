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
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"briefing.pdf"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote briefing.pdf and setup.md\n", artifacts: [
            document.path,
            markdown.path
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
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview-title">Setup"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-markdown-preview-meta">1 heading"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label">setup.md"#))
        XCTAssertTrue(html.contains("# Setup"))
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
