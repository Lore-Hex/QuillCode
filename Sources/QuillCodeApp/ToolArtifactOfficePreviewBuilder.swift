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
                  let directory = try zipCentralDirectory(from: fileURL, fileSize: fileSize)
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

    private static func zipCentralDirectory(from fileURL: URL, fileSize: Int) throws -> ZipCentralDirectory? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let tailCount = min(fileSize, endOfCentralDirectorySearchLimit)
        try handle.seek(toOffset: UInt64(fileSize - tailCount))
        guard let tail = try handle.read(upToCount: tailCount),
              let end = endOfCentralDirectory(in: tail)
        else {
            return nil
        }

        guard end.diskNumber == 0,
              end.centralDirectoryDisk == 0,
              end.entriesOnDisk == end.totalEntries,
              end.totalEntries != UInt16.max,
              end.centralDirectorySize != UInt32.max,
              end.centralDirectoryOffset != UInt32.max,
              end.centralDirectorySize <= centralDirectoryByteLimit
        else {
            return nil
        }

        let directoryOffset = Int(end.centralDirectoryOffset)
        let directorySize = Int(end.centralDirectorySize)
        guard directoryOffset >= 0,
              directorySize >= 0,
              directoryOffset + directorySize <= fileSize
        else {
            return nil
        }

        try handle.seek(toOffset: UInt64(directoryOffset))
        guard let data = try handle.read(upToCount: directorySize),
              data.count == directorySize
        else {
            return nil
        }
        return centralDirectory(from: data)
    }

    private static func centralDirectory(from data: Data) -> ZipCentralDirectory? {
        var offset = 0
        var fileNames: [String] = []
        while offset + centralDirectoryHeaderLength <= data.count {
            guard littleEndianUInt32(data, at: offset) == centralDirectoryHeaderSignature else {
                return fileNames.isEmpty ? nil : ZipCentralDirectory(fileNames: fileNames)
            }
            let fileNameLength = Int(littleEndianUInt16(data, at: offset + 28))
            let extraLength = Int(littleEndianUInt16(data, at: offset + 30))
            let commentLength = Int(littleEndianUInt16(data, at: offset + 32))
            let fileNameStart = offset + centralDirectoryHeaderLength
            let fileNameEnd = fileNameStart + fileNameLength
            let nextOffset = fileNameEnd + extraLength + commentLength
            guard fileNameEnd <= data.count,
                  nextOffset <= data.count
            else {
                return nil
            }
            if let name = String(data: data[fileNameStart..<fileNameEnd], encoding: .utf8),
               !name.isEmpty {
                fileNames.append(name)
            }
            offset = nextOffset
        }
        return fileNames.isEmpty ? nil : ZipCentralDirectory(fileNames: fileNames)
    }

    private static func endOfCentralDirectory(in data: Data) -> EndOfCentralDirectory? {
        guard data.count >= endOfCentralDirectoryMinimumLength else { return nil }
        var offset = data.count - endOfCentralDirectoryMinimumLength
        while offset >= 0 {
            if littleEndianUInt32(data, at: offset) == endOfCentralDirectorySignature,
               offset + endOfCentralDirectoryMinimumLength <= data.count {
                return EndOfCentralDirectory(
                    diskNumber: littleEndianUInt16(data, at: offset + 4),
                    centralDirectoryDisk: littleEndianUInt16(data, at: offset + 6),
                    entriesOnDisk: littleEndianUInt16(data, at: offset + 8),
                    totalEntries: littleEndianUInt16(data, at: offset + 10),
                    centralDirectorySize: littleEndianUInt32(data, at: offset + 12),
                    centralDirectoryOffset: littleEndianUInt32(data, at: offset + 16)
                )
            }
            if offset == 0 { break }
            offset -= 1
        }
        return nil
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

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private struct ZipCentralDirectory {
        var fileNames: [String]
    }

    private struct EndOfCentralDirectory {
        var diskNumber: UInt16
        var centralDirectoryDisk: UInt16
        var entriesOnDisk: UInt16
        var totalEntries: UInt16
        var centralDirectorySize: UInt32
        var centralDirectoryOffset: UInt32
    }

    private static let fileSizeLimit = 50 * 1_024 * 1_024
    private static let centralDirectoryByteLimit: UInt32 = 1 * 1_024 * 1_024
    private static let endOfCentralDirectorySearchLimit = 66 * 1_024
    private static let endOfCentralDirectoryMinimumLength = 22
    private static let centralDirectoryHeaderLength = 46
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let centralDirectoryHeaderSignature: UInt32 = 0x0201_4B50
}
