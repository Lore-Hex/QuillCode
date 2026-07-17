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
        try pngHeader(width: 1280, height: 720).write(to: pngFile)

        let imageFile = ToolArtifactState(value: pngFile.path)

        XCTAssertEqual(imageFile.imagePreview?.dimensionsLabel, "1280 x 720 px")
        XCTAssertEqual(imageFile.imagePreview?.typeLine, "Image · PNG · 1280 x 720 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: gifHeader(width: 320, height: 240))?.label, "320 x 240 px")
        XCTAssertEqual(ToolArtifactImageMetadataReader.dimensions(from: jpegHeader(width: 640, height: 480))?.label, "640 x 480 px")

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

        let textFile = ToolArtifactState(value: "/tmp/quillcode/notes.md", textPreview: "# Notes\n")
        XCTAssertFalse(textFile.isDocumentPreview)
        XCTAssertTrue(textFile.hasTextPreview)
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

    private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
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
