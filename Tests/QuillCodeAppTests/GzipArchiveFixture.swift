import Foundation

enum GzipArchiveFixture {
    static func gzipArchive(originalName: String, compressedBytes: Data, uncompressedByteCount: UInt32) -> Data {
        var data = Data([
            0x1f, 0x8b,
            0x08,
            0x08,
            0x00, 0x00, 0x00, 0x00,
            0x00,
            0xff
        ])
        data.append(contentsOf: originalName.utf8)
        data.append(0x00)
        data.append(compressedBytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(UInt8(uncompressedByteCount & 0xff))
        data.append(UInt8((uncompressedByteCount >> 8) & 0xff))
        data.append(UInt8((uncompressedByteCount >> 16) & 0xff))
        data.append(UInt8((uncompressedByteCount >> 24) & 0xff))
        return data
    }
}
