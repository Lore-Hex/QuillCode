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

    func testArtifactStateDerivesNPMLockfilePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("package-lock.json")
        let jsonText = """
        {
          "name": "quillcode-web",
          "version": "0.1.0",
          "lockfileVersion": 3,
          "packages": {
            "": {
              "name": "quillcode-web",
              "version": "0.1.0"
            },
            "node_modules/@playwright/test": {
              "version": "1.55.0",
              "resolved": "https://registry.npmjs.org/@playwright/test/-/test-1.55.0.tgz",
              "dev": true
            },
            "node_modules/lucide-react": {
              "version": "0.468.0",
              "resolved": "https://registry.npmjs.org/lucide-react/-/lucide-react-0.468.0.tgz"
            },
            "node_modules/fsevents": {
              "version": "2.3.3",
              "resolved": "https://registry.npmjs.org/fsevents/-/fsevents-2.3.3.tgz",
              "optional": true
            }
          },
          "dependencies": {
            "@playwright/test": {"version": "1.55.0"},
            "fsevents": {"version": "2.3.3"},
            "lucide-react": {"version": "0.468.0"}
          }
        }
        """
        try jsonText.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.npmLockfilePreview)
        let byteSizeLabel = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: XCTUnwrap(jsonText.data(using: .utf8)).count))

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.lockfileVersion, "3")
        XCTAssertEqual(preview.rootPackageLabel, "quillcode-web@0.1.0")
        XCTAssertEqual(preview.packageCount, 3)
        XCTAssertEqual(preview.dependencyCount, 3)
        XCTAssertEqual(preview.devPackageCount, 1)
        XCTAssertEqual(preview.optionalPackageCount, 1)
        XCTAssertEqual(preview.resolvedHostLabels, ["registry.npmjs.org"])
        XCTAssertEqual(preview.packagePreviewLabels, [
            "@playwright/test@1.55.0 · dev",
            "fsevents@2.3.3 · optional",
            "lucide-react@0.468.0"
        ])
        XCTAssertEqual(preview.byteSizeLabel, byteSizeLabel)
        XCTAssertEqual(preview.metadataLines, [
            "Format: npm lockfile",
            "Lockfile: 3",
            "Root: quillcode-web@0.1.0",
            "3 packages",
            "3 dependencies",
            "1 dev package",
            "1 optional package",
            "Size: \(byteSizeLabel)"
        ])
        XCTAssertNotNil(artifact.jsonPreview)

        let packageJSON = directory.appendingPathComponent("package.json")
        try #"{"name":"quillcode-web","lockfileVersion":3}"#.write(to: packageJSON, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: packageJSON.path).npmLockfilePreview)

        let remoteLockfile = ToolArtifactState(value: "https://example.com/package-lock.json")
        XCTAssertNil(remoteLockfile.npmLockfilePreview)
    }

    func testArtifactStateDerivesSwiftPMPackageResolvedPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("Package.resolved")
        let jsonText = """
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
            },
            {
              "identity": "swift-collections",
              "kind": "remoteSourceControl",
              "location": "https://github.com/apple/swift-collections.git",
              "state": {
                "revision": "1234567890abcdef"
              }
            }
          ],
          "version": 2
        }
        """
        try jsonText.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.swiftPMPackageResolvedPreview)
        let byteSizeLabel = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: XCTUnwrap(jsonText.data(using: .utf8)).count))

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "SPM")
        XCTAssertEqual(preview.schemaVersion, "2")
        XCTAssertEqual(preview.pinCount, 3)
        XCTAssertEqual(preview.versionedPinCount, 1)
        XCTAssertEqual(preview.branchPinCount, 1)
        XCTAssertEqual(preview.revisionOnlyPinCount, 1)
        XCTAssertEqual(preview.sourceHostLabels, ["github.com"])
        XCTAssertEqual(preview.pinPreviewLabels, [
            "swift-argument-parser@1.5.0",
            "trusted-router-swift · main",
            "swift-collections · 1234567890ab"
        ])
        XCTAssertEqual(preview.byteSizeLabel, byteSizeLabel)
        XCTAssertEqual(preview.metadataLines, [
            "Format: SwiftPM resolved packages",
            "Schema: 2",
            "3 pins",
            "1 versioned",
            "1 branch",
            "1 revision-only",
            "Size: \(byteSizeLabel)"
        ])

        let packageJSON = directory.appendingPathComponent("package.json")
        try #"{"pins":[],"version":2}"#.write(to: packageJSON, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: packageJSON.path).swiftPMPackageResolvedPreview)

        let remoteResolved = ToolArtifactState(value: "https://example.com/Package.resolved")
        XCTAssertNil(remoteResolved.swiftPMPackageResolvedPreview)
    }

    func testArtifactStateDerivesCycloneDXPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("bom.json")
        let jsonText = """
        {
          "bomFormat": "CycloneDX",
          "specVersion": "1.6",
          "serialNumber": "urn:uuid:7f9b2e15-40d4-4f37-9d97-6e5d5c76d601",
          "metadata": {
            "component": {
              "type": "application",
              "name": "QuillCode",
              "version": "0.1.0",
              "purl": "pkg:generic/quillcode@0.1.0"
            }
          },
          "components": [
            {
              "type": "library",
              "name": "trusted-router-swift",
              "version": "1.2.3",
              "purl": "pkg:swift/lore-hex/trusted-router-swift@1.2.3"
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
            { "id": "CVE-0000-0001", "ratings": [{ "severity": "high" }] },
            { "id": "CVE-0000-0002", "ratings": [{ "severity": "critical" }] },
            { "id": "CVE-0000-0003", "severity": "medium" }
          ]
        }
        """
        try jsonText.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.cycloneDXPreview)
        let byteSizeLabel = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: XCTUnwrap(jsonText.data(using: .utf8)).count))

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.specVersion, "1.6")
        XCTAssertEqual(preview.serialNumber, "urn:uuid:7f9b2e15-40d4-4f37-9d97-6e5d5c76d601")
        XCTAssertEqual(preview.rootComponentLabel, "QuillCode@0.1.0 · application · pkg:generic/quillcode@0.1.0")
        XCTAssertEqual(preview.componentCount, 2)
        XCTAssertEqual(preview.serviceCount, 1)
        XCTAssertEqual(preview.dependencyCount, 1)
        XCTAssertEqual(preview.vulnerabilityCount, 3)
        XCTAssertEqual(preview.criticalVulnerabilityCount, 1)
        XCTAssertEqual(preview.highVulnerabilityCount, 1)
        XCTAssertEqual(preview.mediumVulnerabilityCount, 1)
        XCTAssertEqual(preview.lowVulnerabilityCount, 0)
        XCTAssertEqual(preview.byteSizeLabel, byteSizeLabel)
        XCTAssertEqual(preview.componentPreviewLabels, [
            "trusted-router-swift@1.2.3 · library · pkg:swift/lore-hex/trusted-router-swift@1.2.3",
            "Yams@5.1.3 · library"
        ])
        XCTAssertEqual(preview.metadataLines, [
            "Format: CycloneDX",
            "Spec: 1.6",
            "Root: QuillCode@0.1.0 · application · pkg:generic/quillcode@0.1.0",
            "Serial: urn:uuid:7f9b2e15-40d4-4f37-9d97-6e5d5c76d601",
            "2 components",
            "1 service",
            "1 dependency",
            "Vulnerabilities: 3",
            "Critical: 1",
            "High: 1",
            "Medium: 1",
            "Size: \(byteSizeLabel)"
        ])
        let packageJSON = directory.appendingPathComponent("package.json")
        try #"{"name":"quillcode","version":"0.1.0"}"#.write(to: packageJSON, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: packageJSON.path).cycloneDXPreview)

        let remoteSBOM = ToolArtifactState(value: "https://example.com/bom.json")
        XCTAssertNil(remoteSBOM.cycloneDXPreview)
    }

    func testArtifactStateDerivesSPDXPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("sbom.spdx.json")
        let jsonText = """
        {
          "spdxVersion": "SPDX-2.3",
          "SPDXID": "SPDXRef-DOCUMENT",
          "name": "QuillCode SBOM",
          "documentNamespace": "https://lorehex.example/spdx/quillcode-2026",
          "creationInfo": {
            "creators": [
              "Tool: quill-code",
              "Organization: Lore Hex"
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
        """
        try jsonText.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.spdxPreview)
        let byteSizeLabel = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: XCTUnwrap(jsonText.data(using: .utf8)).count))

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.specVersion, "SPDX-2.3")
        XCTAssertEqual(preview.documentName, "QuillCode SBOM")
        XCTAssertEqual(preview.documentNamespace, "https://lorehex.example/spdx/quillcode-2026")
        XCTAssertEqual(preview.packageCount, 2)
        XCTAssertEqual(preview.fileCount, 1)
        XCTAssertEqual(preview.relationshipCount, 1)
        XCTAssertEqual(preview.extractedLicenseCount, 1)
        XCTAssertEqual(preview.creatorCount, 2)
        XCTAssertEqual(preview.byteSizeLabel, byteSizeLabel)
        XCTAssertEqual(preview.packagePreviewLabels, [
            "QuillCode@0.1.0 · SPDXRef-Package-QuillCode",
            "trusted-router-swift@1.2.3 · SPDXRef-Package-TrustedRouterSwift"
        ])
        XCTAssertEqual(preview.licensePreviewLabels, [
            "Apache-2.0",
            "MIT",
            "LicenseRef-Lore-Hex-Notice"
        ])
        XCTAssertEqual(preview.metadataLines, [
            "Format: SPDX",
            "Spec: SPDX-2.3",
            "Document: QuillCode SBOM",
            "Namespace: https://lorehex.example/spdx/quillcode-2026",
            "2 packages",
            "1 file",
            "1 relationship",
            "1 extracted license",
            "2 creators",
            "Size: \(byteSizeLabel)"
        ])

        let packageJSON = directory.appendingPathComponent("package.json")
        try #"{"name":"quillcode","version":"0.1.0"}"#.write(to: packageJSON, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: packageJSON.path).spdxPreview)

        let remoteSBOM = ToolArtifactState(value: "https://example.com/sbom.spdx.json")
        XCTAssertNil(remoteSBOM.spdxPreview)
    }

    func testArtifactStateDerivesHARPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let trace = directory.appendingPathComponent("network.har")
        let harText = """
        {
          "log": {
            "version": "1.2",
            "creator": {"name": "QuillCode", "version": "1.0"},
            "entries": [
              {
                "request": {"method": "GET", "url": "https://api.trustedrouter.com/v1/models?token=secret"},
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

        let artifact = ToolArtifactState(value: trace.path)
        let preview = try XCTUnwrap(artifact.harPreview)
        let byteCount = try XCTUnwrap(harText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "HAR")
        XCTAssertEqual(preview.versionLabel, "1.2")
        XCTAssertEqual(preview.creatorLabel, "QuillCode 1.0")
        XCTAssertEqual(preview.entryCount, 3)
        XCTAssertEqual(preview.methodLabels, ["GET", "POST"])
        XCTAssertEqual(preview.statusGroupLabels, ["2xx", "4xx"])
        XCTAssertEqual(preview.hostPreviewLabels, ["api.trustedrouter.com", "quillos.cloud"])
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: HAR",
            "Version: 1.2",
            "Creator: QuillCode 1.0",
            "3 entries",
            "Methods: GET, POST",
            "Statuses: 2xx, 4xx",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)

        let corruptHAR = directory.appendingPathComponent("corrupt.har")
        try #"{"entries":[]}"#.write(to: corruptHAR, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: corruptHAR.path).harPreview)

        let remoteHAR = ToolArtifactState(value: "https://example.com/network.har")
        XCTAssertNil(remoteHAR.harPreview)
    }

    func testArtifactStateDerivesLCOVPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let coverage = directory.appendingPathComponent("lcov.info")
        let lcovText = """
        TN:QuillCode
        SF:/workspace/Sources/QuillCodeApp/Workspace.swift
        FN:10,render
        FNDA:3,render
        DA:10,3
        DA:11,0
        DA:12,5
        LF:3
        LH:2
        BRDA:12,0,0,1
        BRDA:12,0,1,0
        BRF:2
        BRH:1
        FNF:1
        FNH:1
        end_of_record
        SF:/workspace/Tests/QuillCodeAppTests/WorkspaceTests.swift
        DA:20,1
        DA:21,1
        DA:22,0
        end_of_record
        """
        try lcovText.write(to: coverage, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: coverage.path)
        let preview = try XCTUnwrap(artifact.lcovPreview)
        let byteCount = try XCTUnwrap(lcovText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "LCOV")
        XCTAssertEqual(preview.formatLabel, "LCOV")
        XCTAssertEqual(preview.sourceFileCount, 2)
        XCTAssertEqual(preview.lineHitCount, 4)
        XCTAssertEqual(preview.lineFoundCount, 6)
        XCTAssertEqual(preview.branchHitCount, 1)
        XCTAssertEqual(preview.branchFoundCount, 2)
        XCTAssertEqual(preview.functionHitCount, 1)
        XCTAssertEqual(preview.functionFoundCount, 1)
        XCTAssertEqual(preview.lineCoverageLabel, "66.7% (4/6)")
        XCTAssertEqual(preview.branchCoverageLabel, "50% (1/2)")
        XCTAssertEqual(preview.functionCoverageLabel, "100% (1/1)")
        XCTAssertEqual(preview.sourcePreviewLabels, [
            "QuillCodeApp/Workspace.swift · 66.7%",
            "QuillCodeAppTests/WorkspaceTests.swift · 66.7%"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: LCOV",
            "2 source files",
            "Lines: 66.7% (4/6)",
            "Branches: 50% (1/2)",
            "Functions: 100% (1/1)",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)

        let extensionCoverage = directory.appendingPathComponent("coverage.lcov")
        try lcovText.write(to: extensionCoverage, atomically: true, encoding: .utf8)
        let extensionArtifact = ToolArtifactState(value: extensionCoverage.path)
        XCTAssertEqual(extensionArtifact.documentPreview?.extensionLabel, "LCOV")
        XCTAssertEqual(extensionArtifact.lcovPreview?.sourceFileCount, 2)

        let remoteLCOV = ToolArtifactState(value: "https://example.com/lcov.info")
        XCTAssertNil(remoteLCOV.lcovPreview)

        let invalidLCOV = directory.appendingPathComponent("empty.info")
        try "TN:empty\n".write(to: invalidLCOV, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: invalidLCOV.path).lcovPreview)
    }

    func testArtifactStateDerivesGoCoveragePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let coverage = directory.appendingPathComponent("cover.out")
        let coverageText = """
        mode: atomic
        github.com/lore/QuillCode/internal/runtime/runner.go:10.1,12.2 3 1
        github.com/lore/QuillCode/internal/runtime/runner.go:14.1,15.2 2 0
        github.com/lore/QuillCode/pkg/tools/shell.go:20.1,24.2 5 2
        """
        try coverageText.write(to: coverage, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: coverage.path)
        let preview = try XCTUnwrap(artifact.goCoveragePreview)
        let byteCount = try XCTUnwrap(coverageText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "GOCOVER")
        XCTAssertEqual(preview.formatLabel, "Go coverage")
        XCTAssertEqual(preview.modeLabel, "atomic")
        XCTAssertEqual(preview.sourceFileCount, 2)
        XCTAssertEqual(preview.blockCount, 3)
        XCTAssertEqual(preview.statementCoveredCount, 8)
        XCTAssertEqual(preview.statementTotalCount, 10)
        XCTAssertEqual(preview.statementCoverageLabel, "80% (8/10)")
        XCTAssertEqual(preview.sourcePreviewLabels, [
            "runtime/runner.go · 60%",
            "tools/shell.go · 100%"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.metadataLines, [
            "Format: Go coverage",
            "Mode: atomic",
            "2 source files",
            "3 blocks",
            "Statements: 80% (8/10)",
            "Size: \(byteCount) bytes"
        ])

        let coverageOut = directory.appendingPathComponent("coverage.out")
        try coverageText.write(to: coverageOut, atomically: true, encoding: .utf8)
        XCTAssertEqual(ToolArtifactState(value: coverageOut.path).goCoveragePreview?.sourceFileCount, 2)

        let genericOut = directory.appendingPathComponent("build.out")
        try coverageText.write(to: genericOut, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: genericOut.path).documentPreview)
        XCTAssertNil(ToolArtifactState(value: genericOut.path).goCoveragePreview)

        let invalidDirectory = directory.appendingPathComponent("invalid", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidDirectory, withIntermediateDirectories: true)
        let invalid = invalidDirectory.appendingPathComponent("coverage.out")
        try "mode: weird\nmain.go:1.1,2.1 1 1\n".write(to: invalid, atomically: true, encoding: .utf8)
        XCTAssertEqual(ToolArtifactState(value: invalid.path).documentPreview?.extensionLabel, "GOCOVER")
        XCTAssertNil(ToolArtifactState(value: invalid.path).goCoveragePreview)

        let remote = ToolArtifactState(value: "https://example.com/cover.out")
        XCTAssertNil(remote.goCoveragePreview)
    }

    func testArtifactStateDerivesSARIFPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("codeql.sarif.json")
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
                {"ruleId": "swift/style", "level": "note"},
                {"ruleId": "swift/suppressed", "level": "none"}
              ]
            },
            {
              "tool": {"driver": {"name": "Semgrep"}},
              "results": [
                {"ruleId": "swift/path-injection", "level": "warning"}
              ]
            }
          ]
        }
        """
        try sarifText.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.sarifPreview)
        let byteCount = try XCTUnwrap(sarifText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "SARIF")
        XCTAssertEqual(preview.versionLabel, "2.1.0")
        XCTAssertEqual(preview.runCount, 2)
        XCTAssertEqual(preview.resultCount, 5)
        XCTAssertEqual(preview.errorCount, 1)
        XCTAssertEqual(preview.warningCount, 2)
        XCTAssertEqual(preview.noteCount, 1)
        XCTAssertEqual(preview.noneCount, 1)
        XCTAssertEqual(preview.toolPreviewLabels, ["CodeQL", "Semgrep"])
        XCTAssertEqual(preview.rulePreviewLabels, [
            "swift/hardcoded-credential",
            "swift/path-injection",
            "swift/style",
            "swift/suppressed"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: SARIF",
            "Version: 2.1.0",
            "2 runs",
            "5 results",
            "Errors: 1",
            "Warnings: 2",
            "Notes: 1",
            "None: 1",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)

        let extensionReport = directory.appendingPathComponent("security.sarif")
        try sarifText.write(to: extensionReport, atomically: true, encoding: .utf8)
        let extensionArtifact = ToolArtifactState(value: extensionReport.path)
        XCTAssertEqual(extensionArtifact.documentPreview?.extensionLabel, "SARIF")
        XCTAssertEqual(extensionArtifact.sarifPreview?.resultCount, 5)

        let remoteSARIF = ToolArtifactState(value: "https://example.com/codeql.sarif.json")
        XCTAssertNil(remoteSARIF.sarifPreview)

        let invalidSARIF = directory.appendingPathComponent("invalid.sarif")
        try #"{"version":"2.1.0"}"#.write(to: invalidSARIF, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: invalidSARIF.path).sarifPreview)
    }

    func testArtifactStateDerivesNotebookPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let notebook = directory.appendingPathComponent("analysis.ipynb")
        let notebookText = """
        {
          "cells": [
            {"cell_type": "markdown", "metadata": {}, "source": ["# Analysis\\n"]},
            {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["print('hello')\\n"]},
            {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["1 + 1\\n"]},
            {"cell_type": "raw", "metadata": {}, "source": ["notes\\n"]}
          ],
          "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3.12"}
          },
          "nbformat": 4,
          "nbformat_minor": 5
        }
        """
        try notebookText.write(to: notebook, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: notebook.path)
        let preview = try XCTUnwrap(artifact.notebookPreview)
        let byteCount = try XCTUnwrap(notebookText.data(using: .utf8)?.count)

        XCTAssertEqual(artifact.documentPreview?.kind, .document)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "IPYNB")
        XCTAssertEqual(preview.formatLabel, "Jupyter Notebook")
        XCTAssertEqual(preview.notebookVersionLabel, "4.5")
        XCTAssertEqual(preview.languageLabel, "python")
        XCTAssertEqual(preview.codeCellCount, 2)
        XCTAssertEqual(preview.markdownCellCount, 1)
        XCTAssertEqual(preview.rawCellCount, 1)
        XCTAssertEqual(preview.byteSizeLabel, "\(byteCount) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: Jupyter Notebook",
            "Version: 4.5",
            "Language: python",
            "4 cells",
            "2 code",
            "1 markdown",
            "1 raw",
            "Size: \(byteCount) bytes"
        ])
        XCTAssertNil(artifact.jsonPreview)

        let invalidNotebook = directory.appendingPathComponent("broken.ipynb")
        try #"{"metadata":{}}"#.write(to: invalidNotebook, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: invalidNotebook.path).notebookPreview)

        let remoteNotebook = ToolArtifactState(value: "https://example.com/analysis.ipynb")
        XCTAssertNil(remoteNotebook.notebookPreview)
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

    func testArtifactStateDerivesIstanbulPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("coverage-final.json")
        let content = """
        {
          "/workspace/Sources/QuillCodeApp/Workspace.swift": {
            "statementMap": {
              "0": {"start": {"line": 10}, "end": {"line": 10}},
              "1": {"start": {"line": 11}, "end": {"line": 11}},
              "2": {"start": {"line": 11}, "end": {"line": 11}}
            },
            "s": {"0": 1, "1": 0, "2": 2},
            "fnMap": {"0": {"name": "render"}, "1": {"name": "send"}},
            "f": {"0": 1, "1": 0},
            "branchMap": {"0": {"type": "if"}, "1": {"type": "binary-expr"}},
            "b": {"0": [1, 0], "1": [2, 1]}
          },
          "/workspace/Sources/QuillCodeTools/ShellToolExecutor.swift": {
            "statementMap": {
              "0": {"start": {"line": 20}, "end": {"line": 20}},
              "1": {"start": {"line": 21}, "end": {"line": 21}}
            },
            "s": {"0": 0, "1": 0},
            "fnMap": {"0": {"name": "run"}},
            "f": {"0": 0},
            "branchMap": {"0": {"type": "if"}},
            "b": {"0": [0, 0]}
          }
        }
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.istanbulPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.sourceFileCount, 2)
        XCTAssertEqual(preview.lineCoverageLabel, "50% (2/4)")
        XCTAssertEqual(preview.statementCoverageLabel, "40% (2/5)")
        XCTAssertEqual(preview.branchCoverageLabel, "50% (3/6)")
        XCTAssertEqual(preview.functionCoverageLabel, "33.3% (1/3)")
        XCTAssertEqual(preview.filePreviewLabels, [
            "QuillCodeApp/Workspace.swift · 100%",
            "QuillCodeTools/ShellToolExecutor.swift · 0%"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: Istanbul JSON",
            "2 source files",
            "Lines: 50% (2/4)",
            "Statements: 40% (2/5)",
            "Branches: 50% (3/6)",
            "Functions: 33.3% (1/3)",
            "Size: \(content.utf8.count) bytes"
        ])

        let generic = directory.appendingPathComponent("build-report.json")
        try #"{"status":"passed","durationMs":42}"#.write(to: generic, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: generic.path).istanbulPreview)

        let summary = directory.appendingPathComponent("coverage-summary.json")
        try """
        {
          "total": {
            "lines": {"total": 20, "covered": 18, "skipped": 0, "pct": 90},
            "statements": {"total": 25, "covered": 20, "skipped": 0, "pct": 80},
            "branches": {"total": 10, "covered": 7, "skipped": 0, "pct": 70},
            "functions": {"total": 5, "covered": 4, "skipped": 0, "pct": 80}
          },
          "/workspace/Sources/QuillCodeApp/Workspace.swift": {
            "lines": {"total": 10, "covered": 9, "skipped": 0, "pct": 90}
          }
        }
        """.write(to: summary, atomically: true, encoding: .utf8)
        let summaryPreview = try XCTUnwrap(ToolArtifactState(value: summary.path).istanbulPreview)
        XCTAssertEqual(summaryPreview.lineCoverageLabel, "90% (18/20)")
        XCTAssertEqual(summaryPreview.statementCoverageLabel, "80% (20/25)")
        XCTAssertEqual(summaryPreview.branchCoverageLabel, "70% (7/10)")
        XCTAssertEqual(summaryPreview.functionCoverageLabel, "80% (4/5)")

        let remoteIstanbul = ToolArtifactState(value: "https://example.com/coverage-final.json")
        XCTAssertNil(remoteIstanbul.istanbulPreview)
    }

    func testArtifactStateDerivesCoveragePyPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("coverage.json")
        let content = """
        {
          "meta": {"format": 2, "version": "7.6.1", "branch_coverage": true},
          "files": {
            "src/quillcode/app.py": {
              "executed_lines": [1, 2, 4],
              "summary": {
                "covered_lines": 3,
                "num_statements": 4,
                "covered_branches": 1,
                "num_branches": 2
              }
            },
            "tests/test_app.py": {
              "executed_lines": [1, 2],
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
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.coveragePyPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.formatLabel, "coverage.py JSON")
        XCTAssertEqual(preview.versionLabel, "7.6.1")
        XCTAssertEqual(preview.sourceFileCount, 2)
        XCTAssertEqual(preview.lineCoverageLabel, "83.3% (5/6)")
        XCTAssertEqual(preview.branchCoverageLabel, "50% (1/2)")
        XCTAssertEqual(preview.filePreviewLabels, [
            "quillcode/app.py · 75%",
            "tests/test_app.py · 100%"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: coverage.py JSON",
            "Version: 7.6.1",
            "2 source files",
            "Lines: 83.3% (5/6)",
            "Branches: 50% (1/2)",
            "Size: \(content.utf8.count) bytes"
        ])

        let generic = directory.appendingPathComponent("build-report.json")
        try #"{"status":"passed","durationMs":42}"#.write(to: generic, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: generic.path).coveragePyPreview)

        let remoteCoveragePy = ToolArtifactState(value: "https://example.com/coverage.json")
        XCTAssertNil(remoteCoveragePy.coveragePyPreview)
    }

    func testArtifactStateDerivesPytestJSONPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("report.json")
        let content = """
        {
          "created": 1780000000.0,
          "duration": 12.345,
          "exitcode": 1,
          "root": "/workspace",
          "summary": {
            "total": 5,
            "passed": 2,
            "failed": 1,
            "error": 1,
            "skipped": 1,
            "xfailed": 0,
            "xpassed": 0
          },
          "tests": [
            {"nodeid": "tests/test_app.py::test_renders_prompt", "outcome": "passed"},
            {"nodeid": "tests/test_app.py::test_writes_file", "outcome": "failed"},
            {"nodeid": "tests/test_cli.py::test_bootstrap", "outcome": "error"},
            {"nodeid": "tests/test_cli.py::test_skip", "outcome": "skipped"}
          ]
        }
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.pytestJSONPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.formatLabel, "pytest JSON")
        XCTAssertEqual(preview.exitCode, 1)
        XCTAssertEqual(preview.durationLabel, "12.3s")
        XCTAssertEqual(preview.totalCount, 5)
        XCTAssertEqual(preview.passedCount, 2)
        XCTAssertEqual(preview.failedCount, 1)
        XCTAssertEqual(preview.errorCount, 1)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(preview.failurePreviewLabels, [
            "tests/test_app.py::test_writes_file",
            "tests/test_cli.py::test_bootstrap"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: pytest JSON",
            "Exit code: 1",
            "Duration: 12.3s",
            "5 tests",
            "Passed: 2",
            "Failed: 1",
            "Errors: 1",
            "Skipped: 1",
            "XFailed: 0",
            "XPassed: 0",
            "Size: \(content.utf8.count) bytes"
        ])

        let generic = directory.appendingPathComponent("build-report.json")
        try #"{"status":"passed","durationMs":42}"#.write(to: generic, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: generic.path).pytestJSONPreview)

        let remotePytest = ToolArtifactState(value: "https://example.com/report.json")
        XCTAssertNil(remotePytest.pytestJSONPreview)
    }

    func testArtifactStateDerivesJestJSONPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("jest-results.json")
        let content = """
        {
          "success": false,
          "numTotalTests": 4,
          "numPassedTests": 2,
          "numFailedTests": 1,
          "numPendingTests": 1,
          "numTodoTests": 0,
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
            },
            {
              "name": "/repo/tests/cli.test.ts",
              "perfStats": {"runtime": 2000},
              "assertionResults": [
                {"fullName": "CLI starts quickly", "status": "passed"},
                {"fullName": "CLI waits for fixture", "status": "pending"}
              ]
            }
          ]
        }
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.jestJSONPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "JSON")
        XCTAssertEqual(preview.formatLabel, "Jest JSON")
        XCTAssertEqual(preview.success, false)
        XCTAssertEqual(preview.totalTestCount, 4)
        XCTAssertEqual(preview.passedTestCount, 2)
        XCTAssertEqual(preview.failedTestCount, 1)
        XCTAssertEqual(preview.pendingTestCount, 1)
        XCTAssertEqual(preview.todoTestCount, 0)
        XCTAssertEqual(preview.totalSuiteCount, 2)
        XCTAssertEqual(preview.failedSuiteCount, 1)
        XCTAssertEqual(preview.runtimeLabel, "3.23s")
        XCTAssertEqual(preview.failurePreviewLabels, ["App > writes a file"])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: Jest JSON",
            "Result: failed",
            "Runtime: 3.23s",
            "4 tests",
            "Passed: 2",
            "Failed: 1",
            "Pending: 1",
            "TODO: 0",
            "2 suites",
            "Failed suites: 1",
            "Size: \(content.utf8.count) bytes"
        ])

        let generic = directory.appendingPathComponent("build-report.json")
        try #"{"success":false,"durationMs":42}"#.write(to: generic, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: generic.path).jestJSONPreview)

        let remoteJest = ToolArtifactState(value: "https://example.com/jest-results.json")
        XCTAssertNil(remoteJest.jestJSONPreview)
    }

    func testArtifactStateDerivesTAPPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("test.tap")
        let content = """
        TAP version 13
        1..4
        ok 1 - loads app
        not ok 2 - writes file
        ok 3 - optional browser # SKIP no browser
        not ok 4 - planned support # TODO implement later
        Bail out! database unavailable
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.tapPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "TAP")
        XCTAssertEqual(preview.formatLabel, "TAP")
        XCTAssertEqual(preview.planLabel, "1..4")
        XCTAssertEqual(preview.assertionCount, 4)
        XCTAssertEqual(preview.passedCount, 3)
        XCTAssertEqual(preview.failedCount, 1)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(preview.todoCount, 1)
        XCTAssertEqual(preview.bailoutLabel, "database unavailable")
        XCTAssertEqual(preview.failurePreviewLabels, ["2 - writes file"])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: TAP",
            "Plan: 1..4",
            "4 assertions",
            "Passed: 3",
            "Failed: 1",
            "Skipped: 1",
            "TODO: 1",
            "Bail out: database unavailable",
            "Size: \(content.utf8.count) bytes"
        ])

        let generic = directory.appendingPathComponent("notes.tap")
        try "this is not tap\n".write(to: generic, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: generic.path).tapPreview)

        let remoteTAP = ToolArtifactState(value: "https://example.com/test.tap")
        XCTAssertNil(remoteTAP.tapPreview)
    }

    func testArtifactStateDerivesJUnitPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("TEST-QuillCode.xml")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
          <testsuite name="QuillCodeAppTests" tests="3" failures="1" errors="0" skipped="1" time="1.25">
            <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testRendersArtifacts" time="0.1" />
            <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testStreamsOutput" time="0.2">
              <failure message="expected streamed output" />
            </testcase>
            <testcase classname="QuillCodeAppTests.WorkspaceTests" name="testSkipped">
              <skipped />
            </testcase>
          </testsuite>
          <testsuite name="QuillCodeToolsTests" tests="2" failures="0" errors="1" skipped="0" time="0.75">
            <testcase classname="QuillCodeToolsTests.ShellTests" name="testWhoami" />
            <testcase classname="QuillCodeToolsTests.ShellTests" name="testTimeout">
              <error message="timed out" />
            </testcase>
          </testsuite>
        </testsuites>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.junitPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.suiteCount, 2)
        XCTAssertEqual(preview.testCount, 5)
        XCTAssertEqual(preview.failureCount, 1)
        XCTAssertEqual(preview.errorCount, 1)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(preview.durationLabel, "2 s")
        XCTAssertEqual(preview.suitePreviewLabels, ["QuillCodeAppTests", "QuillCodeToolsTests"])
        XCTAssertEqual(preview.failurePreviewLabels, [
            "QuillCodeAppTests.WorkspaceTests.testStreamsOutput",
            "QuillCodeToolsTests.ShellTests.testTimeout"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: JUnit XML",
            "2 suites",
            "5 tests",
            "Failures: 1",
            "Errors: 1",
            "Skipped: 1",
            "Duration: 2 s",
            "Size: \(content.utf8.count) bytes"
        ])

        let fallbackReport = directory.appendingPathComponent("fallback.xml")
        try """
        <testsuite name="FallbackSuite">
          <testcase classname="FallbackTests" name="testPass" />
          <testcase classname="FallbackTests" name="testFailure"><failure /></testcase>
          <testcase classname="FallbackTests" name="testError"><error /></testcase>
          <testcase classname="FallbackTests" name="testSkipped"><skipped /></testcase>
        </testsuite>
        """.write(to: fallbackReport, atomically: true, encoding: .utf8)
        let fallbackPreview = try XCTUnwrap(ToolArtifactState(value: fallbackReport.path).junitPreview)
        XCTAssertEqual(fallbackPreview.testCount, 4)
        XCTAssertEqual(fallbackPreview.failureCount, 1)
        XCTAssertEqual(fallbackPreview.errorCount, 1)
        XCTAssertEqual(fallbackPreview.skippedCount, 1)

        let nonJUnit = directory.appendingPathComponent("manifest.xml")
        try "<project><target /></project>".write(to: nonJUnit, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: nonJUnit.path).junitPreview)

        let remoteJUnit = ToolArtifactState(value: "https://example.com/TEST-QuillCode.xml")
        XCTAssertNil(remoteJUnit.junitPreview)
    }

    func testArtifactStateDerivesTRXPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("results.trx")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TestRun id="run-1" name="QuillCode .NET Tests" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
          <Results>
            <UnitTestResult testName="QuillCode.Tests.AppTests.RendersPrompt" outcome="Passed" duration="00:00:01.1000000" />
            <UnitTestResult testName="QuillCode.Tests.AppTests.WritesFile" outcome="Failed" duration="00:00:02.2500000" />
            <UnitTestResult testName="QuillCode.Tests.CliTests.IsSkipped" outcome="NotExecuted" duration="00:00:00.0000000" />
            <UnitTestResult testName="QuillCode.Tests.CliTests.IsInconclusive" outcome="Inconclusive" duration="00:00:00.5000000" />
          </Results>
        </TestRun>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.trxPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "TRX")
        XCTAssertEqual(preview.formatLabel, "TRX")
        XCTAssertEqual(preview.testRunName, "QuillCode .NET Tests")
        XCTAssertEqual(preview.totalCount, 4)
        XCTAssertEqual(preview.passedCount, 1)
        XCTAssertEqual(preview.failedCount, 1)
        XCTAssertEqual(preview.inconclusiveCount, 1)
        XCTAssertEqual(preview.notExecutedCount, 1)
        XCTAssertEqual(preview.durationLabel, "3.85 s")
        XCTAssertEqual(preview.failurePreviewLabels, ["QuillCode.Tests.AppTests.WritesFile"])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: TRX",
            "Run: QuillCode .NET Tests",
            "4 tests",
            "Passed: 1",
            "Failed: 1",
            "Inconclusive: 1",
            "Not executed: 1",
            "Duration: 3.85 s",
            "Size: \(content.utf8.count) bytes"
        ])

        let generic = directory.appendingPathComponent("report.trx")
        try "<project><target /></project>".write(to: generic, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: generic.path).trxPreview)

        let remoteTRX = ToolArtifactState(value: "https://example.com/results.trx")
        XCTAssertNil(remoteTRX.trxPreview)
    }

    func testArtifactStateDerivesXUnitPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("xunit-results.xml")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <assemblies>
          <assembly name="/workspace/bin/Debug/net8.0/QuillCode.Tests.dll" total="4" passed="2" failed="1" skipped="1" time="3.50">
            <collection name="QuillCode app tests">
              <test name="QuillCode.Tests.AppTests.RendersPrompt" result="Pass" time="1.25" />
              <test name="QuillCode.Tests.AppTests.WritesFile" result="Fail" time="2.00" />
              <test name="QuillCode.Tests.CliTests.IsSkipped" result="Skip" time="0.25" />
            </collection>
          </assembly>
        </assemblies>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.xunitPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.assemblyCount, 1)
        XCTAssertEqual(preview.collectionCount, 1)
        XCTAssertEqual(preview.testCount, 4)
        XCTAssertEqual(preview.passedCount, 2)
        XCTAssertEqual(preview.failedCount, 1)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(preview.durationLabel, "3.5 s")
        XCTAssertEqual(preview.assemblyPreviewLabels, ["QuillCode.Tests.dll"])
        XCTAssertEqual(preview.failurePreviewLabels, ["QuillCode.Tests.AppTests.WritesFile"])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: xUnit XML",
            "1 assembly",
            "1 collection",
            "4 tests",
            "Passed: 2",
            "Failed: 1",
            "Skipped: 1",
            "Duration: 3.5 s",
            "Size: \(content.utf8.count) bytes"
        ])

        let fallbackReport = directory.appendingPathComponent("xunit-fallback.xml")
        try """
        <assembly name="QuillCode.Fallback.dll">
          <collection name="Fallback">
            <test name="FallbackTests.Pass" result="Pass" time="0.25" />
            <test name="FallbackTests.Fail" result="Fail" time="0.75" />
            <test name="FallbackTests.Skip" result="Skip" time="0.00" />
          </collection>
        </assembly>
        """.write(to: fallbackReport, atomically: true, encoding: .utf8)
        let fallbackPreview = try XCTUnwrap(ToolArtifactState(value: fallbackReport.path).xunitPreview)
        XCTAssertEqual(fallbackPreview.testCount, 3)
        XCTAssertEqual(fallbackPreview.passedCount, 1)
        XCTAssertEqual(fallbackPreview.failedCount, 1)
        XCTAssertEqual(fallbackPreview.skippedCount, 1)
        XCTAssertEqual(fallbackPreview.durationLabel, "1 s")

        let nonXUnit = directory.appendingPathComponent("manifest.xml")
        try "<project><target /></project>".write(to: nonXUnit, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: nonXUnit.path).xunitPreview)

        let remoteXUnit = ToolArtifactState(value: "https://example.com/xunit-results.xml")
        XCTAssertNil(remoteXUnit.xunitPreview)
    }

    func testArtifactStateDerivesNUnitPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("TestResult.xml")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <test-run id="2" name="QuillCode NUnit Tests" total="4" passed="2" failed="1" inconclusive="0" skipped="1" duration="4.25">
          <test-suite type="Assembly" name="QuillCode.Tests.dll">
            <test-case id="0-1001" fullname="QuillCode.Tests.AppTests.RendersPrompt" result="Passed" duration="1.25" />
            <test-case id="0-1002" fullname="QuillCode.Tests.AppTests.WritesFile" result="Failed" duration="2.00" />
            <test-case id="0-1003" fullname="QuillCode.Tests.CliTests.IsSkipped" result="Skipped" duration="0.25" />
          </test-suite>
        </test-run>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.nunitPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.runName, "QuillCode NUnit Tests")
        XCTAssertEqual(preview.testCount, 4)
        XCTAssertEqual(preview.passedCount, 2)
        XCTAssertEqual(preview.failedCount, 1)
        XCTAssertEqual(preview.inconclusiveCount, 0)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(preview.durationLabel, "4.25 s")
        XCTAssertEqual(preview.failurePreviewLabels, ["QuillCode.Tests.AppTests.WritesFile"])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: NUnit XML",
            "Run: QuillCode NUnit Tests",
            "4 tests",
            "Passed: 2",
            "Failed: 1",
            "Skipped: 1",
            "Duration: 4.25 s",
            "Size: \(content.utf8.count) bytes"
        ])

        let fallbackReport = directory.appendingPathComponent("nunit-fallback.xml")
        try """
        <test-run name="Fallback NUnit">
          <test-case fullname="FallbackTests.Pass" result="Passed" duration="0.25" />
          <test-case fullname="FallbackTests.Fail" result="Failed" duration="0.75" />
          <test-case fullname="FallbackTests.Inconclusive" result="Inconclusive" duration="0.50" />
          <test-case fullname="FallbackTests.Skip" result="Skipped" duration="0.00" />
        </test-run>
        """.write(to: fallbackReport, atomically: true, encoding: .utf8)
        let fallbackPreview = try XCTUnwrap(ToolArtifactState(value: fallbackReport.path).nunitPreview)
        XCTAssertEqual(fallbackPreview.testCount, 4)
        XCTAssertEqual(fallbackPreview.passedCount, 1)
        XCTAssertEqual(fallbackPreview.failedCount, 1)
        XCTAssertEqual(fallbackPreview.inconclusiveCount, 1)
        XCTAssertEqual(fallbackPreview.skippedCount, 1)
        XCTAssertEqual(fallbackPreview.durationLabel, "1.5 s")

        let nonNUnit = directory.appendingPathComponent("manifest.xml")
        try "<project><target /></project>".write(to: nonNUnit, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: nonNUnit.path).nunitPreview)

        let remoteNUnit = ToolArtifactState(value: "https://example.com/TestResult.xml")
        XCTAssertNil(remoteNUnit.nunitPreview)
    }

    func testArtifactStateDerivesCoberturaPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("coverage.xml")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <coverage line-rate="0.75" branch-rate="0.5" lines-covered="3" lines-valid="4" branches-covered="1" branches-valid="2" version="1.9">
          <packages>
            <package name="QuillCodeApp">
              <classes>
                <class name="Workspace" filename="Sources/QuillCodeApp/Workspace.swift" />
                <class name="ToolCard" filename="Sources/QuillCodeApp/ToolCard.swift" />
              </classes>
            </package>
            <package name="QuillCodeTools">
              <classes>
                <class name="ShellToolExecutor" filename="Sources/QuillCodeTools/ShellToolExecutor.swift" />
              </classes>
            </package>
          </packages>
        </coverage>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.coberturaPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.versionLabel, "1.9")
        XCTAssertEqual(preview.packageCount, 2)
        XCTAssertEqual(preview.classCount, 3)
        XCTAssertEqual(preview.lineCoverageLabel, "75% (3/4)")
        XCTAssertEqual(preview.branchCoverageLabel, "50% (1/2)")
        XCTAssertEqual(preview.packagePreviewLabels, ["QuillCodeApp", "QuillCodeTools"])
        XCTAssertEqual(preview.classPreviewLabels, [
            "Workspace · Sources/QuillCodeApp/Workspace.swift",
            "ToolCard · Sources/QuillCodeApp/ToolCard.swift",
            "ShellToolExecutor · Sources/QuillCodeTools/ShellToolExecutor.swift"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: Cobertura XML",
            "Version: 1.9",
            "2 packages",
            "3 classes",
            "Lines: 75% (3/4)",
            "Branches: 50% (1/2)",
            "Size: \(content.utf8.count) bytes"
        ])
        XCTAssertNil(artifact.junitPreview)

        let rateOnly = directory.appendingPathComponent("rate-only.xml")
        try #"<coverage line-rate="0.8333" branch-rate="0.25"><packages /></coverage>"#
            .write(to: rateOnly, atomically: true, encoding: .utf8)
        let ratePreview = try XCTUnwrap(ToolArtifactState(value: rateOnly.path).coberturaPreview)
        XCTAssertEqual(ratePreview.lineCoverageLabel, "83.3%")
        XCTAssertEqual(ratePreview.branchCoverageLabel, "25%")

        let clover = directory.appendingPathComponent("clover.xml")
        try #"<coverage generated="1780000000"><project><metrics elements="10" coveredelements="8" /></project></coverage>"#
            .write(to: clover, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: clover.path).coberturaPreview)

        let nonCobertura = directory.appendingPathComponent("manifest.xml")
        try "<project><target /></project>".write(to: nonCobertura, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: nonCobertura.path).coberturaPreview)

        let remoteCobertura = ToolArtifactState(value: "https://example.com/coverage.xml")
        XCTAssertNil(remoteCobertura.coberturaPreview)
    }

    func testArtifactStateDerivesCloverPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("clover.xml")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <coverage generated="1780000000" clover="4.5.0">
          <project name="QuillCode">
            <file name="Workspace.swift" path="Sources/QuillCodeApp/Workspace.swift" />
            <file name="ShellToolExecutor.swift" path="Sources/QuillCodeTools/ShellToolExecutor.swift" />
            <metrics packages="2" files="2" classes="3" methods="10" coveredmethods="8" statements="20" coveredstatements="15" conditionals="6" coveredconditionals="3" elements="36" coveredelements="26" />
          </project>
        </coverage>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.cloverPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.packageCount, 2)
        XCTAssertEqual(preview.fileCount, 2)
        XCTAssertEqual(preview.classCount, 3)
        XCTAssertEqual(preview.elementCoverageLabel, "72.2% (26/36)")
        XCTAssertEqual(preview.methodCoverageLabel, "80% (8/10)")
        XCTAssertEqual(preview.statementCoverageLabel, "75% (15/20)")
        XCTAssertEqual(preview.conditionalCoverageLabel, "50% (3/6)")
        XCTAssertEqual(preview.projectPreviewLabels, ["QuillCode"])
        XCTAssertEqual(preview.filePreviewLabels, [
            "Sources/QuillCodeApp/Workspace.swift",
            "Sources/QuillCodeTools/ShellToolExecutor.swift"
        ])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: Clover XML",
            "2 packages",
            "2 files",
            "3 classes",
            "Elements: 72.2% (26/36)",
            "Methods: 80% (8/10)",
            "Statements: 75% (15/20)",
            "Conditionals: 50% (3/6)",
            "Size: \(content.utf8.count) bytes"
        ])
        XCTAssertNil(artifact.coberturaPreview)
        XCTAssertNil(artifact.junitPreview)

        let nonClover = directory.appendingPathComponent("coverage-generic.xml")
        try "<coverage><packages /></coverage>".write(to: nonClover, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: nonClover.path).cloverPreview)

        let remoteClover = ToolArtifactState(value: "https://example.com/clover.xml")
        XCTAssertNil(remoteClover.cloverPreview)
    }

    func testArtifactStateDerivesJaCoCoPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let report = directory.appendingPathComponent("jacoco.xml")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <report name="QuillCode">
          <sessioninfo id="test-host" start="1780000000" dump="1780000100" />
          <package name="dev/quillcode/app">
            <class name="dev/quillcode/app/Workspace" sourcefilename="Workspace.kt" />
            <sourcefile name="Workspace.kt" />
          </package>
          <package name="dev/quillcode/tools">
            <class name="dev/quillcode/tools/ShellToolExecutor" sourcefilename="ShellToolExecutor.kt" />
            <sourcefile name="ShellToolExecutor.kt" />
          </package>
          <counter type="INSTRUCTION" missed="4" covered="96" />
          <counter type="BRANCH" missed="2" covered="6" />
          <counter type="LINE" missed="3" covered="17" />
          <counter type="METHOD" missed="1" covered="9" />
          <counter type="CLASS" missed="0" covered="2" />
        </report>
        """
        try content.write(to: report, atomically: true, encoding: .utf8)

        let artifact = ToolArtifactState(value: report.path)
        let preview = try XCTUnwrap(artifact.jaCoCoPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "XML")
        XCTAssertEqual(preview.reportNameLabel, "QuillCode")
        XCTAssertEqual(preview.packageCount, 2)
        XCTAssertEqual(preview.sourceFileCount, 2)
        XCTAssertEqual(preview.classCount, 2)
        XCTAssertEqual(preview.lineCoverageLabel, "85% (17/20)")
        XCTAssertEqual(preview.branchCoverageLabel, "75% (6/8)")
        XCTAssertEqual(preview.methodCoverageLabel, "90% (9/10)")
        XCTAssertEqual(preview.classCoverageLabel, "100% (2/2)")
        XCTAssertEqual(preview.packagePreviewLabels, ["dev/quillcode/app", "dev/quillcode/tools"])
        XCTAssertEqual(preview.sourceFilePreviewLabels, ["Workspace.kt", "ShellToolExecutor.kt"])
        XCTAssertEqual(preview.byteSizeLabel, "\(content.utf8.count) bytes")
        XCTAssertEqual(preview.metadataLines, [
            "Format: JaCoCo XML",
            "Report: QuillCode",
            "2 packages",
            "2 source files",
            "2 classes",
            "Lines: 85% (17/20)",
            "Branches: 75% (6/8)",
            "Methods: 90% (9/10)",
            "Classes: 100% (2/2)",
            "Size: \(content.utf8.count) bytes"
        ])
        XCTAssertNil(artifact.junitPreview)
        XCTAssertNil(artifact.coberturaPreview)
        XCTAssertNil(artifact.cloverPreview)

        let nonJaCoCo = directory.appendingPathComponent("report.xml")
        try "<report><summary /></report>".write(to: nonJaCoCo, atomically: true, encoding: .utf8)
        XCTAssertNil(ToolArtifactState(value: nonJaCoCo.path).jaCoCoPreview)

        let remoteJaCoCo = ToolArtifactState(value: "https://example.com/jacoco.xml")
        XCTAssertNil(remoteJaCoCo.jaCoCoPreview)
    }

    func testArtifactStateDerivesSQLitePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let database = directory.appendingPathComponent("cache.sqlite3")
        let bytes = sqliteFixture(pageSize: 4096, pageCount: 3)
        try bytes.write(to: database)

        let artifact = ToolArtifactState(value: database.path)
        let preview = try XCTUnwrap(artifact.sqlitePreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "SQLITE3")
        XCTAssertEqual(preview.formatLabel, "SQLite")
        XCTAssertEqual(preview.pageSize, 4096)
        XCTAssertEqual(preview.pageCount, 3)
        XCTAssertEqual(preview.byteSizeLabel, ToolArtifactByteSizeFormatter.label(for: bytes.count))
        XCTAssertEqual(preview.metadataLines, [
            "Format: SQLite",
            "Page size: 4096 bytes",
            "3 pages",
            "Size: \(try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: bytes.count)))"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)
        XCTAssertNil(artifact.yamlPreview)
        XCTAssertNil(artifact.propertyListPreview)

        let genericDB = directory.appendingPathComponent("cache.db")
        try bytes.write(to: genericDB)
        XCTAssertEqual(ToolArtifactState(value: genericDB.path).sqlitePreview?.pageCount, 3)

        let corruptDatabase = directory.appendingPathComponent("corrupt.sqlite3")
        try Data(repeating: 0, count: 128).write(to: corruptDatabase)
        XCTAssertNil(ToolArtifactState(value: corruptDatabase.path).sqlitePreview)

        let remoteDatabase = ToolArtifactState(value: "https://example.com/cache.sqlite3")
        XCTAssertNil(remoteDatabase.sqlitePreview)
    }

    private func sqliteFixture(pageSize: Int, pageCount: Int) -> Data {
        let byteCount = max(100, pageSize * pageCount)
        var data = Data(repeating: 0, count: byteCount)
        let magic = Data("SQLite format 3\u{0000}".utf8)
        data.replaceSubrange(0..<magic.count, with: magic)
        data[16] = UInt8((pageSize >> 8) & 0xFF)
        data[17] = UInt8(pageSize & 0xFF)
        data[28] = UInt8((pageCount >> 24) & 0xFF)
        data[29] = UInt8((pageCount >> 16) & 0xFF)
        data[30] = UInt8((pageCount >> 8) & 0xFF)
        data[31] = UInt8(pageCount & 0xFF)
        return data
    }

    func testArtifactStateDerivesWebAssemblyPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let module = directory.appendingPathComponent("module.wasm")
        let bytes = wasmFixture(version: 1)
        try bytes.write(to: module)

        let artifact = ToolArtifactState(value: module.path)
        let preview = try XCTUnwrap(artifact.webAssemblyPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "WASM")
        XCTAssertEqual(preview.formatLabel, "WebAssembly")
        XCTAssertEqual(preview.version, 1)
        XCTAssertEqual(preview.byteSizeLabel, ToolArtifactByteSizeFormatter.label(for: bytes.count))
        XCTAssertEqual(preview.metadataLines, [
            "Format: WebAssembly",
            "Version: 1",
            "Size: \(try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: bytes.count)))"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)
        XCTAssertNil(artifact.yamlPreview)
        XCTAssertNil(artifact.propertyListPreview)
        XCTAssertNil(artifact.sqlitePreview)

        let corruptModule = directory.appendingPathComponent("corrupt.wasm")
        try Data(repeating: 0, count: 8).write(to: corruptModule)
        XCTAssertNil(ToolArtifactState(value: corruptModule.path).webAssemblyPreview)

        let remoteModule = ToolArtifactState(value: "https://example.com/module.wasm")
        XCTAssertNil(remoteModule.webAssemblyPreview)
    }

    private func wasmFixture(version: UInt32) -> Data {
        Data([
            0x00, 0x61, 0x73, 0x6D,
            UInt8(version & 0xFF),
            UInt8((version >> 8) & 0xFF),
            UInt8((version >> 16) & 0xFF),
            UInt8((version >> 24) & 0xFF)
        ])
    }

    func testArtifactStateDerivesFontPreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let font = directory.appendingPathComponent("Inter.woff2")
        let bytes = woff2Fixture(flavor: "OTTO", declaredSize: 32, tableCount: 7)
        try bytes.write(to: font)

        let artifact = ToolArtifactState(value: font.path)
        let preview = try XCTUnwrap(artifact.fontPreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "WOFF2")
        XCTAssertEqual(preview.formatLabel, "WOFF2")
        XCTAssertEqual(preview.flavorLabel, "OpenType CFF")
        XCTAssertEqual(preview.tableCount, 7)
        XCTAssertEqual(preview.byteSizeLabel, ToolArtifactByteSizeFormatter.label(for: bytes.count))
        XCTAssertEqual(preview.declaredByteSizeLabel, ToolArtifactByteSizeFormatter.label(for: 32))
        XCTAssertEqual(preview.metadataLines, [
            "Format: WOFF2",
            "Flavor: OpenType CFF",
            "7 tables",
            "Declared size: \(try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: 32)))",
            "Size: \(try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: bytes.count)))"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)
        XCTAssertNil(artifact.yamlPreview)
        XCTAssertNil(artifact.propertyListPreview)
        XCTAssertNil(artifact.sqlitePreview)
        XCTAssertNil(artifact.webAssemblyPreview)

        let otf = directory.appendingPathComponent("Display.otf")
        try sfntFixture(signature: "OTTO", tableCount: 3).write(to: otf)
        let otfPreview = try XCTUnwrap(ToolArtifactState(value: otf.path).fontPreview)
        XCTAssertEqual(otfPreview.formatLabel, "OpenType")
        XCTAssertEqual(otfPreview.tableCount, 3)

        let corruptFont = directory.appendingPathComponent("corrupt.woff2")
        try Data(repeating: 0, count: 16).write(to: corruptFont)
        XCTAssertNil(ToolArtifactState(value: corruptFont.path).fontPreview)

        let remoteFont = ToolArtifactState(value: "https://example.com/Inter.woff2")
        XCTAssertNil(remoteFont.fontPreview)
    }

    private func woff2Fixture(flavor: String, declaredSize: UInt32, tableCount: UInt16) -> Data {
        var data = Data("wOF2".utf8)
        data.append(Data(flavor.utf8))
        data.append(UInt8((declaredSize >> 24) & 0xFF))
        data.append(UInt8((declaredSize >> 16) & 0xFF))
        data.append(UInt8((declaredSize >> 8) & 0xFF))
        data.append(UInt8(declaredSize & 0xFF))
        data.append(UInt8((tableCount >> 8) & 0xFF))
        data.append(UInt8(tableCount & 0xFF))
        data.append(contentsOf: [0, 0])
        return data
    }

    private func sfntFixture(signature: String, tableCount: UInt16) -> Data {
        var data = Data(signature.utf8)
        data.append(UInt8((tableCount >> 8) & 0xFF))
        data.append(UInt8(tableCount & 0xFF))
        data.append(contentsOf: [0, 0, 0, 0, 0, 0])
        return data
    }

    func testArtifactStateDerivesExecutablePreviewMetadata() throws {
        let directory = try makeQuillCodeTestDirectory()
        let sharedObject = directory.appendingPathComponent("libquill.so")
        let bytes = elfFixture(machine: 0xB7, bitness: 2, littleEndian: true)
        try bytes.write(to: sharedObject)

        let artifact = ToolArtifactState(value: sharedObject.path)
        let preview = try XCTUnwrap(artifact.executablePreview)

        XCTAssertEqual(artifact.documentPreview?.kind, .data)
        XCTAssertEqual(artifact.documentPreview?.extensionLabel, "SO")
        XCTAssertEqual(preview.formatLabel, "ELF")
        XCTAssertEqual(preview.architectureLabel, "ARM64")
        XCTAssertEqual(preview.bitnessLabel, "64-bit")
        XCTAssertEqual(preview.endianLabel, "Little")
        XCTAssertEqual(preview.byteSizeLabel, ToolArtifactByteSizeFormatter.label(for: bytes.count))
        XCTAssertEqual(preview.metadataLines, [
            "Format: ELF",
            "Architecture: ARM64",
            "Class: 64-bit",
            "Endian: Little",
            "Size: \(try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: bytes.count)))"
        ])
        XCTAssertNil(artifact.jsonPreview)
        XCTAssertNil(artifact.jsonLinesPreview)
        XCTAssertNil(artifact.tomlPreview)
        XCTAssertNil(artifact.yamlPreview)
        XCTAssertNil(artifact.propertyListPreview)
        XCTAssertNil(artifact.sqlitePreview)
        XCTAssertNil(artifact.webAssemblyPreview)
        XCTAssertNil(artifact.fontPreview)

        let executable = directory.appendingPathComponent("quill.exe")
        try peFixture(machine: 0x8664).write(to: executable)
        let pePreview = try XCTUnwrap(ToolArtifactState(value: executable.path).executablePreview)
        XCTAssertEqual(pePreview.formatLabel, "PE")
        XCTAssertEqual(pePreview.architectureLabel, "x86_64")
        XCTAssertEqual(pePreview.bitnessLabel, "64-bit")

        let dylib = directory.appendingPathComponent("QuillCode.dylib")
        try machOFixture(magicBytes: [0xCF, 0xFA, 0xED, 0xFE], cpuType: 0x0100000C).write(to: dylib)
        let machOPreview = try XCTUnwrap(ToolArtifactState(value: dylib.path).executablePreview)
        XCTAssertEqual(machOPreview.formatLabel, "Mach-O")
        XCTAssertEqual(machOPreview.architectureLabel, "ARM64")

        let corruptBinary = directory.appendingPathComponent("corrupt.so")
        try Data(repeating: 0, count: 128).write(to: corruptBinary)
        XCTAssertNil(ToolArtifactState(value: corruptBinary.path).executablePreview)

        let remoteBinary = ToolArtifactState(value: "https://example.com/tool.exe")
        XCTAssertNil(remoteBinary.executablePreview)
    }

    private func elfFixture(machine: UInt16, bitness: UInt8, littleEndian: Bool) -> Data {
        var data = Data(repeating: 0, count: 64)
        data[0] = 0x7F
        data[1] = 0x45
        data[2] = 0x4C
        data[3] = 0x46
        data[4] = bitness
        data[5] = littleEndian ? 1 : 2
        if littleEndian {
            data[18] = UInt8(machine & 0xFF)
            data[19] = UInt8((machine >> 8) & 0xFF)
        } else {
            data[18] = UInt8((machine >> 8) & 0xFF)
            data[19] = UInt8(machine & 0xFF)
        }
        return data
    }

    private func peFixture(machine: UInt16) -> Data {
        var data = Data(repeating: 0, count: 128)
        data[0] = 0x4D
        data[1] = 0x5A
        data[60] = 0x40
        data[64] = 0x50
        data[65] = 0x45
        data[66] = 0
        data[67] = 0
        data[68] = UInt8(machine & 0xFF)
        data[69] = UInt8((machine >> 8) & 0xFF)
        return data
    }

    private func machOFixture(magicBytes: [UInt8], cpuType: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: magicBytes)
        data.append(UInt8(cpuType & 0xFF))
        data.append(UInt8((cpuType >> 8) & 0xFF))
        data.append(UInt8((cpuType >> 16) & 0xFF))
        data.append(UInt8((cpuType >> 24) & 0xFF))
        return data
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

        let packageEntries = [
            "META-INF/MANIFEST.MF",
            "com/example/App.class",
            "assets/config.json"
        ]
        for (extensionLabel, formatLabel) in [
            ("jar", "JAR"),
            ("war", "WAR"),
            ("ear", "EAR"),
            ("apk", "APK"),
            ("ipa", "IPA"),
            ("epub", "EPUB"),
            ("whl", "WHL"),
            ("vsix", "VSIX"),
            ("xpi", "XPI"),
            ("nupkg", "NUPKG")
        ] {
            let packageArchive = directory.appendingPathComponent("bundle.\(extensionLabel)")
            let packageBytes = OfficePackageFixture.zipPackage(fileNames: packageEntries)
            try packageBytes.write(to: packageArchive)
            let packageByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: packageBytes.count))
            let packageArtifact = ToolArtifactState(value: packageArchive.path)
            let packageDocumentPreview = try XCTUnwrap(packageArtifact.documentPreview)
            let packageArchivePreview = try XCTUnwrap(packageArtifact.archivePreview)

            XCTAssertEqual(packageDocumentPreview.kind, .archive)
            XCTAssertEqual(packageDocumentPreview.extensionLabel, formatLabel)
            XCTAssertEqual(packageArchivePreview.formatLabel, formatLabel)
            XCTAssertEqual(packageArchivePreview.entryCount, 3)
            XCTAssertEqual(packageArchivePreview.topLevelCount, 3)
            XCTAssertEqual(packageArchivePreview.entryPreviewLabels, packageEntries)
            XCTAssertEqual(packageArchivePreview.byteSizeLabel, packageByteSize)
            XCTAssertEqual(packageArchivePreview.metadataLines, [
                "Format: \(formatLabel)",
                "3 entries",
                "3 top-level items",
                "Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json",
                "Size: \(packageByteSize)"
            ])
        }

        let sevenZipArchive = directory.appendingPathComponent("sources.7z")
        let sevenZipBytes = Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0x00, 0x00])
        try sevenZipBytes.write(to: sevenZipArchive)
        let sevenZipByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: sevenZipBytes.count))

        let sevenZipPreview = try XCTUnwrap(ToolArtifactState(value: sevenZipArchive.path).archivePreview)
        XCTAssertEqual(sevenZipPreview.formatLabel, "7Z")
        XCTAssertNil(sevenZipPreview.entryCount)
        XCTAssertNil(sevenZipPreview.topLevelCount)
        XCTAssertNil(sevenZipPreview.entryPreviewLabel)
        XCTAssertTrue(sevenZipPreview.entryPreviewLabels.isEmpty)
        XCTAssertEqual(sevenZipPreview.byteSizeLabel, sevenZipByteSize)
        XCTAssertEqual(sevenZipPreview.metadataLines, [
            "Format: 7Z",
            "Size: \(sevenZipByteSize)"
        ])

        let rarArchive = directory.appendingPathComponent("sources.rar")
        let rarBytes = Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00, 0x00, 0x00])
        try rarBytes.write(to: rarArchive)
        let rarByteSize = try XCTUnwrap(ToolArtifactByteSizeFormatter.label(for: rarBytes.count))

        let rarPreview = try XCTUnwrap(ToolArtifactState(value: rarArchive.path).archivePreview)
        XCTAssertEqual(rarPreview.formatLabel, "RAR")
        XCTAssertNil(rarPreview.entryCount)
        XCTAssertNil(rarPreview.topLevelCount)
        XCTAssertNil(rarPreview.entryPreviewLabel)
        XCTAssertTrue(rarPreview.entryPreviewLabels.isEmpty)
        XCTAssertEqual(rarPreview.byteSizeLabel, rarByteSize)
        XCTAssertEqual(rarPreview.metadataLines, [
            "Format: RAR",
            "Size: \(rarByteSize)"
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
        try assertSourcePreview(
            filename: "package.json",
            contents: "{\n  \"name\": \"quillcode\"\n}\n",
            typeLabel: "npm package",
            lineCountLabel: "3 lines"
        )
        try assertSourcePreview(
            filename: "tsconfig.json",
            contents: "{\n  \"compilerOptions\": {}\n}\n",
            typeLabel: "TypeScript config",
            lineCountLabel: "3 lines"
        )
        try assertSourcePreview(
            filename: "Cargo.toml",
            contents: "[package]\nname = \"quillcode\"\n",
            typeLabel: "Cargo manifest",
            lineCountLabel: "2 lines"
        )
        try assertSourcePreview(
            filename: "requirements.txt",
            contents: "pytest==8.0.0\nplaywright==1.54.0\n",
            typeLabel: "Python requirements",
            lineCountLabel: "2 lines"
        )
        try assertSourcePreview(
            filename: ".dockerignore",
            contents: ".build\nDerivedData\n",
            typeLabel: "Docker ignore",
            lineCountLabel: "2 lines"
        )
        try assertSourcePreview(
            filename: "CMakeLists.txt",
            contents: "cmake_minimum_required(VERSION 3.27)\nproject(QuillCode)\n",
            typeLabel: "CMake",
            lineCountLabel: "2 lines"
        )
        try assertSourcePreview(
            filename: "Justfile",
            contents: "test:\n    swift test\n",
            typeLabel: "Justfile",
            lineCountLabel: "2 lines"
        )
        try assertSourcePreview(
            filename: "WORKSPACE",
            contents: "workspace(name = \"quillcode\")\n",
            typeLabel: "Bazel workspace",
            lineCountLabel: "1 line"
        )
        try assertSourcePreview(
            filename: "flake.nix",
            contents: "{ description = \"QuillCode\"; }\n",
            typeLabel: "Nix flake",
            lineCountLabel: "1 line"
        )
        try assertSourcePreview(
            filename: "pnpm-lock.yaml",
            contents: "lockfileVersion: '9.0'\n",
            typeLabel: "pnpm lockfile",
            lineCountLabel: "1 line"
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
