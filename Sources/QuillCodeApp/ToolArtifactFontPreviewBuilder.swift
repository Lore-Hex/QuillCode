import Foundation

enum ToolArtifactFontPreviewBuilder {
    static func fontPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactFontPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              fontExtensions.contains(documentPreview.extensionLabel.lowercased()),
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize >= minimumHeaderSize else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: headerReadLimit) ?? Data()
            guard header.count >= minimumHeaderSize else { return nil }

            return fontPreview(from: header, fileSize: fileSize)
        } catch {
            return nil
        }
    }

    private static func fontPreview(from header: Data, fileSize: Int) -> ToolArtifactFontPreview? {
        if header.starts(with: woffMagic) || header.starts(with: woff2Magic) {
            return webFontPreview(from: header, fileSize: fileSize)
        }
        return sfntFontPreview(from: header, fileSize: fileSize)
    }

    private static func sfntFontPreview(from header: Data, fileSize: Int) -> ToolArtifactFontPreview? {
        guard header.count >= 12 else { return nil }
        let signature = asciiString(in: header, range: 0..<4)
        let formatLabel: String
        let flavorLabel: String
        switch signature {
        case "\u{0000}\u{0001}\u{0000}\u{0000}":
            formatLabel = "TrueType"
            flavorLabel = "sfnt"
        case "OTTO":
            formatLabel = "OpenType"
            flavorLabel = "CFF"
        case "ttcf":
            formatLabel = "TrueType Collection"
            flavorLabel = "Collection"
        case "true":
            formatLabel = "TrueType"
            flavorLabel = "Classic Mac"
        case "typ1":
            formatLabel = "PostScript Type 1"
            flavorLabel = "Classic Mac"
        default:
            return nil
        }

        return ToolArtifactFontPreview(
            formatLabel: formatLabel,
            flavorLabel: flavorLabel,
            tableCount: unsignedBigEndian16(in: header, offset: 4),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func webFontPreview(from header: Data, fileSize: Int) -> ToolArtifactFontPreview? {
        guard header.count >= 16 else { return nil }
        let isWOFF2 = header.starts(with: woff2Magic)
        let flavor = flavorLabel(for: asciiString(in: header, range: 4..<8))
        return ToolArtifactFontPreview(
            formatLabel: isWOFF2 ? "WOFF2" : "WOFF",
            flavorLabel: flavor,
            tableCount: unsignedBigEndian16(in: header, offset: 12),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            declaredByteSizeLabel: unsignedBigEndian32(in: header, offset: 8)
                .flatMap { ToolArtifactByteSizeFormatter.label(for: Int($0)) }
        )
    }

    private static func flavorLabel(for signature: String) -> String? {
        switch signature {
        case "\u{0000}\u{0001}\u{0000}\u{0000}":
            return "TrueType"
        case "OTTO":
            return "OpenType CFF"
        case "true":
            return "Classic Mac TrueType"
        case "typ1":
            return "Classic Mac Type 1"
        default:
            return nil
        }
    }

    private static func asciiString(in data: Data, range: Range<Int>) -> String {
        String(bytes: data[range], encoding: .isoLatin1) ?? ""
    }

    private static func unsignedBigEndian16(in data: Data, offset: Int) -> Int? {
        guard data.count >= offset + 2 else { return nil }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    private static func unsignedBigEndian32(in data: Data, offset: Int) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        return UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
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

    private static let fontExtensions: Set<String> = ["otf", "ttc", "ttf", "woff", "woff2"]
    private static let minimumHeaderSize = 12
    private static let headerReadLimit = 16
    private static let woffMagic = Data("wOFF".utf8)
    private static let woff2Magic = Data("wOF2".utf8)
}
