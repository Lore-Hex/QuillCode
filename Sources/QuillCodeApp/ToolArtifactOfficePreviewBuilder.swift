import Foundation

enum ToolArtifactOfficePreviewBuilder {
    static func officePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactOfficePreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              let officeKind = officeKind(for: documentPreview.extensionLabel),
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize <= fileSizeLimit,
                  let directory = try ToolArtifactZipCentralDirectoryReader.centralDirectory(
                    from: fileURL,
                    fileSize: fileSize
                  )
            else {
                return nil
            }

            let preview = ToolArtifactOfficePreview(
                formatLabel: "Office Open XML",
                entryCount: directory.fileNames.count,
                worksheetCount: officeKind == .spreadsheet ? worksheetCount(in: directory.fileNames) : nil,
                slideCount: officeKind == .presentation ? slideCount(in: directory.fileNames) : nil,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
                contentPreviewLabels: contentPreviewLabels(in: directory.fileNames, officeKind: officeKind)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func worksheetCount(in fileNames: [String]) -> Int? {
        let count = fileNames.filter { fileName in
            fileName.hasPrefix("xl/worksheets/sheet")
                && fileName.hasSuffix(".xml")
                && !fileName.contains("/_rels/")
        }.count
        return count > 0 ? count : nil
    }

    private static func slideCount(in fileNames: [String]) -> Int? {
        let count = fileNames.filter { fileName in
            fileName.hasPrefix("ppt/slides/slide")
                && fileName.hasSuffix(".xml")
                && !fileName.contains("/_rels/")
        }.count
        return count > 0 ? count : nil
    }

    private static func contentPreviewLabels(
        in fileNames: [String],
        officeKind: ToolArtifactDocumentKind
    ) -> [String] {
        switch officeKind {
        case .document:
            return documentPreviewLabels(in: fileNames)
        case .spreadsheet:
            return numberedPreviewLabels(
                in: fileNames,
                prefix: "xl/worksheets/sheet",
                suffix: ".xml",
                label: "Sheet"
            )
        case .presentation:
            return numberedPreviewLabels(
                in: fileNames,
                prefix: "ppt/slides/slide",
                suffix: ".xml",
                label: "Slide"
            )
        default:
            return []
        }
    }

    private static func documentPreviewLabels(in fileNames: [String]) -> [String] {
        let orderedChecks: [(String, String)] = [
            ("word/document.xml", "Document body"),
            ("word/comments.xml", "Comments"),
            ("word/footnotes.xml", "Footnotes"),
            ("word/endnotes.xml", "Endnotes")
        ]
        var labels = orderedChecks.compactMap { path, label in
            fileNames.contains(path) ? label : nil
        }
        let headerCount = fileNames.filter { matchesNumberedEntry($0, prefix: "word/header", suffix: ".xml") }.count
        let footerCount = fileNames.filter { matchesNumberedEntry($0, prefix: "word/footer", suffix: ".xml") }.count
        if headerCount > 0 {
            labels.append("\(headerCount) header\(headerCount == 1 ? "" : "s")")
        }
        if footerCount > 0 {
            labels.append("\(footerCount) footer\(footerCount == 1 ? "" : "s")")
        }
        return Array(labels.prefix(contentPreviewLabelLimit))
    }

    private static func numberedPreviewLabels(
        in fileNames: [String],
        prefix: String,
        suffix: String,
        label: String
    ) -> [String] {
        fileNames
            .compactMap { fileName -> (Int, String)? in
                guard let number = numberedEntryIndex(fileName, prefix: prefix, suffix: suffix) else {
                    return nil
                }
                return (number, "\(label) \(number)")
            }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
            .prefix(contentPreviewLabelLimit)
            .map(\.1)
    }

    private static func matchesNumberedEntry(_ fileName: String, prefix: String, suffix: String) -> Bool {
        numberedEntryIndex(fileName, prefix: prefix, suffix: suffix) != nil
    }

    private static func numberedEntryIndex(_ fileName: String, prefix: String, suffix: String) -> Int? {
        guard fileName.hasPrefix(prefix),
              fileName.hasSuffix(suffix),
              !fileName.contains("/_rels/")
        else {
            return nil
        }
        let start = fileName.index(fileName.startIndex, offsetBy: prefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return Int(fileName[start..<end])
    }

    private static func officeKind(for extensionLabel: String) -> ToolArtifactDocumentKind? {
        switch extensionLabel.lowercased() {
        case "docx":
            return .document
        case "xlsx":
            return .spreadsheet
        case "pptx":
            return .presentation
        default:
            return nil
        }
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else {
            return nil
        }
        return url
    }

    private static let fileSizeLimit = 50 * 1_024 * 1_024
    private static let contentPreviewLabelLimit = 5
}
