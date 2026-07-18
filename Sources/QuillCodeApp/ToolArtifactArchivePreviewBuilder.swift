import Foundation

enum ToolArtifactArchivePreviewBuilder {
    static func archivePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactArchivePreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .archive,
              documentPreview.extensionLabel.lowercased() == "zip",
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

            let preview = ToolArtifactArchivePreview(
                formatLabel: "ZIP",
                entryCount: directory.fileNames.count,
                topLevelCount: topLevelCount(in: directory.fileNames),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func topLevelCount(in fileNames: [String]) -> Int? {
        let names = Set(fileNames.compactMap { fileName -> String? in
            let trimmed = fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.split(separator: "/").first.map(String.init)
        })
        return names.isEmpty ? nil : names.count
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
