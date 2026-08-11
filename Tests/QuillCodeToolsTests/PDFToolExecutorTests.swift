import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeTools
#if canImport(AppKit) && canImport(CoreGraphics) && canImport(CoreText) && canImport(PDFKit)
import AppKit
import CoreGraphics
import CoreText
import PDFKit
#endif

final class PDFToolExecutorTests: XCTestCase {
    #if canImport(AppKit) && canImport(CoreGraphics) && canImport(CoreText) && canImport(PDFKit)
    func testMergeCreatesOrderedPagesContentsAndBookmarks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePDF(text: "First source", to: root.appendingPathComponent("first.pdf"))
        try writePDF(text: "Second source", to: root.appendingPathComponent("second.pdf"))
        let result = PDFToolExecutor(workspaceRoot: root).merge(
            inputs: ["first.pdf", "second.pdf"],
            output: "merged.pdf",
            labels: ["Opening", "Appendix"],
            title: "Board packet"
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        let merged = try XCTUnwrap(PDFDocument(url: root.appendingPathComponent("merged.pdf")))
        XCTAssertEqual(merged.pageCount, 3)
        XCTAssertEqual(merged.outlineRoot?.numberOfChildren, 2)
        XCTAssertEqual(merged.outlineRoot?.child(at: 0)?.label, "Opening")
        XCTAssertEqual(merged.outlineRoot?.child(at: 1)?.label, "Appendix")
        XCTAssertTrue(
            merged.page(at: 0)?.string?.contains("Table of Contents") == true,
            "contents text: \(merged.page(at: 0)?.string ?? "<none>")"
        )
        XCTAssertTrue(
            merged.page(at: 1)?.string?.contains("First source") == true,
            "first-page text: \(merged.page(at: 1)?.string ?? "<none>")"
        )
        XCTAssertTrue(
            merged.page(at: 2)?.string?.contains("Second source") == true,
            "second-page text: \(merged.page(at: 2)?.string ?? "<none>")"
        )
    }

    func testMergeRejectsLabelCountMismatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePDF(text: "Source", to: root.appendingPathComponent("source.pdf"))

        let result = PDFToolExecutor(workspaceRoot: root).merge(
            inputs: ["source.pdf"],
            output: "merged.pdf",
            labels: ["One", "Two"]
        )

        XCTAssertFalse(result.ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("merged.pdf").path))
    }

    func testToolRouterPublishesAndDispatchesPDFMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePDF(text: "Source", to: root.appendingPathComponent("source.pdf"))

        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.pdfMerge.name))
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.pdfMerge.name,
            argumentsJSON: """
            {"inputs":["source.pdf"],"output":"merged.pdf","includeTableOfContents":false}
            """
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(PDFDocument(url: root.appendingPathComponent("merged.pdf"))?.pageCount, 1)
    }

    private func writePDF(text: String, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    CTFontCreateWithName("Helvetica" as CFString, 18, nil),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 54, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }
    #else
    func testUnavailableMergerIsNotPublished() throws {
        XCTAssertFalse(PDFToolExecutor.isAvailable)
        XCTAssertFalse(ToolRouter.definitions.map(\.name).contains(ToolDefinition.pdfMerge.name))

        let result = PDFToolExecutor(workspaceRoot: FileManager.default.temporaryDirectory).merge(
            inputs: ["source.pdf"],
            output: "merged.pdf"
        )
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "PDF merging is unavailable on this platform.")
    }
    #endif
}
