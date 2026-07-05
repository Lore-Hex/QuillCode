import Foundation

struct ToolArtifactImageDimensions: Sendable, Hashable {
    var width: Int
    var height: Int

    var label: String {
        "\(width) x \(height) px"
    }
}

enum ToolArtifactImageMetadataReader {
    private static let maximumHeaderBytes = 64 * 1024

    static func dimensionsLabel(for value: String, kind: ToolArtifactKind) -> String? {
        dimensions(for: value, kind: kind)?.label
    }

    static func dimensions(for value: String, kind: ToolArtifactKind) -> ToolArtifactImageDimensions? {
        guard let url = localFileURL(for: value, kind: kind),
              let data = readHeaderData(from: url)
        else {
            return nil
        }
        return dimensions(from: data)
    }

    static func dimensions(from data: Data) -> ToolArtifactImageDimensions? {
        pngDimensions(from: data)
            ?? gifDimensions(from: data)
            ?? jpegDimensions(from: data)
    }

    private static func localFileURL(for value: String, kind: ToolArtifactKind) -> URL? {
        guard kind == .file else { return nil }
        if value.hasPrefix("file://") {
            guard let url = URL(string: value), url.isFileURL else { return nil }
            return url
        }
        guard value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value)
    }

    private static func readHeaderData(from url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? file.close() }
        let data = file.readData(ofLength: maximumHeaderBytes)
        return data.isEmpty ? nil : data
    }

    private static func pngDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24,
              data.starts(with: signature),
              data[12] == 0x49,
              data[13] == 0x48,
              data[14] == 0x44,
              data[15] == 0x52
        else {
            return nil
        }
        return dimensions(width: bigEndianUInt32(data, at: 16), height: bigEndianUInt32(data, at: 20))
    }

    private static func gifDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        guard data.count >= 10 else { return nil }
        let header = String(decoding: data.prefix(6), as: UTF8.self)
        guard header == "GIF87a" || header == "GIF89a" else { return nil }
        return dimensions(width: littleEndianUInt16(data, at: 6), height: littleEndianUInt16(data, at: 8))
    }

    private static func jpegDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        guard data.count >= 4, data[0] == 0xFF, data[1] == 0xD8 else {
            return nil
        }

        var index = 2
        while index + 8 < data.count {
            while index < data.count, data[index] != 0xFF {
                index += 1
            }
            while index < data.count, data[index] == 0xFF {
                index += 1
            }
            guard index < data.count else { return nil }

            let marker = data[index]
            index += 1
            if marker == 0xD9 || marker == 0xDA {
                return nil
            }
            guard index + 1 < data.count else { return nil }
            let segmentLength = Int(bigEndianUInt16(data, at: index))
            guard segmentLength >= 2, index + segmentLength <= data.count else {
                return nil
            }
            if isJPEGStartOfFrameMarker(marker), segmentLength >= 7 {
                let height = bigEndianUInt16(data, at: index + 3)
                let width = bigEndianUInt16(data, at: index + 5)
                return dimensions(width: UInt32(width), height: UInt32(height))
            }
            index += segmentLength
        }
        return nil
    }

    private static func isJPEGStartOfFrameMarker(_ marker: UInt8) -> Bool {
        switch marker {
        case 0xC0...0xC3, 0xC5...0xC7, 0xC9...0xCB, 0xCD...0xCF:
            return true
        default:
            return false
        }
    }

    private static func dimensions(width: UInt32, height: UInt32) -> ToolArtifactImageDimensions? {
        guard width > 0, height > 0 else { return nil }
        return ToolArtifactImageDimensions(width: Int(width), height: Int(height))
    }

    private static func bigEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func bigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
    }
}
