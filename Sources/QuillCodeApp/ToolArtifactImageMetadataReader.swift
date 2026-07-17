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
            ?? tiffDimensions(from: data)
            ?? bmpDimensions(from: data)
            ?? webpDimensions(from: data)
            ?? svgDimensions(from: data)
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

    private static func tiffDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        guard data.count >= 10 else { return nil }
        let byteOrder: TIFFByteOrder
        if data[0] == 0x49, data[1] == 0x49 {
            byteOrder = .littleEndian
        } else if data[0] == 0x4D, data[1] == 0x4D {
            byteOrder = .bigEndian
        } else {
            return nil
        }
        guard tiffUInt16(data, at: 2, byteOrder: byteOrder) == 42 else {
            return nil
        }

        let firstIFDOffset = Int(tiffUInt32(data, at: 4, byteOrder: byteOrder))
        guard firstIFDOffset >= 8, firstIFDOffset + 2 <= data.count else {
            return nil
        }
        let entryCount = Int(tiffUInt16(data, at: firstIFDOffset, byteOrder: byteOrder))
        guard entryCount <= 1024 else { return nil }

        var width: UInt32?
        var height: UInt32?
        for entryIndex in 0..<entryCount {
            let entryOffset = firstIFDOffset + 2 + entryIndex * 12
            guard entryOffset + 12 <= data.count else { return nil }
            let tag = tiffUInt16(data, at: entryOffset, byteOrder: byteOrder)
            guard tag == 256 || tag == 257 else { continue }
            guard let value = tiffScalarValue(data, at: entryOffset, byteOrder: byteOrder) else {
                continue
            }
            if tag == 256 {
                width = value
            } else {
                height = value
            }
            if let width, let height {
                return dimensions(width: width, height: height)
            }
        }
        return nil
    }

    private static func tiffScalarValue(_ data: Data, at entryOffset: Int, byteOrder: TIFFByteOrder) -> UInt32? {
        let fieldType = tiffUInt16(data, at: entryOffset + 2, byteOrder: byteOrder)
        let valueCount = tiffUInt32(data, at: entryOffset + 4, byteOrder: byteOrder)
        guard valueCount == 1 else { return nil }
        switch fieldType {
        case 3:
            return UInt32(tiffUInt16(data, at: entryOffset + 8, byteOrder: byteOrder))
        case 4:
            return tiffUInt32(data, at: entryOffset + 8, byteOrder: byteOrder)
        default:
            return nil
        }
    }

    private static func bmpDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        guard data.count >= 26,
              data[0] == 0x42,
              data[1] == 0x4D
        else {
            return nil
        }

        let dibHeaderSize = littleEndianUInt32(data, at: 14)
        if dibHeaderSize == 12, data.count >= 26 {
            return dimensions(width: littleEndianUInt16(data, at: 18), height: littleEndianUInt16(data, at: 20))
        }

        guard dibHeaderSize >= 40, data.count >= 26 else {
            return nil
        }
        let width = littleEndianInt32(data, at: 18)
        let height = littleEndianInt32(data, at: 22)
        guard width > 0, height != 0 else { return nil }
        return dimensions(width: UInt32(width), height: UInt32(abs(Int64(height))))
    }

    private static func webpDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        guard data.count >= 20,
              asciiString(data, at: 0, length: 4) == "RIFF",
              asciiString(data, at: 8, length: 4) == "WEBP"
        else {
            return nil
        }

        var offset = 12
        while offset + 8 <= data.count {
            let chunkType = asciiString(data, at: offset, length: 4)
            let chunkSize = Int(littleEndianUInt32(data, at: offset + 4))
            let payloadOffset = offset + 8
            guard payloadOffset <= data.count else { return nil }

            switch chunkType {
            case "VP8X":
                guard chunkSize >= 10, payloadOffset + 10 <= data.count else { return nil }
                let width = littleEndianUInt24(data, at: payloadOffset + 4) + 1
                let height = littleEndianUInt24(data, at: payloadOffset + 7) + 1
                return dimensions(width: width, height: height)
            case "VP8L":
                guard chunkSize >= 5, payloadOffset + 5 <= data.count, data[payloadOffset] == 0x2F else {
                    return nil
                }
                let b0 = UInt32(data[payloadOffset + 1])
                let b1 = UInt32(data[payloadOffset + 2])
                let b2 = UInt32(data[payloadOffset + 3])
                let b3 = UInt32(data[payloadOffset + 4])
                let width = 1 + b0 + ((b1 & 0x3F) << 8)
                let height = 1 + ((b1 & 0xC0) >> 6) + (b2 << 2) + ((b3 & 0x0F) << 10)
                return dimensions(width: width, height: height)
            case "VP8 ":
                guard chunkSize >= 10,
                      payloadOffset + 10 <= data.count,
                      data[payloadOffset + 3] == 0x9D,
                      data[payloadOffset + 4] == 0x01,
                      data[payloadOffset + 5] == 0x2A
                else {
                    return nil
                }
                let width = UInt32(littleEndianUInt16(data, at: payloadOffset + 6) & 0x3FFF)
                let height = UInt32(littleEndianUInt16(data, at: payloadOffset + 8) & 0x3FFF)
                return dimensions(width: width, height: height)
            default:
                let paddedSize = chunkSize + (chunkSize % 2)
                guard paddedSize >= chunkSize, payloadOffset + paddedSize > offset else { return nil }
                offset = payloadOffset + paddedSize
            }
        }
        return nil
    }

    private static func svgDimensions(from data: Data) -> ToolArtifactImageDimensions? {
        guard let text = String(data: data, encoding: .utf8),
              let svgStart = text.range(of: "<svg", options: [.caseInsensitive])
        else {
            return nil
        }
        let searchText = String(text[svgStart.lowerBound...].prefix(4096))
        guard let tagEnd = searchText.firstIndex(of: ">") else {
            return nil
        }
        let svgTag = String(searchText[..<tagEnd])
        if let width = svgLengthAttribute("width", in: svgTag),
           let height = svgLengthAttribute("height", in: svgTag) {
            return dimensions(width: UInt32(width), height: UInt32(height))
        }
        guard let viewBox = svgAttribute("viewBox", in: svgTag) ?? svgAttribute("viewbox", in: svgTag) else {
            return nil
        }
        let values = viewBox
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        return roundedDimensions(width: values[2], height: values[3])
    }

    private static func svgLengthAttribute(_ name: String, in text: String) -> Int? {
        guard let value = svgAttribute(name, in: text) else { return nil }
        let numericPrefix = value.prefix { character in
            character.isNumber || character == "."
        }
        guard let doubleValue = Double(numericPrefix), doubleValue > 0 else {
            return nil
        }
        return Int(doubleValue.rounded())
    }

    private static func svgAttribute(_ name: String, in text: String) -> String? {
        let quotedPattern = #"\#(name)\s*=\s*["']([^"']+)["']"#
        if let value = firstRegexCapture(pattern: quotedPattern, in: text) {
            return value
        }
        return firstRegexCapture(pattern: #"\#(name)\s*=\s*([^\s>]+)"#, in: text)
    }

    private static func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func dimensions(width: UInt32, height: UInt32) -> ToolArtifactImageDimensions? {
        guard width > 0, height > 0 else { return nil }
        return ToolArtifactImageDimensions(width: Int(width), height: Int(height))
    }

    private static func roundedDimensions(width: Double, height: Double) -> ToolArtifactImageDimensions? {
        guard width > 0, height > 0 else { return nil }
        return ToolArtifactImageDimensions(width: Int(width.rounded()), height: Int(height.rounded()))
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

    private static func littleEndianUInt24(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func littleEndianInt32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: littleEndianUInt32(data, at: offset))
    }

    private static func tiffUInt16(_ data: Data, at offset: Int, byteOrder: TIFFByteOrder) -> UInt16 {
        switch byteOrder {
        case .littleEndian:
            return UInt16(littleEndianUInt16(data, at: offset))
        case .bigEndian:
            return bigEndianUInt16(data, at: offset)
        }
    }

    private static func tiffUInt32(_ data: Data, at offset: Int, byteOrder: TIFFByteOrder) -> UInt32 {
        switch byteOrder {
        case .littleEndian:
            return littleEndianUInt32(data, at: offset)
        case .bigEndian:
            return bigEndianUInt32(data, at: offset)
        }
    }

    private static func asciiString(_ data: Data, at offset: Int, length: Int) -> String? {
        guard offset >= 0, length >= 0, offset + length <= data.count else {
            return nil
        }
        return String(bytes: data[offset..<offset + length], encoding: .ascii)
    }

    private enum TIFFByteOrder {
        case littleEndian
        case bigEndian
    }
}
