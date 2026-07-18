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
            case "gz":
                preview = try gzipPreview(
                    from: fileURL,
                    fileSize: fileSize,
                    formatLabel: "GZIP",
                    includesSingleMemberCounts: true
                )
            case "tar.gz", "tgz":
                preview = try gzipPreview(
                    from: fileURL,
                    fileSize: fileSize,
                    formatLabel: documentPreview.extensionLabel.uppercased(),
                    includesSingleMemberCounts: false
                )
            case "xz":
                preview = try xzPreview(
                    from: fileURL,
                    fileSize: fileSize,
                    formatLabel: "XZ",
                    memberName: inferredXZMemberName(from: fileURL, extensionLabel: "xz"),
                    includesSingleMemberCounts: true
                )
            case "tar.xz", "txz":
                preview = try xzPreview(
                    from: fileURL,
                    fileSize: fileSize,
                    formatLabel: documentPreview.extensionLabel.uppercased(),
                    memberName: inferredXZMemberName(from: fileURL, extensionLabel: documentPreview.extensionLabel),
                    includesSingleMemberCounts: false
                )
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
            entryPreviewLabels: entryPreviewLabels(in: directory.fileNames),
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
            entryPreviewLabels: entryPreviewLabels(in: fileNames),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func gzipPreview(
        from fileURL: URL,
        fileSize: Int,
        formatLabel: String,
        includesSingleMemberCounts: Bool
    ) throws -> ToolArtifactArchivePreview? {
        guard fileSize >= gzipMinimumSize else { return nil }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let headerReadCount = min(fileSize, gzipHeaderReadLimit)
        guard let header = try handle.read(upToCount: headerReadCount),
              header.count >= gzipFixedHeaderSize,
              header[0] == gzipMagicByte0,
              header[1] == gzipMagicByte1,
              header[2] == gzipDeflateMethod
        else {
            return nil
        }

        let flags = header[3]
        guard flags & gzipReservedFlags == 0 else { return nil }

        let memberName = gzipOriginalFileName(from: header, flags: flags)
        try handle.seek(toOffset: UInt64(fileSize - gzipTrailerISizeLength))
        guard let trailer = try handle.read(upToCount: gzipTrailerISizeLength),
              trailer.count == gzipTrailerISizeLength
        else {
            return nil
        }

        let uncompressedSize = gzipLittleEndianUInt32(trailer)
        return ToolArtifactArchivePreview(
            formatLabel: formatLabel,
            entryCount: includesSingleMemberCounts ? 1 : nil,
            topLevelCount: includesSingleMemberCounts && memberName != nil ? 1 : nil,
            entryPreviewLabel: memberName,
            entryPreviewLabels: memberName.map { [$0] } ?? [],
            uncompressedByteSizeLabel: ToolArtifactByteSizeFormatter.label(for: Int(uncompressedSize)),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func xzPreview(
        from fileURL: URL,
        fileSize: Int,
        formatLabel: String,
        memberName: String?,
        includesSingleMemberCounts: Bool
    ) throws -> ToolArtifactArchivePreview? {
        guard fileSize >= xzMinimumSize else { return nil }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: xzHeaderMagic.count),
              Array(header) == xzHeaderMagic
        else {
            return nil
        }

        try handle.seek(toOffset: UInt64(fileSize - xzFooterMagic.count))
        guard let footer = try handle.read(upToCount: xzFooterMagic.count),
              Array(footer) == xzFooterMagic
        else {
            return nil
        }

        return ToolArtifactArchivePreview(
            formatLabel: formatLabel,
            entryCount: includesSingleMemberCounts ? 1 : nil,
            topLevelCount: includesSingleMemberCounts && memberName != nil ? 1 : nil,
            entryPreviewLabel: memberName,
            entryPreviewLabels: memberName.map { [$0] } ?? [],
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func entryPreviewLabel(in fileNames: [String]) -> String? {
        let previewNames = entryPreviewLabels(in: fileNames)
        guard !previewNames.isEmpty else { return nil }

        let remainingCount = max(fileNames.count - previewNames.count, 0)
        let previewText = previewNames.joined(separator: ", ")
        if remainingCount > 0 {
            return "\(previewText), +\(remainingCount) more"
        }
        return previewText
    }

    private static func entryPreviewLabels(in fileNames: [String]) -> [String] {
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
        return previewNames
    }

    private static func sanitizedEntryName(_ fileName: String) -> String {
        let singleLineName = fileName
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLineName.prefix(entryNameCharacterLimit))
    }

    private static func gzipOriginalFileName(from header: Data, flags: UInt8) -> String? {
        var offset = gzipFixedHeaderSize
        if flags & gzipExtraFieldFlag != 0 {
            guard offset + 2 <= header.count else { return nil }
            let extraLength = Int(header[offset]) | (Int(header[offset + 1]) << 8)
            offset += 2 + extraLength
            guard offset <= header.count else { return nil }
        }
        guard flags & gzipOriginalNameFlag != 0 else { return nil }

        var nameBytes: [UInt8] = []
        while offset < header.count {
            let byte = header[offset]
            offset += 1
            if byte == 0 {
                return sanitizedEntryName(String(decoding: nameBytes, as: UTF8.self))
            }
            nameBytes.append(byte)
            if nameBytes.count == entryNameCharacterLimit {
                break
            }
        }
        return nameBytes.isEmpty ? nil : sanitizedEntryName(String(decoding: nameBytes, as: UTF8.self))
    }

    private static func inferredXZMemberName(from fileURL: URL, extensionLabel: String) -> String? {
        let fileName = fileURL.lastPathComponent
        let lowercasedFileName = fileName.lowercased()
        let suffix: String
        switch extensionLabel.lowercased() {
        case "tar.xz":
            suffix = ".tar.xz"
        case "txz":
            suffix = ".txz"
        default:
            suffix = ".xz"
        }
        guard lowercasedFileName.hasSuffix(suffix),
              fileName.count > suffix.count
        else {
            return nil
        }
        let endIndex = fileName.index(fileName.endIndex, offsetBy: -suffix.count)
        let baseName = String(fileName[..<endIndex])
        let memberName = extensionLabel.lowercased() == "xz" ? baseName : "\(baseName).tar"
        return sanitizedEntryName(memberName)
    }

    private static func gzipLittleEndianUInt32(_ data: Data) -> UInt32 {
        UInt32(data[0])
            | (UInt32(data[1]) << 8)
            | (UInt32(data[2]) << 16)
            | (UInt32(data[3]) << 24)
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
    private static let gzipHeaderReadLimit = 64 * 1_024
    private static let gzipMinimumSize = 18
    private static let gzipFixedHeaderSize = 10
    private static let gzipTrailerISizeLength = 4
    private static let gzipMagicByte0: UInt8 = 0x1f
    private static let gzipMagicByte1: UInt8 = 0x8b
    private static let gzipDeflateMethod: UInt8 = 8
    private static let gzipExtraFieldFlag: UInt8 = 0x04
    private static let gzipOriginalNameFlag: UInt8 = 0x08
    private static let gzipReservedFlags: UInt8 = 0xe0
    private static let xzHeaderMagic: [UInt8] = [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]
    private static let xzFooterMagic: [UInt8] = [0x59, 0x5a]
    private static let xzMinimumSize = 12
}
