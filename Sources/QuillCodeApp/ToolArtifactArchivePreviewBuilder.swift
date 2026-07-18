import Foundation

enum ToolArtifactArchivePreviewBuilder {
    static func archivePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactArchivePreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .archive,
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize <= fileSizeLimit else { return nil }

            let preview: ToolArtifactArchivePreview?
            switch documentPreview.extensionLabel.lowercased() {
            case "zip":
                preview = try zipPreview(from: fileURL, fileSize: fileSize)
            case "tar":
                preview = try tarPreview(from: fileURL, fileSize: fileSize)
            default:
                preview = nil
            }
            guard let preview else { return nil }
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func zipPreview(from fileURL: URL, fileSize: Int) throws -> ToolArtifactArchivePreview? {
        guard let directory = try ToolArtifactZipCentralDirectoryReader.centralDirectory(
            from: fileURL,
            fileSize: fileSize
        ) else {
            return nil
        }
        return ToolArtifactArchivePreview(
            formatLabel: "ZIP",
            entryCount: directory.fileNames.count,
            topLevelCount: topLevelCount(in: directory.fileNames),
            entryPreviewLabel: entryPreviewLabel(in: directory.fileNames),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func tarPreview(from fileURL: URL, fileSize: Int) throws -> ToolArtifactArchivePreview? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset = 0
        var fileNames: [String] = []
        while offset + tarBlockSize <= fileSize,
              fileNames.count < tarEntryLimit {
            try handle.seek(toOffset: UInt64(offset))
            guard let header = try handle.read(upToCount: tarBlockSize),
                  header.count == tarBlockSize
            else {
                return nil
            }
            if isZeroBlock(header) {
                break
            }
            guard let fileName = tarFileName(from: header),
                  let size = tarFileSize(from: header)
            else {
                return nil
            }
            if !fileName.isEmpty {
                fileNames.append(fileName)
            }
            let payloadBlocks = (size + tarBlockSize - 1) / tarBlockSize
            let nextOffset = offset + tarBlockSize + payloadBlocks * tarBlockSize
            guard nextOffset > offset else { return nil }
            offset = nextOffset
        }

        guard !fileNames.isEmpty else { return nil }
        return ToolArtifactArchivePreview(
            formatLabel: "TAR",
            entryCount: fileNames.count,
            topLevelCount: topLevelCount(in: fileNames),
            entryPreviewLabel: entryPreviewLabel(in: fileNames),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func entryPreviewLabel(in fileNames: [String]) -> String? {
        var previewNames: [String] = []
        for fileName in fileNames {
            let previewName = sanitizedEntryName(fileName)
            if !previewName.isEmpty {
                previewNames.append(previewName)
            }
            if previewNames.count == entryPreviewLimit {
                break
            }
        }
        guard !previewNames.isEmpty else { return nil }

        let remainingCount = max(fileNames.count - previewNames.count, 0)
        let previewText = previewNames.joined(separator: ", ")
        if remainingCount > 0 {
            return "\(previewText), +\(remainingCount) more"
        }
        return previewText
    }

    private static func sanitizedEntryName(_ fileName: String) -> String {
        let singleLineName = fileName
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLineName.prefix(entryNameCharacterLimit))
    }

    private static func topLevelCount(in fileNames: [String]) -> Int? {
        let names = Set(fileNames.compactMap { fileName -> String? in
            let trimmed = fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.split(separator: "/").first.map(String.init)
        })
        return names.isEmpty ? nil : names.count
    }

    private static func isZeroBlock(_ data: Data) -> Bool {
        data.allSatisfy { $0 == 0 }
    }

    private static func tarFileName(from header: Data) -> String? {
        let name = tarString(in: header, range: 0..<100)
        let prefix = tarString(in: header, range: 345..<500)
        if let prefix, !prefix.isEmpty {
            return [prefix, name].compactMap { $0 }.joined(separator: "/")
        }
        return name
    }

    private static func tarFileSize(from header: Data) -> Int? {
        guard let sizeText = tarString(in: header, range: 124..<136)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !sizeText.isEmpty,
              let size = Int(sizeText, radix: 8),
              size >= 0
        else {
            return nil
        }
        return size
    }

    private static func tarString(in data: Data, range: Range<Int>) -> String? {
        guard range.lowerBound >= 0,
              range.upperBound <= data.count
        else {
            return nil
        }
        let bytes = data[range].prefix { $0 != 0 }
        guard !bytes.isEmpty else { return nil }
        return String(data: Data(bytes), encoding: .utf8)
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
    private static let tarBlockSize = 512
    private static let tarEntryLimit = 10_000
    private static let entryPreviewLimit = 3
    private static let entryNameCharacterLimit = 80
}
