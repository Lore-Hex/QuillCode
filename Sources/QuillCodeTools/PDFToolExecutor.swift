import CoreGraphics
import CoreText
import Foundation
import PDFKit
import QuillCodeCore

public struct PDFToolExecutor: @unchecked Sendable {
    public var workspaceRoot: URL
    public let accessScope: HostToolAccessScope
    public var editGuard: FileEditSessionGuard?

    private var pathResolver: FileWorkspacePathResolver {
        FileWorkspacePathResolver(workspaceRoot: workspaceRoot, accessScope: accessScope)
    }

    public init(
        workspaceRoot: URL,
        accessScope: HostToolAccessScope = .workspaceOnly,
        editGuard: FileEditSessionGuard? = nil
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.accessScope = accessScope
        self.editGuard = editGuard
    }

    public func merge(
        inputs: [String],
        output: String,
        labels: [String]? = nil,
        title: String? = nil,
        includeTableOfContents: Bool = true
    ) -> ToolResult {
        do {
            guard !inputs.isEmpty else {
                return ToolResult(ok: false, error: "PDF merge requires at least one input path.")
            }
            guard inputs.count <= 500 else {
                return ToolResult(ok: false, error: "PDF merge accepts at most 500 input files.")
            }
            if let labels, labels.count != inputs.count {
                return ToolResult(ok: false, error: "PDF merge labels must match inputs one-for-one.")
            }

            let outputURL = try pathResolver.resolve(output)
            guard outputURL.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
                return ToolResult(ok: false, error: "PDF merge output must use a .pdf extension.")
            }
            let inputURLs = try inputs.map(pathResolver.resolve)
            guard !inputURLs.contains(where: { $0.standardizedFileURL == outputURL.standardizedFileURL }) else {
                return ToolResult(ok: false, error: "PDF merge output cannot also be an input.")
            }

            let resolvedLabels = labels ?? inputURLs.map { $0.deletingPathExtension().lastPathComponent }
            let operation = {
                try performMerge(
                    inputURLs: inputURLs,
                    outputURL: outputURL,
                    labels: resolvedLabels,
                    title: title,
                    includeTableOfContents: includeTableOfContents
                )
            }
            let result: MergeResult
            if let editGuard {
                result = try editGuard.withExclusiveAccess(to: [outputURL]) {
                    if FileManager.default.fileExists(atPath: outputURL.path), !editGuard.hasRead(outputURL) {
                        throw FileEditGuardError.writeWithoutRead(output)
                    }
                    let value = try operation()
                    editGuard.markWritten(outputURL)
                    return value
                }
            } else {
                result = try operation()
            }

            let contentsStatus = includeTableOfContents ? "included" : "omitted"
            let summary = [
                "Merged \(inputs.count) PDFs into \(pathResolver.relativePath(for: outputURL)).",
                "Pages: \(result.pageCount); bookmarks: \(resolvedLabels.count); "
                    + "table of contents: \(contentsStatus).",
            ].joined(separator: "\n") + "\n"
            return ToolResult(
                ok: true,
                stdout: summary,
                artifacts: inputURLs.map(\.path) + [outputURL.path]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func performMerge(
        inputURLs: [URL],
        outputURL: URL,
        labels: [String],
        title: String?,
        includeTableOfContents: Bool
    ) throws -> MergeResult {
        var sources: [(document: PDFDocument, pageCount: Int)] = []
        for inputURL in inputURLs {
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw PDFToolError.missingInput(pathResolver.relativePath(for: inputURL))
            }
            guard let document = PDFDocument(url: inputURL), document.pageCount > 0 else {
                throw PDFToolError.invalidInput(pathResolver.relativePath(for: inputURL))
            }
            sources.append((document, document.pageCount))
        }

        let merged = PDFDocument()
        if includeTableOfContents,
           let page = Self.tableOfContentsPage(
               title: title ?? "Table of Contents",
               labels: labels,
               pageCounts: sources.map(\.pageCount)
           ) {
            merged.insert(page, at: 0)
        }

        var firstPageIndexes: [Int] = []
        for source in sources {
            firstPageIndexes.append(merged.pageCount)
            for index in 0..<source.pageCount {
                guard let page = source.document.page(at: index) else {
                    throw PDFToolError.invalidInput("page \(index + 1)")
                }
                merged.insert(page, at: merged.pageCount)
            }
        }

        let outlineRoot = PDFOutline()
        outlineRoot.label = title ?? outputURL.deletingPathExtension().lastPathComponent
        for (index, label) in labels.enumerated() {
            guard let page = merged.page(at: firstPageIndexes[index]) else { continue }
            let item = PDFOutline()
            item.label = label
            item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))
            outlineRoot.insertChild(item, at: outlineRoot.numberOfChildren)
        }
        merged.outlineRoot = outlineRoot
        merged.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: title ?? outputURL.deletingPathExtension().lastPathComponent,
            PDFDocumentAttribute.creatorAttribute: "Quill Cowork",
        ]

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard merged.write(to: outputURL) else {
            throw PDFToolError.cannotWrite(pathResolver.relativePath(for: outputURL))
        }
        guard let verification = PDFDocument(url: outputURL),
              verification.pageCount == merged.pageCount,
              verification.outlineRoot?.numberOfChildren == labels.count
        else {
            try? FileManager.default.removeItem(at: outputURL)
            throw PDFToolError.verificationFailed(pathResolver.relativePath(for: outputURL))
        }
        return MergeResult(pageCount: verification.pageCount)
    }

    private static func tableOfContentsPage(
        title: String,
        labels: [String],
        pageCounts: [Int]
    ) -> PDFPage? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 54
        var lines = title == "Table of Contents"
            ? [title, ""]
            : [title, "Table of Contents", ""]
        var pageNumber = 2
        for (index, label) in labels.enumerated() {
            lines.append("\(index + 1). \(label) .... \(pageNumber)")
            pageNumber += pageCounts[index]
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        context.beginPDFPage(nil)

        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 22, nil)
        let attributed = NSMutableAttributedString(string: lines.joined(separator: "\n"))
        attributed.addAttribute(
            NSAttributedString.Key(kCTFontAttributeName as String),
            value: bodyFont,
            range: NSRange(location: 0, length: attributed.length)
        )
        attributed.addAttribute(
            NSAttributedString.Key(kCTFontAttributeName as String),
            value: titleFont,
            range: NSRange(location: 0, length: min(title.utf16.count, attributed.length))
        )
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        path.addRect(CGRect(
            x: margin,
            y: margin,
            width: pageWidth - 2 * margin,
            height: pageHeight - 2 * margin
        ))
        let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }
}

private struct MergeResult {
    var pageCount: Int
}

private enum PDFToolError: Error, CustomStringConvertible {
    case cannotWrite(String)
    case invalidInput(String)
    case missingInput(String)
    case verificationFailed(String)

    var description: String {
        switch self {
        case .cannotWrite(let path): "Could not write merged PDF: \(path)"
        case .invalidInput(let path): "Input is not a readable PDF: \(path)"
        case .missingInput(let path): "PDF input not found: \(path)"
        case .verificationFailed(let path): "Merged PDF failed page or bookmark verification: \(path)"
        }
    }
}
