import Foundation

enum ZstandardArchiveFixture {
    static func zstandardArchive(payload: Data = Data("compressed zstd payload".utf8)) -> Data {
        var data = Data([0x28, 0xb5, 0x2f, 0xfd])
        data.append(payload)
        return data
    }
}
