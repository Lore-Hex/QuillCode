import Foundation

enum XZArchiveFixture {
    static func xzArchive(payload: Data = Data("compressed xz payload".utf8)) -> Data {
        var data = Data([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00])
        data.append(payload)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x59, 0x5a])
        return data
    }
}
