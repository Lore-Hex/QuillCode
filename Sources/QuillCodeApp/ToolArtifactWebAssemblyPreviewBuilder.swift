import Foundation

enum ToolArtifactWebAssemblyPreviewBuilder {
    static func webAssemblyPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactWebAssemblyPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "wasm",
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
                  header.prefix(wasmMagic.count) == wasmMagic
            else {
                return nil
            }

            return ToolArtifactWebAssemblyPreview(
                version: wasmVersion(from: header),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func wasmVersion(from header: Data) -> UInt32? {
        guard header.count >= headerSize else { return nil }
        return UInt32(header[4])
            | UInt32(header[5]) << 8
            | UInt32(header[6]) << 16
            | UInt32(header[7]) << 24
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

    private static let headerSize = 8
    private static let wasmMagic = Data([0x00, 0x61, 0x73, 0x6D])
}
