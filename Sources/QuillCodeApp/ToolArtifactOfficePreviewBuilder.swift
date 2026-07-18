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
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
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
}
