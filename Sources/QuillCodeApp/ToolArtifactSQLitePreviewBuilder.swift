import Foundation

enum ToolArtifactSQLitePreviewBuilder {
    static func sqlitePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSQLitePreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              sqliteExtensions.contains(documentPreview.extensionLabel.lowercased()),
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize >= headerSize else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: headerSize) ?? Data()
            guard header.count >= headerSize,
                  header.starts(with: sqliteHeaderMagic)
            else {
                return nil
            }

            return ToolArtifactSQLitePreview(
                pageSize: sqlitePageSize(from: header),
                pageCount: sqlitePageCount(from: header),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func sqlitePageSize(from header: Data) -> Int? {
        guard header.count >= 18 else { return nil }
        let value = Int(header[16]) << 8 | Int(header[17])
        return value == 1 ? 65_536 : (value > 0 ? value : nil)
    }

    private static func sqlitePageCount(from header: Data) -> Int? {
        guard header.count >= 32 else { return nil }
        let value = Int(header[28]) << 24
            | Int(header[29]) << 16
            | Int(header[30]) << 8
            | Int(header[31])
        return value > 0 ? value : nil
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

    private static let sqliteExtensions: Set<String> = ["db", "sqlite", "sqlite3"]
    private static let headerSize = 100
    private static let sqliteHeaderMagic = Data("SQLite format 3\u{0000}".utf8)
}
