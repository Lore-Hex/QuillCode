import Foundation
import XCTest
@testable import QuillCodeApp

final class QuillCodeToolCardSurfaceTests: XCTestCase {
    func testArtifactStateDerivesLinksAndImagePreviews() {
        let imageFile = ToolArtifactState(value: "/tmp/quillcode/screenshot.png")
        XCTAssertEqual(imageFile.kind, .file)
        XCTAssertEqual(imageFile.href, "file:///tmp/quillcode/screenshot.png")
        XCTAssertTrue(imageFile.isImagePreview)
        XCTAssertEqual(imageFile.previewURL, imageFile.href)
        XCTAssertEqual(imageFile.imagePreview?.typeLabel, "Image")
        XCTAssertEqual(imageFile.imagePreview?.extensionLabel, "PNG")
        XCTAssertEqual(imageFile.imagePreview?.detail, "/tmp/quillcode")

        let imageURL = ToolArtifactState(value: "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.kind, .url)
        XCTAssertEqual(imageURL.href, "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.label, "example.com/assets/mock.webp")
        XCTAssertTrue(imageURL.isImagePreview)
        XCTAssertEqual(imageURL.previewURL, imageURL.href)
        XCTAssertEqual(imageURL.imagePreview?.extensionLabel, "WEBP")
        XCTAssertEqual(imageURL.imagePreview?.detail, "example.com/assets/mock.webp")

        let inlineImage = ToolArtifactState(value: "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.kind, .url)
        XCTAssertEqual(inlineImage.label, "Inline image")
        XCTAssertEqual(inlineImage.detail, "Image artifact")
        XCTAssertTrue(inlineImage.isImagePreview)
        XCTAssertEqual(inlineImage.previewURL, "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.imagePreview?.extensionLabel, "PNG")
        XCTAssertEqual(inlineImage.imagePreview?.detail, "Image artifact")
        XCTAssertNil(inlineImage.textPreview)

        let nonImageData = ToolArtifactState(value: "data:text/plain;base64,SGVsbG8=")
        XCTAssertEqual(nonImageData.kind, .path)
        XCTAssertEqual(nonImageData.label, "data:text/plain;base64,SGVsbG8=")
        XCTAssertFalse(nonImageData.isImagePreview)
        XCTAssertNil(nonImageData.previewURL)
        XCTAssertNil(nonImageData.imagePreview)
        XCTAssertNil(nonImageData.href)
        XCTAssertNil(nonImageData.textPreview)
    }

    func testLocalImageArtifactReadsBoundedHeaderDimensions() throws {
        let directory = try makeQuillCodeTestDirectory()
        let pngFile = directory.appendingPathComponent("screenshot.png")
        let svgFile = directory.appendingPathComponent("logo.svg")
        let bmpFile = directory.appendingPathComponent("diagram.bmp")
        let webpFile = directory.appendingPathComponent("mock.webp")
        let tiffFile = directory.appendingPathComponent("scan.tiff")
        let icoFile = directory.appendingPathComponent("app.ico")
        try pngHeader(width: 1280, height: 720).write(to: pngFile)
        try """
        <svg width="320px" height="180px" viewBox="0 0 320 180" xmlns="http://www.w3.org/2000/svg">
          <rect width="320" height="180"/>
        </svg>
        """.write(to: svgFile, atomically: true, encoding: .utf8)
        try bmpHeader(width: 640, height: 360).write(to: bmpFile)
        try webpVP8XHeader(width: 512, height: 288).write(to: webpFile)
        try tiffHeader(width: 300, height: 200, byteOrder: .littleEndian).write(to: tiffFile)
        try icoHeader(sizes: [(16, 16), (0, 0)]).write(to: icoFile)

        let imageFile = ToolArtifactState(value: pngFile.path)
        let svgArtifact = ToolArtifactState(value: svgFile.path)
        let bmpArtifact = ToolArtifactState(value: bmpFile.path)
        let webpArtifact = ToolArtifactState(value: webpFile.path)
        let tiffArtifact = ToolArtifactState(value: tiffFile.path)
        let icoArtifact = ToolArtifactState(value: icoFile.path)

        XCTAssertEqual(imageFile.imagePreview?.dimensionsLabel, "1280 x 720 px")
        XCTAssertEqual(imageFile.imagePreview?.typeLine, "Image · PNG · 1280 x 720 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: gifHeader(width: 320, height: 240))?.label, "320 x 240 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: jpegHeader(width: 640, height: 480))?.label, "640 x 480 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: bmpHeader(width: 800, height: -600))?.label, "800 x 600 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: webpVP8XHeader(width: 512, height: 288))?.label, "512 x 288 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: webpVP8LHeader(width: 257, height: 129))?.label, "257 x 129 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: webpVP8Header(width: 320, height: 180))?.label, "320 x 180 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: icoHeader(sizes: [(16, 16), (0, 0)]))?.label, "256 x 256 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: tiffHeader(width: 300, height: 200, byteOrder: .littleEndian))?.label, "300 x 200 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: tiffHeader(width: 301, height: 201, byteOrder: .bigEndian))?.label, "301 x 201 px")
        XCTAssertTrue(svgArtifact.isImagePreview)
        XCTAssertNil(svgArtifact.documentPreview)
        XCTAssertEqual(svgArtifact.imagePreview?.extensionLabel, "SVG")
        XCTAssertEqual(svgArtifact.imagePreview?.dimensionsLabel, "320 x 180 px")
        XCTAssertEqual(svgArtifact.imagePreview?.typeLine, "Image · SVG · 320 x 180 px")
        XCTAssertEqual(bmpArtifact.imagePreview?.typeLine, "Image · BMP · 640 x 360 px")
        XCTAssertEqual(webpArtifact.imagePreview?.typeLine, "Image · WEBP · 512 x 288 px")
        XCTAssertEqual(tiffArtifact.imagePreview?.typeLine, "Image · TIFF · 300 x 200 px")
        XCTAssertEqual(icoArtifact.imagePreview?.typeLine, "Image · ICO · 256 x 256 px")
        XCTAssertEqual(
            ToolArtifactImageMetadataReader.dimensions(from: Data(#"<svg viewBox="0 0 1024 768"></svg>"#.utf8))?.label,
            "1024 x 768 px"
        )

        let urlImage = ToolArtifactState(value: "https://example.com/screenshot.png")
        XCTAssertNil(urlImage.imagePreview?.dimensionsLabel)
    }

    func testArtifactStateDerivesDocumentPreviews() {
        let pdfFile = ToolArtifactState(value: "/tmp/quillcode/reports/briefing.pdf")
        XCTAssertEqual(pdfFile.kind, .file)
        XCTAssertFalse(pdfFile.isImagePreview)
        XCTAssertTrue(pdfFile.isDocumentPreview)
        XCTAssertEqual(pdfFile.documentPreview?.kind, .pdf)
        XCTAssertEqual(pdfFile.documentPreview?.typeLabel, "PDF")
        XCTAssertEqual(pdfFile.documentPreview?.extensionLabel, "PDF")
        XCTAssertEqual(pdfFile.documentPreview?.detail, "/tmp/quillcode/reports")

        let spreadsheetURL = ToolArtifactState(value: "https://example.com/artifacts/budget.xlsx?download=1")
        XCTAssertEqual(spreadsheetURL.kind, .url)
        XCTAssertTrue(spreadsheetURL.isDocumentPreview)
        XCTAssertEqual(spreadsheetURL.documentPreview?.kind, .spreadsheet)
        XCTAssertEqual(spreadsheetURL.documentPreview?.typeLabel, "Spreadsheet")
        XCTAssertEqual(spreadsheetURL.documentPreview?.extensionLabel, "XLSX")
        XCTAssertEqual(spreadsheetURL.documentPreview?.detail, "example.com/artifacts/budget.xlsx")
        XCTAssertEqual(spreadsheetURL.href, "https://example.com/artifacts/budget.xlsx?download=1")

        let appshotBundle = ToolArtifactState(value: "/tmp/quillcode/appshots/checkout.appshot.json")
        XCTAssertEqual(appshotBundle.kind, .file)
        XCTAssertTrue(appshotBundle.isDocumentPreview)
        XCTAssertEqual(appshotBundle.documentPreview?.kind, .appshot)
        XCTAssertEqual(appshotBundle.documentPreview?.typeLabel, "Appshot")
        XCTAssertEqual(appshotBundle.documentPreview?.extensionLabel, "APPSHOT")
        XCTAssertEqual(appshotBundle.documentPreview?.detail, "/tmp/quillcode/appshots")

        let jsonReport = ToolArtifactState(value: "/tmp/quillcode/reports/build-report.json")
        XCTAssertTrue(jsonReport.isDocumentPreview)
        XCTAssertEqual(jsonReport.documentPreview?.kind, .data)
        XCTAssertEqual(jsonReport.documentPreview?.typeLabel, "Data")
        XCTAssertEqual(jsonReport.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(jsonReport.documentPreview?.detail, "/tmp/quillcode/reports")

        let audioFile = ToolArtifactState(value: "/tmp/quillcode/audio/voice-note.mp3")
        XCTAssertTrue(audioFile.isDocumentPreview)
        XCTAssertEqual(audioFile.documentPreview?.kind, .audio)
        XCTAssertEqual(audioFile.documentPreview?.typeLabel, "Audio")
        XCTAssertEqual(audioFile.documentPreview?.extensionLabel, "MP3")
        XCTAssertEqual(audioFile.documentPreview?.detail, "/tmp/quillcode/audio")

        let videoURL = ToolArtifactState(value: "https://example.com/artifacts/demo.mp4?download=1")
        XCTAssertTrue(videoURL.isDocumentPreview)
        XCTAssertEqual(videoURL.documentPreview?.kind, .video)
        XCTAssertEqual(videoURL.documentPreview?.typeLabel, "Video")
        XCTAssertEqual(videoURL.documentPreview?.extensionLabel, "MP4")
        XCTAssertEqual(videoURL.documentPreview?.detail, "example.com/artifacts/demo.mp4")

        let archiveFile = ToolArtifactState(value: "/tmp/quillcode/packages/source.zip")
        XCTAssertTrue(archiveFile.isDocumentPreview)
        XCTAssertEqual(archiveFile.documentPreview?.kind, .archive)
        XCTAssertEqual(archiveFile.documentPreview?.typeLabel, "Archive")
        XCTAssertEqual(archiveFile.documentPreview?.extensionLabel, "ZIP")
        XCTAssertEqual(archiveFile.documentPreview?.detail, "/tmp/quillcode/packages")

        let compoundArchiveURL = ToolArtifactState(value: "https://example.com/artifacts/logs.tar.gz?download=1")
        XCTAssertTrue(compoundArchiveURL.isDocumentPreview)
        XCTAssertEqual(compoundArchiveURL.documentPreview?.kind, .archive)
        XCTAssertEqual(compoundArchiveURL.documentPreview?.typeLabel, "Archive")
        XCTAssertEqual(compoundArchiveURL.documentPreview?.extensionLabel, "TAR.GZ")
        XCTAssertEqual(compoundArchiveURL.documentPreview?.detail, "example.com/artifacts/logs.tar.gz")

        let textFile = ToolArtifactState(value: "/tmp/quillcode/notes.md", textPreview: "# Notes\n")
        XCTAssertTrue(textFile.isDocumentPreview)
        XCTAssertEqual(textFile.documentPreview?.kind, .markdown)
        XCTAssertEqual(textFile.documentPreview?.typeLabel, "Markdown")
        XCTAssertEqual(textFile.documentPreview?.extensionLabel, "MD")
        XCTAssertTrue(textFile.hasTextPreview)

        let markdownURL = ToolArtifactState(value: "https://example.com/specs/setup.markdown?raw=1")
        XCTAssertTrue(markdownURL.isDocumentPreview)
        XCTAssertEqual(markdownURL.documentPreview?.kind, .markdown)
        XCTAssertEqual(markdownURL.documentPreview?.extensionLabel, "MARKDOWN")
        XCTAssertEqual(markdownURL.documentPreview?.detail, "example.com/specs/setup.markdown")

        let mdxFile = ToolArtifactState(value: "/tmp/quillcode/docs/component.mdx", textPreview: "# Component\n")
        XCTAssertTrue(mdxFile.isDocumentPreview)
        XCTAssertEqual(mdxFile.documentPreview?.kind, .markdown)
        XCTAssertEqual(mdxFile.documentPreview?.typeLabel, "Markdown")
        XCTAssertEqual(mdxFile.documentPreview?.extensionLabel, "MDX")
        XCTAssertTrue(mdxFile.hasTextPreview)
    }

    func testArtifactStateDerivesMarkdownPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let markdown = directory.appendingPathComponent("release-notes.md")
        let markdownText = """
        # Release Notes

        Intro.

        ## Added

        - Markdown artifact cards.

        ### Fixed ###

        Details.
        """
        try markdownText.write(to: markdown, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: markdown.path)
        let preview = try XCTUnwrap(artifact.markdownPreview)
        let byteCount = try XCTUnwrap(markdownText.data(using: .utf8)?.count)

        XCTAssertEqual(preview.title, "Release Notes")
        XCTAssertEqual(preview.headingCount, 3)
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "3 headings",
            "Size: \(byteCount) bytes"
        ])
    }

    func testArtifactStateDerivesMDXPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let mdx = directory.appendingPathComponent("component.mdx")
        let mdxText = """
        # Component Guide

        import { Callout } from "./Callout"

        <Callout tone="info">Ship the preview.</Callout>

        ## Props

        - `tone` controls the status color.
        """
        try mdxText.write(to: mdx, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(
            value: mdx.path,
            textPreview: ToolArtifactTextPreviewBuilder.textPreview(for: mdx.path)
        )
        let preview = try XCTUnwrap(artifact.markdownPreview)
        let sourcePreview = try XCTUnwrap(artifact.sourceTextPreview)
        let byteCount = try XCTUnwrap(mdxText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .markdown)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "MDX")
        XCTAssertEqual(preview.title, "Component Guide")
        XCTAssertEqual(preview.headingCount, 2)
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(sourcePreview.typeLabel, "MDX")
        XCTAssertEqual(sourcePreview.lineCountLabel, "9 lines")
    }

    func testArtifactStateDerivesPDFPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let pdfFile = directory.appendingPathComponent("briefing.pdf")
        let pdfBytes = pdfFixture(title: "Quarterly Plan", pageCount: 2)
        try pdfBytes.write(to: pdfFile, atomically: true, encoding: .isoLatin1)

        let artifact = ToolArtifactState(value: pdfFile.path)
        let preview = try XCTUnwrap(artifact.pdfPreview)
        let byteCount = pdfBytes.data(using: .isoLatin1)?.count ?? 0

        XCTAssertEqual(preview.title, "Quarterly Plan")
        XCTAssertEqual(preview.versionLabel, "PDF 1.7")
        XCTAssertEqual(preview.pageCount, 2)
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Version: PDF 1.7",
            "2 pages",
            "Size: \(byteCount) bytes"
        ])

        let remotePDF = ToolArtifactState(value: "https://example.com/briefing.pdf")
        XCTAssertNil(remotePDF.pdfPreview)
    }

    func testArtifactStateDerivesRTFPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let rtfFile = directory.appendingPathComponent("summary.rtf")
        let rtfText = #"{\rtf1\ansi{\info{\title Launch Notes}}{\fonttbl{\f0 Helvetica;}}\f0 Hello world.}"#
        try rtfText.write(to: rtfFile, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: rtfFile.path)
        let preview = try XCTUnwrap(artifact.rtfPreview)
        let byteCount = try XCTUnwrap(rtfText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .document)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "RTF")
        XCTAssertEqual(preview.title, "Launch Notes")
        XCTAssertEqual(preview.formatLabel, "RTF")
        XCTAssertEqual(preview.encodingLabel, "ANSI")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: RTF",
            "Encoding: ANSI",
            "Size: \(byteCount) bytes"
        ])

        let plainFile = directory.appendingPathComponent("plain.rtf")
        try "not rich text".write(to: plainFile, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: plainFile.path).rtfPreview)

        let remoteRTF = ToolArtifactState(value: "https://example.com/summary.rtf")
        XCTAssertNil(remoteRTF.rtfPreview)
    }

    func testArtifactStateDerivesHTMLPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let htmlFile = directory.appendingPathComponent("dashboard.html")
        let htmlText = """
        <!doctype html>
        <html>
          <head>
            <title>Quill Dashboard &amp; Metrics</title>
            <style>body { font-family: sans-serif; }</style>
          </head>
          <body>
            <h1>Launch Readiness</h1>
            <a href="/logs">Logs</a>
            <a href="/settings">Settings</a>
            <script>window.ready = true;</script>
          </body>
        </html>
        """
        try htmlText.write(to: htmlFile, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: htmlFile.path, textPreview: ToolArtifactTextPreviewBuilder.textPreview(for: htmlFile.path))
        let preview = try XCTUnwrap(artifact.htmlPreview)
        let byteCount = try XCTUnwrap(htmlText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .document)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "HTML")
        XCTAssertEqual(preview.title, "Quill Dashboard & Metrics")
        XCTAssertEqual(preview.heading, "Launch Readiness")
        XCTAssertEqual(preview.linkCount, 2)
        XCTAssertEqual(preview.scriptCount, 1)
        XCTAssertEqual(preview.styleCount, 1)
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: HTML",
            "2 links",
            "1 script",
            "1 style block",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNotNil(artifact.sourceTextPreview)

        let plainHTMLFile = directory.appendingPathComponent("plain.html")
        try "not html".write(to: plainHTMLFile, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: plainHTMLFile.path).htmlPreview)

        let remoteHTML = ToolArtifactState(value: "https://example.com/dashboard.html")
        XCTAssertNil(remoteHTML.htmlPreview)
    }

    func testArtifactStateDerivesDiffPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let diffFile = directory.appendingPathComponent("refactor.diff")
        let diffText = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,3 +1,4 @@
         import SwiftUI
        -let title = "Old"
        +let title = "QuillCode"
        +let subtitle = "Fast"
         struct AppView: View {}
        @@ -10,2 +11,2 @@
        -print("old")
        +print("new")
        diff --git a/Tests/AppTests.swift b/Tests/AppTests.swift
        index 3333333..4444444 100644
        --- a/Tests/AppTests.swift
        +++ b/Tests/AppTests.swift
        @@ -4,2 +4,3 @@
         func testTitle() {
        +    XCTAssertEqual(title, "QuillCode")
         }
        """
        try diffText.write(to: diffFile, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: diffFile.path, textPreview: ToolArtifactTextPreviewBuilder.textPreview(for: diffFile.path))
        let preview = try XCTUnwrap(artifact.diffPreview)
        let byteCount = try XCTUnwrap(diffText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "DIFF")
        XCTAssertEqual(preview.fileCount, 2)
        XCTAssertEqual(preview.hunkCount, 3)
        XCTAssertEqual(preview.additionCount, 4)
        XCTAssertEqual(preview.deletionCount, 2)
        XCTAssertEqual(preview.changedFileLabels, ["Sources/App.swift", "Tests/AppTests.swift"])
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: Unified diff",
            "2 files",
            "3 hunks",
            "+4 / -2",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNotNil(artifact.sourceTextPreview)

        let plainDiff = directory.appendingPathComponent("plain.diff")
        try "not a diff".write(to: plainDiff, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: plainDiff.path).diffPreview)

        let remoteDiff = ToolArtifactState(value: "https://example.com/refactor.diff")
        XCTAssertNil(remoteDiff.diffPreview)
    }

    func testArtifactStateDerivesJSONPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("build-report.json")
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

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.jsonPreview)
        let byteCount = try XCTUnwrap(jsonText.data(using: .utf8)?.count)

        XCTAssertEqual(preview.rootLabel, "Object")
        XCTAssertEqual(preview.keyCount, 7)
        XCTAssertNil(preview.itemCount)
        XCTAssertEqual(preview.keyPreviewLabels, [
            "artifacts",
            "commit",
            "durationMs",
            "generatedAt",
            "platform",
            "status"
        ])
        XCTAssertEqual(preview.keyPreviewLabel, "artifacts, commit, durationMs, generatedAt, platform, status, +1 more")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Root: Object",
            "7 keys",
            "Keys: artifacts, commit, durationMs, generatedAt, platform, status, +1 more",
            "Size: \(byteCount) bytes"
        ])

        let remoteJSON = ToolArtifactState(value: "https://example.com/build-report.json")
        XCTAssertNil(remoteJSON.jsonPreview)
    }

    func testArtifactStateDerivesJSONLinesPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let events = directory.appendingPathComponent("events.jsonl")
        let jsonLinesText = """
        {"event":"started","level":"info","runId":"run_123"}
        {"event":"tool.completed","level":"info","tool":"shell.run"}
        {"event":"finished","level":"info","durationMs":1284}
        """
        try jsonLinesText.write(to: events, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: events.path)
        let preview = try XCTUnwrap(artifact.jsonLinesPreview)
        let byteCount = try XCTUnwrap(jsonLinesText.data(using: .utf8)?.count)

        XCTAssertEqual(preview.formatLabel, "JSONL")
        XCTAssertEqual(preview.recordCountLabel, "3 records")
        XCTAssertEqual(preview.keyPreviewLabels, [
            "durationMs",
            "event",
            "level",
            "runId",
            "tool"
        ])
        XCTAssertEqual(preview.keyPreviewLabel, "durationMs, event, level, runId, tool")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: JSONL",
            "3 records",
            "Keys: durationMs, event, level, runId, tool",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)

        let remoteJSONLines = ToolArtifactState(value: "https://example.com/events.jsonl")
        XCTAssertNil(remoteJSONLines.jsonLinesPreview)
    }

    func testArtifactStateDerivesTOMLPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let config = directory.appendingPathComponent("config.toml")
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

        let artifact = ToolArtifactState(value: config.path)
        let preview = try XCTUnwrap(artifact.tomlPreview)
        let byteCount = try XCTUnwrap(tomlText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "TOML")
        XCTAssertEqual(preview.topLevelKeyCount, 6)
        XCTAssertEqual(preview.tableCount, 4)
        XCTAssertEqual(preview.arrayCount, 2)
        XCTAssertEqual(preview.scalarCount, 8)
        XCTAssertEqual(preview.keyPreviewLabels, [
            "approval_policy",
            "disabled",
            "extra_roots",
            "mcp_servers",
            "model",
            "tools"
        ])
        XCTAssertEqual(preview.keyPreviewLabel, "approval_policy, disabled, extra_roots, mcp_servers, model, tools")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: TOML",
            "6 top-level keys",
            "4 tables",
            "2 arrays",
            "8 values",
            "Keys: approval_policy, disabled, extra_roots, mcp_servers, model, tools",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)

        let remoteTOML = ToolArtifactState(value: "https://example.com/config.toml")
        XCTAssertNil(remoteTOML.tomlPreview)
    }

    func testArtifactStateDerivesINIPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let ini = directory.appendingPathComponent("quillcode.ini")
        let iniText = """
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
        """
        try iniText.write(to: ini, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: ini.path)
        let preview = try XCTUnwrap(artifact.iniPreview)
        let byteCount = try XCTUnwrap(iniText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "INI")
        XCTAssertEqual(preview.formatLabel, "INI")
        XCTAssertEqual(preview.sectionCount, 3)
        XCTAssertEqual(preview.keyCount, 9)
        XCTAssertEqual(preview.sectionPreviewLabels, ["trustedrouter", "workspace", "tools"])
        XCTAssertEqual(preview.sectionPreviewLabel, "trustedrouter, workspace, tools")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: INI",
            "3 sections",
            "9 keys",
            "Sections: trustedrouter, workspace, tools",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)

        let remoteINI = ToolArtifactState(value: "https://example.com/quillcode.ini")
        XCTAssertNil(remoteINI.iniPreview)
    }

    func testArtifactStateDerivesDotenvPreviewMetadataWithoutValues() throws {
        let directory = try makeQuillCodeTestDirectory()
        let dotenv = directory.appendingPathComponent(".env.local")
        let dotenvText = """
        # Local development settings
        TRUSTEDROUTER_API_KEY=sk-secret-value
        QUILLCODE_MODEL=trustedrouter/fast
        export QUILLCODE_DEBUG=true
        EMPTY_VALUE=
        INVALID-NAME=ignored
        """
        try dotenvText.write(to: dotenv, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: dotenv.path)
        let preview = try XCTUnwrap(artifact.dotenvPreview)
        let byteCount = try XCTUnwrap(dotenvText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "ENV")
        XCTAssertEqual(preview.variableCount, 4)
        XCTAssertEqual(preview.exportedVariableCount, 1)
        XCTAssertEqual(preview.keyPreviewLabels, [
            "TRUSTEDROUTER_API_KEY",
            "QUILLCODE_MODEL",
            "QUILLCODE_DEBUG",
            "EMPTY_VALUE"
        ])
        XCTAssertEqual(preview.keyPreviewLabel, "TRUSTEDROUTER_API_KEY, QUILLCODE_MODEL, QUILLCODE_DEBUG, EMPTY_VALUE")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: DOTENV",
            "4 variables",
            "1 exported",
            "Keys: TRUSTEDROUTER_API_KEY, QUILLCODE_MODEL, QUILLCODE_DEBUG, EMPTY_VALUE",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(preview.metadataLines.first { $0.contains("sk-secret-value") })
        XCTAssertNil(artifact.iniPreview)
        XCTAssertNil(artifact.textPreview)
        XCTAssertNil(artifact.sourceTextPreview)

        let remoteDotenv = ToolArtifactState(value: "https://example.com/.env")
        XCTAssertNil(remoteDotenv.dotenvPreview)
    }

    func testArtifactStateDerivesYAMLPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let workflow = directory.appendingPathComponent("ci.yml")
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

        let artifact = ToolArtifactState(value: workflow.path)
        let preview = try XCTUnwrap(artifact.yamlPreview)
        let byteCount = try XCTUnwrap(yamlText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "YML")
        XCTAssertEqual(preview.formatLabel, "YML")
        XCTAssertEqual(preview.rootLabel, "Mapping")
        XCTAssertEqual(preview.keyCount, 3)
        XCTAssertNil(preview.itemCount)
        XCTAssertEqual(preview.mappingCount, 5)
        XCTAssertEqual(preview.sequenceCount, 2)
        XCTAssertEqual(preview.scalarCount, 6)
        XCTAssertEqual(preview.keyPreviewLabels, ["jobs", "name", "on"])
        XCTAssertEqual(preview.keyPreviewLabel, "jobs, name, on")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: YML",
            "Root: Mapping",
            "3 keys",
            "5 mappings",
            "2 sequences",
            "6 values",
            "Keys: jobs, name, on",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)

        let remoteYAML = ToolArtifactState(value: "https://example.com/workflow.yml")
        XCTAssertNil(remoteYAML.yamlPreview)
    }

    func testArtifactStateDerivesPropertyListPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let plist = directory.appendingPathComponent("Info.plist")
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

        let artifact = ToolArtifactState(value: plist.path)
        let preview = try XCTUnwrap(artifact.propertyListPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "PLIST")
        XCTAssertEqual(preview.formatLabel, "XML PLIST")
        XCTAssertEqual(preview.rootLabel, "Dictionary")
        XCTAssertEqual(preview.keyCount, 5)
        XCTAssertNil(preview.itemCount)
        XCTAssertEqual(preview.dictionaryCount, 2)
        XCTAssertEqual(preview.arrayCount, 2)
        XCTAssertEqual(preview.scalarCount, 6)
        XCTAssertEqual(preview.keyPreviewLabels, [
            "CFBundleIdentifier",
            "CFBundleName",
            "CFBundleURLTypes",
            "LSMinimumSystemVersion",
            "NSPrincipalClass"
        ])
        XCTAssertEqual(
            preview.keyPreviewLabel,
            "CFBundleIdentifier, CFBundleName, CFBundleURLTypes, LSMinimumSystemVersion, NSPrincipalClass"
        )
        XCTAssertEqual(preview.byteSizeLabel, "\(data.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: XML PLIST",
            "Root: Dictionary",
            "5 keys",
            "2 dictionaries",
            "2 arrays",
            "6 values",
            "Keys: CFBundleIdentifier, CFBundleName, CFBundleURLTypes, LSMinimumSystemVersion, NSPrincipalClass",
            "Size: \(data.count) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)
        XCTAssertNil(artifact.yamlPreview)

        let remotePlist = ToolArtifactState(value: "https://example.com/Info.plist")
        XCTAssertNil(remotePlist.propertyListPreview)
    }

    func testArtifactStateDerivesXMLPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let manifest = directory.appendingPathComponent("manifest.xml")
        let content = """
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
        """
        try content.write(to: manifest, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: manifest.path)
        let preview = try XCTUnwrap(artifact.xmlPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.rootElementLabel, "project")
        XCTAssertEqual(preview.elementCount, 8)
        XCTAssertEqual(preview.attributeCount, 8)
        XCTAssertEqual(preview.namespaceCount, 1)
        XCTAssertEqual(preview.childPreviewLabels, ["dependencies", "module", "settings"])
        XCTAssertEqual(preview.childPreviewLabel, "dependencies, module, settings")
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: XML",
            "Root: project",
            "8 elements",
            "8 attributes",
            "1 namespace",
            "Children: dependencies, module, settings",
            "Size: \(content.utf8.count) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)
        XCTAssertNil(artifact.yamlPreview)
        XCTAssertNil(artifact.propertyListPreview)

        let remoteXML = ToolArtifactState(value: "https://example.com/manifest.xml")
        XCTAssertNil(remoteXML.xmlPreview)
    }

    func testArtifactStateDerivesOfficePackagePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let spreadsheet = directory.appendingPathComponent("budget.xlsx")
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

        let spreadsheetArtifact = ToolArtifactState(value: spreadsheet.path)
        let spreadsheetPreview = try XCTUnwrap(spreadsheetArtifact.officePreview)

        XCTAssertEqual(spreadsheetPreview.formatLabel, "Office Open XML")
        XCTAssertEqual(spreadsheetPreview.entryCount, 7)
        XCTAssertEqual(spreadsheetPreview.worksheetCount, 2)
        XCTAssertNil(spreadsheetPreview.slideCount)
        XCTAssertEqual(spreadsheetPreview.contentPreviewLabels, ["Sheet 1", "Sheet 2"])
        XCTAssertEqual(spreadsheetPreview.byteSizeLabel, ToolArtifactByteSizeFormatter.label(for: spreadsheetBytes.count))
        XCTAssertEqual(spreadsheetPreview.metadataLines, [
            "Format: Office Open XML",
            "7 package entries",
            "2 sheets",
            "Size: \(try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: spreadsheetBytes.count)))"
        ])

        let presentation = directory.appendingPathComponent("deck.pptx")
        try OfficePackageFixture.zipPackage(fileNames: [
            "[Content_Types].xml",
            "ppt/presentation.xml",
            "ppt/slides/slide1.xml",
            "ppt/slides/slide2.xml"
        ]).write(to: presentation)
        let presentationPreview = try XCTUnwrap(ToolArtifactState(value: presentation.path).officePreview)
        XCTAssertEqual(presentationPreview.entryCount, 4)
        XCTAssertNil(presentationPreview.worksheetCount)
        XCTAssertEqual(presentationPreview.slideCount, 2)
        XCTAssertEqual(presentationPreview.contentPreviewLabels, ["Slide 1", "Slide 2"])
        XCTAssertEqual(presentationPreview.metadataLines.dropFirst(2).first, "2 slides")

        let document = directory.appendingPathComponent("briefing.docx")
        try OfficePackageFixture.zipPackage(fileNames: [
            "[Content_Types].xml",
            "word/document.xml",
            "word/header1.xml",
            "word/footer1.xml",
            "word/comments.xml"
        ]).write(to: document)
        let documentPreview = try XCTUnwrap(ToolArtifactState(value: document.path).officePreview)
        XCTAssertEqual(documentPreview.contentPreviewLabels, [
            "Document body",
            "Comments",
            "1 header",
            "1 footer"
        ])

        let remoteSpreadsheet = ToolArtifactState(value: "https://example.com/budget.xlsx")
        XCTAssertNil(remoteSpreadsheet.officePreview)
    }

    func testArtifactStateDerivesArchivePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let archive = directory.appendingPathComponent("source.zip")
        let archiveBytes = OfficePackageFixture.zipPackage(fileNames: [
            "Sources/App.swift",
            "Sources/Model.swift",
            "Tests/AppTests.swift",
            "README.md"
        ])
        try archiveBytes.write(to: archive)
        let byteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: archiveBytes.count))

        let artifact = ToolArtifactState(value: archive.path)
        let preview = try XCTUnwrap(artifact.archivePreview)

        XCTAssertEqual(preview.formatLabel, "ZIP")
        XCTAssertEqual(preview.entryCount, 4)
        XCTAssertEqual(preview.topLevelCount, 3)
        XCTAssertEqual(preview.entryPreviewLabels, [
            "Sources/App.swift",
            "Sources/Model.swift",
            "Tests/AppTests.swift"
        ])
        XCTAssertEqual(preview.byteSizeLabel, byteSize)
        XCTAssertEqual(preview.metadataLines, [
            "Format: ZIP",
            "4 entries",
            "3 top-level items",
            "Entries: Sources/App.swift, Sources/Model.swift, Tests/AppTests.swift, +1 more",
            "Size: \(byteSize)"
        ])

        let tarArchive = directory.appendingPathComponent("sources.tar")
        let tarBytes = TarArchiveFixture.tarArchive(entries: [
            ("Sources/App.swift", Data("print(\"hi\")".utf8)),
            ("Sources/Model.swift", Data("struct Model {}".utf8)),
            ("Tests/AppTests.swift", Data("import XCTest".utf8))
        ])
        try tarBytes.write(to: tarArchive)
        let tarByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: tarBytes.count))

        let tarPreview = try XCTUnwrap(ToolArtifactState(value: tarArchive.path).archivePreview)
        XCTAssertEqual(tarPreview.formatLabel, "TAR")
        XCTAssertEqual(tarPreview.entryCount, 3)
        XCTAssertEqual(tarPreview.topLevelCount, 2)
        XCTAssertEqual(tarPreview.entryPreviewLabels, [
            "Sources/App.swift",
            "Sources/Model.swift",
            "Tests/AppTests.swift"
        ])
        XCTAssertEqual(tarPreview.byteSizeLabel, tarByteSize)
        XCTAssertEqual(tarPreview.metadataLines, [
            "Format: TAR",
            "3 entries",
            "2 top-level items",
            "Entries: Sources/App.swift, Sources/Model.swift, Tests/AppTests.swift",
            "Size: \(tarByteSize)"
        ])

        let gzipArchive = directory.appendingPathComponent("report.txt.gz")
        let gzipBytes = GzipArchiveFixture.gzipArchive(
            originalName: "report.txt",
            compressedBytes: Data("compressed".utf8),
            uncompressedByteCount: 2_048
        )
        try gzipBytes.write(to: gzipArchive)
        let gzipByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: gzipBytes.count))

        let gzipPreview = try XCTUnwrap(ToolArtifactState(value: gzipArchive.path).archivePreview)
        XCTAssertEqual(gzipPreview.formatLabel, "GZIP")
        XCTAssertEqual(gzipPreview.entryCount, 1)
        XCTAssertEqual(gzipPreview.topLevelCount, 1)
        XCTAssertEqual(gzipPreview.entryPreviewLabel, "report.txt")
        XCTAssertEqual(gzipPreview.entryPreviewLabels, ["report.txt"])
        XCTAssertEqual(gzipPreview.uncompressedByteSizeLabel, "2 KB")
        XCTAssertEqual(gzipPreview.byteSizeLabel, gzipByteSize)
        XCTAssertEqual(gzipPreview.metadataLines, [
            "Format: GZIP",
            "1 entry",
            "1 top-level item",
            "Entries: report.txt",
            "Uncompressed: 2 KB",
            "Size: \(gzipByteSize)"
        ])

        let compressedTarArchive = directory.appendingPathComponent("logs.tar.gz")
        let compressedTarBytes = GzipArchiveFixture.gzipArchive(
            originalName: "logs.tar",
            compressedBytes: Data("compressed tar".utf8),
            uncompressedByteCount: 8_192
        )
        try compressedTarBytes.write(to: compressedTarArchive)
        let compressedTarByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: compressedTarBytes.count))

        let compressedTarPreview = try XCTUnwrap(ToolArtifactState(value: compressedTarArchive.path).archivePreview)
        XCTAssertEqual(compressedTarPreview.formatLabel, "TAR.GZ")
        XCTAssertNil(compressedTarPreview.entryCount)
        XCTAssertNil(compressedTarPreview.topLevelCount)
        XCTAssertEqual(compressedTarPreview.entryPreviewLabel, "logs.tar")
        XCTAssertEqual(compressedTarPreview.entryPreviewLabels, ["logs.tar"])
        XCTAssertEqual(compressedTarPreview.uncompressedByteSizeLabel, "8 KB")
        XCTAssertEqual(compressedTarPreview.byteSizeLabel, compressedTarByteSize)
        XCTAssertEqual(compressedTarPreview.metadataLines, [
            "Format: TAR.GZ",
            "Entries: logs.tar",
            "Uncompressed: 8 KB",
            "Size: \(compressedTarByteSize)"
        ])

        let xzArchive = directory.appendingPathComponent("report.txt.xz")
        let xzBytes = XZArchiveFixture.xzArchive()
        try xzBytes.write(to: xzArchive)
        let xzByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: xzBytes.count))

        let xzPreview = try XCTUnwrap(ToolArtifactState(value: xzArchive.path).archivePreview)
        XCTAssertEqual(xzPreview.formatLabel, "XZ")
        XCTAssertEqual(xzPreview.entryCount, 1)
        XCTAssertEqual(xzPreview.topLevelCount, 1)
        XCTAssertEqual(xzPreview.entryPreviewLabel, "report.txt")
        XCTAssertEqual(xzPreview.entryPreviewLabels, ["report.txt"])
        XCTAssertEqual(xzPreview.byteSizeLabel, xzByteSize)
        XCTAssertEqual(xzPreview.metadataLines, [
            "Format: XZ",
            "1 entry",
            "1 top-level item",
            "Entries: report.txt",
            "Size: \(xzByteSize)"
        ])

        let compressedXZTarArchive = directory.appendingPathComponent("logs.tar.xz")
        let compressedXZTarBytes = XZArchiveFixture.xzArchive()
        try compressedXZTarBytes.write(to: compressedXZTarArchive)
        let compressedXZTarByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: compressedXZTarBytes.count))

        let compressedXZTarPreview = try XCTUnwrap(ToolArtifactState(value: compressedXZTarArchive.path).archivePreview)
        XCTAssertEqual(compressedXZTarPreview.formatLabel, "TAR.XZ")
        XCTAssertNil(compressedXZTarPreview.entryCount)
        XCTAssertNil(compressedXZTarPreview.topLevelCount)
        XCTAssertEqual(compressedXZTarPreview.entryPreviewLabel, "logs.tar")
        XCTAssertEqual(compressedXZTarPreview.entryPreviewLabels, ["logs.tar"])
        XCTAssertEqual(compressedXZTarPreview.byteSizeLabel, compressedXZTarByteSize)
        XCTAssertEqual(compressedXZTarPreview.metadataLines, [
            "Format: TAR.XZ",
            "Entries: logs.tar",
            "Size: \(compressedXZTarByteSize)"
        ])

        let bzipArchive = directory.appendingPathComponent("report.txt.bz2")
        let bzipBytes = Bzip2ArchiveFixture.bzip2Archive()
        try bzipBytes.write(to: bzipArchive)
        let bzipByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: bzipBytes.count))

        let bzipPreview = try XCTUnwrap(ToolArtifactState(value: bzipArchive.path).archivePreview)
        XCTAssertEqual(bzipPreview.formatLabel, "BZIP2")
        XCTAssertEqual(bzipPreview.entryCount, 1)
        XCTAssertEqual(bzipPreview.topLevelCount, 1)
        XCTAssertEqual(bzipPreview.entryPreviewLabel, "report.txt")
        XCTAssertEqual(bzipPreview.entryPreviewLabels, ["report.txt"])
        XCTAssertEqual(bzipPreview.byteSizeLabel, bzipByteSize)
        XCTAssertEqual(bzipPreview.metadataLines, [
            "Format: BZIP2",
            "1 entry",
            "1 top-level item",
            "Entries: report.txt",
            "Size: \(bzipByteSize)"
        ])

        let compressedBzipTarArchive = directory.appendingPathComponent("logs.tar.bz2")
        let compressedBzipTarBytes = Bzip2ArchiveFixture.bzip2Archive()
        try compressedBzipTarBytes.write(to: compressedBzipTarArchive)
        let compressedBzipTarByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: compressedBzipTarBytes.count))

        let compressedBzipTarPreview = try XCTUnwrap(ToolArtifactState(value: compressedBzipTarArchive.path).archivePreview)
        XCTAssertEqual(compressedBzipTarPreview.formatLabel, "TAR.BZ2")
        XCTAssertNil(compressedBzipTarPreview.entryCount)
        XCTAssertNil(compressedBzipTarPreview.topLevelCount)
        XCTAssertEqual(compressedBzipTarPreview.entryPreviewLabel, "logs.tar")
        XCTAssertEqual(compressedBzipTarPreview.entryPreviewLabels, ["logs.tar"])
        XCTAssertEqual(compressedBzipTarPreview.byteSizeLabel, compressedBzipTarByteSize)
        XCTAssertEqual(compressedBzipTarPreview.metadataLines, [
            "Format: TAR.BZ2",
            "Entries: logs.tar",
            "Size: \(compressedBzipTarByteSize)"
        ])

        let zstdArchive = directory.appendingPathComponent("report.txt.zst")
        let zstdBytes = ZstandardArchiveFixture.zstandardArchive()
        try zstdBytes.write(to: zstdArchive)
        let zstdByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: zstdBytes.count))

        let zstdPreview = try XCTUnwrap(ToolArtifactState(value: zstdArchive.path).archivePreview)
        XCTAssertEqual(zstdPreview.formatLabel, "ZSTD")
        XCTAssertEqual(zstdPreview.entryCount, 1)
        XCTAssertEqual(zstdPreview.topLevelCount, 1)
        XCTAssertEqual(zstdPreview.entryPreviewLabel, "report.txt")
        XCTAssertEqual(zstdPreview.entryPreviewLabels, ["report.txt"])
        XCTAssertEqual(zstdPreview.byteSizeLabel, zstdByteSize)
        XCTAssertEqual(zstdPreview.metadataLines, [
            "Format: ZSTD",
            "1 entry",
            "1 top-level item",
            "Entries: report.txt",
            "Size: \(zstdByteSize)"
        ])

        let compressedZstdTarArchive = directory.appendingPathComponent("logs.tar.zst")
        let compressedZstdTarBytes = ZstandardArchiveFixture.zstandardArchive()
        try compressedZstdTarBytes.write(to: compressedZstdTarArchive)
        let compressedZstdTarByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: compressedZstdTarBytes.count))

        let compressedZstdTarPreview = try XCTUnwrap(ToolArtifactState(value: compressedZstdTarArchive.path).archivePreview)
        XCTAssertEqual(compressedZstdTarPreview.formatLabel, "TAR.ZST")
        XCTAssertNil(compressedZstdTarPreview.entryCount)
        XCTAssertNil(compressedZstdTarPreview.topLevelCount)
        XCTAssertEqual(compressedZstdTarPreview.entryPreviewLabel, "logs.tar")
        XCTAssertEqual(compressedZstdTarPreview.entryPreviewLabels, ["logs.tar"])
        XCTAssertEqual(compressedZstdTarPreview.byteSizeLabel, compressedZstdTarByteSize)
        XCTAssertEqual(compressedZstdTarPreview.metadataLines, [
            "Format: TAR.ZST",
            "Entries: logs.tar",
            "Size: \(compressedZstdTarByteSize)"
        ])

        let remoteArchive = ToolArtifactState(value: "https://example.com/source.zip")
        XCTAssertNil(remoteArchive.archivePreview)
    }

    func testArtifactStateDerivesMediaPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let audio = directory.appendingPathComponent("voice-note.mp3")
        let video = directory.appendingPathComponent("demo.mp4")
        let audioBytes = ID3MediaFixture.mp3(title: "Morning Notes", artist: "Quill")
        var videoBytes = Data([0x00, 0x00, 0x00, 0x18])
        videoBytes.append(Data("ftypmp42".utf8))
        try audioBytes.write(to: audio)
        try videoBytes.write(to: video)

        let audioPreview = try XCTUnwrap(ToolArtifactState(value: audio.path).mediaPreview)
        let audioByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: audioBytes.count))
        XCTAssertEqual(audioPreview.formatLabel, "MP3")
        XCTAssertEqual(audioPreview.kind, .audio)
        XCTAssertEqual(audioPreview.title, "Morning Notes")
        XCTAssertEqual(audioPreview.artist, "Quill")
        XCTAssertEqual(audioPreview.byteSizeLabel, audioByteSize)
        XCTAssertEqual(audioPreview.playbackURL, audio.absoluteString)
        XCTAssertEqual(audioPreview.metadataLines, [
            "Format: MP3",
            "Artist: Quill",
            "Size: \(audioByteSize)"
        ])

        let videoPreview = try XCTUnwrap(ToolArtifactState(value: video.path).mediaPreview)
        let videoByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: videoBytes.count))
        XCTAssertEqual(videoPreview.formatLabel, "MP4")
        XCTAssertEqual(videoPreview.kind, .video)
        XCTAssertNil(videoPreview.title)
        XCTAssertNil(videoPreview.artist)
        XCTAssertEqual(videoPreview.byteSizeLabel, videoByteSize)
        XCTAssertEqual(videoPreview.playbackURL, video.absoluteString)
        XCTAssertEqual(videoPreview.metadataLines, [
            "Format: MP4",
            "Size: \(videoByteSize)"
        ])

        let remoteAudio = ToolArtifactState(value: "https://example.com/voice-note.mp3")
        XCTAssertNil(remoteAudio.mediaPreview)
    }

    func testArtifactStateDerivesDelimitedTablePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let csv = directory.appendingPathComponent("revenue.csv")
        try """
        Quarter,Revenue,Notes
        Q1,12000,Launch
        Q2,18500,"Expansion, EU"
        Q3,22400,Retention
        """.write(to: csv, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: csv.path)
        let preview = try XCTUnwrap(artifact.tablePreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .spreadsheet)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "CSV")
        XCTAssertEqual(preview.delimiterLabel, "CSV")
        XCTAssertEqual(preview.rowCountLabel, "4 rows")
        XCTAssertEqual(preview.columnCount, 3)
        XCTAssertEqual(preview.headers, ["Quarter", "Revenue", "Notes"])
        XCTAssertEqual(preview.rows, [
            ["Q1", "12000", "Launch"],
            ["Q2", "18500", "Expansion, EU"],
            ["Q3", "22400", "Retention"]
        ])
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: CSV",
            "4 rows, 3 columns"
        ])

        let remoteCSV = ToolArtifactState(value: "https://example.com/revenue.csv")
        XCTAssertNil(remoteCSV.tablePreview)
    }

    func testArtifactStateDerivesAppshotPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let appshotFile = directory.appendingPathComponent("checkout.appshot.json")
        try """
        {
          "app": {"displayName": "QuillCode"},
          "title": "Checkout flow",
          "summary": "Captured checkout page after payment details were entered.",
          "screenshotPath": "checkout.png",
          "viewport": {"width": 1440, "height": 1000},
          "windows": [{"title": "Checkout"}],
          "actions": [
            {"type": "click", "target": "Email"},
            {"type": "type", "text": "user@example.com"}
          ],
          "frames": [
            {"screenshot": "checkout-start.png"},
            {"screenshot": "checkout.png"}
          ],
          "events": [
            {"name": "navigation"},
            {"name": "form-fill"},
            {"name": "capture"}
          ],
          "capturedAt": "2026-06-21T12:00:00Z"
        }
        """.write(to: appshotFile, atomically: true, encoding: .utf8)

        let appshotBundle = ToolArtifactState(value: appshotFile.path)
        let preview = try XCTUnwrap(appshotBundle.appshotPreview)

        XCTAssertEqual(preview.title, "Checkout flow")
        XCTAssertEqual(preview.appLabel, "QuillCode")
        XCTAssertEqual(preview.summary, "Captured checkout page after payment details were entered.")
        let expectedScreenshotURL = directory
            .appendingPathComponent("checkout.png")
            .standardizedFileURL
            .absoluteString
        XCTAssertEqual(preview.screenshotURL, expectedScreenshotURL)
        XCTAssertEqual(preview.viewportLabel, "1440 x 1000")
        XCTAssertEqual(preview.windowCount, 1)
        XCTAssertEqual(preview.actionCount, 2)
        XCTAssertEqual(preview.frameCount, 2)
        XCTAssertEqual(preview.eventCount, 3)
        XCTAssertEqual(preview.actionLabels, ["click: Email", "type: user@example.com"])
        XCTAssertEqual(preview.frameLabels, ["checkout-start.png", "checkout.png"])
        XCTAssertEqual(preview.eventLabels, ["navigation", "form-fill", "capture"])
        XCTAssertEqual(preview.capturedAt, "2026-06-21T12:00:00Z")
        XCTAssertEqual(preview.metadataLines, [
            "App: QuillCode",
            "Viewport: 1440 x 1000",
            "1 window",
            "2 actions",
            "2 frames",
            "3 events",
            "Captured: 2026-06-21T12:00:00Z"
        ])
    }

    func testArtifactTextPreviewBuilderReadsLocalTextFilesOnly() throws {
        let directory = try makeQuillCodeTestDirectory()
        let textFile = directory.appendingPathComponent("hello.txt")
        let appshotFile = directory.appendingPathComponent("checkout.appshot.json")
        let binaryFile = directory.appendingPathComponent("data.bin")
        try "hello world\n".write(to: textFile, atomically: true, encoding: .utf8)
        try #"{"kind":"appshot"}"#.write(to: appshotFile, atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3]).write(to: binaryFile)

        XCTAssertEqual(ToolArtifactTextPreviewBuilder.textPreview(for: textFile.path), "hello world\n")
        XCTAssertEqual(ToolArtifactTextPreviewBuilder.textPreview(for: textFile.absoluteString), "hello world\n")
        XCTAssertNil(ToolArtifactTextPreviewBuilder.textPreview(for: appshotFile.path))
        XCTAssertNil(ToolArtifactTextPreviewBuilder.textPreview(for: binaryFile.path))
        XCTAssertNil(ToolArtifactTextPreviewBuilder.textPreview(for: "https://example.com/hello.txt"))
    }

    func testArtifactStateDerivesSourceTextPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let source = directory.appendingPathComponent("main.swift")
        let sourceText = """
        import Foundation

        print("hello")
        """
        try sourceText.write(to: source, atomically: true, encoding: .utf8)

        let textPreview = try XCTUnwrap(ToolArtifactTextPreviewBuilder.textPreview(for: source.path))
        let artifact = ToolArtifactState(value: source.path, textPreview: textPreview)
        let preview = try XCTUnwrap(artifact.sourceTextPreview)
        let byteCount = try XCTUnwrap(sourceText.data(using: .utf8)?.count)

        XCTAssertEqual(preview.typeLabel, "Swift")
        XCTAssertEqual(preview.lineCountLabel, "3 lines")
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Type: Swift",
            "3 lines",
            "Size: \(byteCount) bytes"
        ])
    }

    func testArtifactStateDerivesCommonCodingSourcePreviewLabels() throws {
        let directory = try makeQuillCodeTestDirectory()

        func assertSourcePreview(
            filename: String,
            contents: String,
            typeLabel: String,
            lineCountLabel: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let source = directory.appendingPathComponent(filename)
            try contents.write(to: source, atomically: true, encoding: .utf8)
            let textPreview = try XCTUnwrap(
                ToolArtifactTextPreviewBuilder.textPreview(for: source.path),
                file: file,
                line: line
            )
            let artifact = ToolArtifactState(value: source.path, textPreview: textPreview)
            let preview = try XCTUnwrap(artifact.sourceTextPreview, file: file, line: line)

            XCTAssertEqual(preview.typeLabel, typeLabel, file: file, line: line)
            XCTAssertEqual(preview.lineCountLabel, lineCountLabel, file: file, line: line)
            XCTAssertFalse(preview.isTruncated, file: file, line: line)
        }

        try assertSourcePreview(
            filename: "Dashboard.vue",
            contents: "<template>\n  <main>{{ title }}</main>\n</template>\n",
            typeLabel: "Vue",
            lineCountLabel: "3 lines"
        )
        try assertSourcePreview(
            filename: "Panel.svelte",
            contents: "<script>\n  export let title\n</script>\n<h1>{title}</h1>\n",
            typeLabel: "Svelte",
            lineCountLabel: "4 lines"
        )
        try assertSourcePreview(
            filename: "page.astro",
            contents: "---\nconst title = 'QuillCode'\n---\n<h1>{title}</h1>\n",
            typeLabel: "Astro",
            lineCountLabel: "4 lines"
        )
        try assertSourcePreview(
            filename: "Program.cs",
            contents: "Console.WriteLine(\"hello\");\n",
            typeLabel: "C#",
            lineCountLabel: "1 line"
        )
        try assertSourcePreview(
            filename: "go.mod",
            contents: "module example.com/quill\n\ngo 1.23\n",
            typeLabel: "Go module",
            lineCountLabel: "3 lines"
        )
        try assertSourcePreview(
            filename: "build.gradle.kts",
            contents: "plugins {\n  kotlin(\"jvm\") version \"2.0.0\"\n}\n",
            typeLabel: "Gradle Kotlin",
            lineCountLabel: "3 lines"
        )
    }

    private func pngHeader(width: UInt32, height: UInt32) -> Data {
        var bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52
        ]
        bytes.append(contentsOf: bigEndianBytes(width))
        bytes.append(contentsOf: bigEndianBytes(height))
        bytes.append(contentsOf: [0x08, 0x02, 0x00, 0x00, 0x00])
        return Data(bytes)
    }

    private func gifHeader(width: UInt16, height: UInt16) -> Data {
        var bytes = Array("GIF89a".utf8)
        bytes.append(UInt8(width & 0x00FF))
        bytes.append(UInt8(width >> 8))
        bytes.append(UInt8(height & 0x00FF))
        bytes.append(UInt8(height >> 8))
        return Data(bytes)
    }

    private func jpegHeader(width: UInt16, height: UInt16) -> Data {
        Data([
            0xFF, 0xD8,
            0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00,
            0xFF, 0xC0, 0x00, 0x0B, 0x08,
            UInt8(height >> 8), UInt8(height & 0x00FF),
            UInt8(width >> 8), UInt8(width & 0x00FF),
            0x01, 0x01, 0x11, 0x00
        ])
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

    private func webpVP8LHeader(width: UInt32, height: UInt32) -> Data {
        let packedWidth = width - 1
        let packedHeight = height - 1
        var bytes = Array("RIFF".utf8)
        bytes.append(contentsOf: littleEndianBytes(UInt32(25)))
        bytes.append(contentsOf: Array("WEBPVP8L".utf8))
        bytes.append(contentsOf: littleEndianBytes(UInt32(5)))
        bytes.append(0x2F)
        bytes.append(UInt8(packedWidth & 0xFF))
        bytes.append(UInt8(((packedWidth >> 8) & 0x3F) | ((packedHeight & 0x03) << 6)))
        bytes.append(UInt8((packedHeight >> 2) & 0xFF))
        bytes.append(UInt8((packedHeight >> 10) & 0x0F))
        return Data(bytes)
    }

    private func webpVP8Header(width: UInt16, height: UInt16) -> Data {
        var bytes = Array("RIFF".utf8)
        bytes.append(contentsOf: littleEndianBytes(UInt32(30)))
        bytes.append(contentsOf: Array("WEBPVP8 ".utf8))
        bytes.append(contentsOf: littleEndianBytes(UInt32(10)))
        bytes.append(contentsOf: [0, 0, 0, 0x9D, 0x01, 0x2A])
        bytes.append(UInt8(width & 0x00FF))
        bytes.append(UInt8(width >> 8))
        bytes.append(UInt8(height & 0x00FF))
        bytes.append(UInt8(height >> 8))
        return Data(bytes)
    }

    private func tiffHeader(width: UInt32, height: UInt32, byteOrder: TIFFFixtureByteOrder) -> Data {
        var bytes = Array(byteOrder.signature.utf8)
        bytes.append(contentsOf: byteOrder.uint16Bytes(42))
        bytes.append(contentsOf: byteOrder.uint32Bytes(8))
        bytes.append(contentsOf: byteOrder.uint16Bytes(2))
        bytes.append(contentsOf: tiffEntry(tag: 256, value: width, byteOrder: byteOrder))
        bytes.append(contentsOf: tiffEntry(tag: 257, value: height, byteOrder: byteOrder))
        bytes.append(contentsOf: byteOrder.uint32Bytes(0))
        return Data(bytes)
    }

    private func icoHeader(sizes: [(width: UInt8, height: UInt8)]) -> Data {
        var bytes: [UInt8] = [
            0, 0,
            1, 0,
            UInt8(sizes.count & 0x00FF),
            UInt8((sizes.count >> 8) & 0x00FF)
        ]
        for size in sizes {
            bytes.append(size.width)
            bytes.append(size.height)
            bytes.append(contentsOf: [
                0, 0,
                1, 0,
                32, 0
            ])
            bytes.append(contentsOf: littleEndianBytes(UInt32(4)))
            bytes.append(contentsOf: littleEndianBytes(UInt32(6 + sizes.count * 16)))
        }
        return Data(bytes)
    }

    private func tiffEntry(tag: UInt16, value: UInt32, byteOrder: TIFFFixtureByteOrder) -> [UInt8] {
        byteOrder.uint16Bytes(tag)
            + byteOrder.uint16Bytes(4)
            + byteOrder.uint32Bytes(1)
            + byteOrder.uint32Bytes(value)
    }

    private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
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

    private enum TIFFFixtureByteOrder {
        case littleEndian
        case bigEndian

        var signature: String {
            switch self {
            case .littleEndian: return "II"
            case .bigEndian: return "MM"
            }
        }

        func uint16Bytes(_ value: UInt16) -> [UInt8] {
            switch self {
            case .littleEndian:
                return [UInt8(value & 0x00FF), UInt8(value >> 8)]
            case .bigEndian:
                return [UInt8(value >> 8), UInt8(value & 0x00FF)]
            }
        }

        func uint32Bytes(_ value: UInt32) -> [UInt8] {
            switch self {
            case .littleEndian:
                return [
                    UInt8(value & 0xFF),
                    UInt8((value >> 8) & 0xFF),
                    UInt8((value >> 16) & 0xFF),
                    UInt8((value >> 24) & 0xFF)
                ]
            case .bigEndian:
                return [
                    UInt8((value >> 24) & 0xFF),
                    UInt8((value >> 16) & 0xFF),
                    UInt8((value >> 8) & 0xFF),
                    UInt8(value & 0xFF)
                ]
            }
        }
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
