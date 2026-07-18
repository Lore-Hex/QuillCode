import Foundation

enum ToolArtifactMediaPreviewBuilder {
    static func mediaPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactMediaPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .audio || documentPreview.kind == .video,
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize <= fileSizeLimit else { return nil }

            var title: String?
            var artist: String?
            if documentPreview.extensionLabel.lowercased() == "mp3" {
                let id3Metadata = try id3Metadata(from: fileURL, fileSize: fileSize)
                title = id3Metadata.title
                artist = id3Metadata.artist
            }

            let preview = ToolArtifactMediaPreview(
                kind: documentPreview.kind,
                formatLabel: documentPreview.extensionLabel.uppercased(),
                title: title,
                artist: artist,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
                playbackURL: fileURL.absoluteString
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func id3Metadata(from fileURL: URL, fileSize: Int) throws -> ID3Metadata {
        guard fileSize >= id3HeaderSize else { return ID3Metadata() }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let readLimit = min(fileSize, id3ReadLimit)
        guard let data = try handle.read(upToCount: readLimit),
              data.count >= id3HeaderSize,
              data[0] == CharacterByte.I,
              data[1] == CharacterByte.D,
              data[2] == CharacterByte.three
        else {
            return ID3Metadata()
        }

        let tagSize = id3SyncSafeInteger(data[6..<10])
        let tagEnd = min(data.count, id3HeaderSize + tagSize)
        let id3MajorVersion = Int(data[3])
        var offset = id3HeaderSize
        var metadata = ID3Metadata()

        while offset + id3FrameHeaderSize <= tagEnd {
            let frameIDData = data[offset..<(offset + 4)]
            guard let frameID = String(data: Data(frameIDData), encoding: .ascii),
                  frameID.range(of: #"^[A-Z0-9]{4}$"#, options: .regularExpression) != nil
            else {
                break
            }

            let frameSizeBytes = data[(offset + 4)..<(offset + 8)]
            let frameSize = id3MajorVersion == 4
                ? id3SyncSafeInteger(frameSizeBytes)
                : id3BigEndianInteger(frameSizeBytes)
            let payloadStart = offset + id3FrameHeaderSize
            let payloadEnd = payloadStart + frameSize
            guard payloadEnd <= tagEnd else { break }

            let payload = data[payloadStart..<payloadEnd]
            switch frameID {
            case "TIT2":
                metadata.title = id3TextFrame(payload)
            case "TPE1":
                metadata.artist = id3TextFrame(payload)
            default:
                break
            }

            offset = payloadEnd
        }

        return metadata
    }

    private static func id3TextFrame(_ payload: Data.SubSequence) -> String? {
        guard let encoding = payload.first else { return nil }
        let textBytes = payload.dropFirst()
        let text: String?
        switch encoding {
        case 0:
            text = String(data: Data(textBytes), encoding: .isoLatin1)
        case 1:
            text = String(data: Data(textBytes), encoding: .utf16)
        case 2:
            text = String(data: Data(textBytes), encoding: .utf16BigEndian)
        case 3:
            text = String(data: Data(textBytes), encoding: .utf8)
        default:
            text = nil
        }
        return text?
            .replacingOccurrences(of: "\u{0}", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefixString(characterLimit)
    }

    private static func id3SyncSafeInteger(_ bytes: Data.SubSequence) -> Int {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
    }

    private static func id3BigEndianInteger(_ bytes: Data.SubSequence) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
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

    private struct ID3Metadata {
        var title: String?
        var artist: String?
    }

    private enum CharacterByte {
        static let I = UInt8(0x49)
        static let D = UInt8(0x44)
        static let three = UInt8(0x33)
    }

    private static let fileSizeLimit = 50 * 1_024 * 1_024
    private static let id3ReadLimit = 128 * 1_024
    private static let id3HeaderSize = 10
    private static let id3FrameHeaderSize = 10
    private static let characterLimit = 120
}

private extension StringProtocol {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
