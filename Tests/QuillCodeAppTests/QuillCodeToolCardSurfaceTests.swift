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
        XCTAssertEqual(presentationPreview.metadataLines.dropFirst(2).first, "2 slides")

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
        XCTAssertEqual(compressedTarPreview.uncompressedByteSizeLabel, "8 KB")
        XCTAssertEqual(compressedTarPreview.byteSizeLabel, compressedTarByteSize)
        XCTAssertEqual(compressedTarPreview.metadataLines, [
            "Format: TAR.GZ",
            "Entries: logs.tar",
            "Uncompressed: 8 KB",
            "Size: \(compressedTarByteSize)"
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
