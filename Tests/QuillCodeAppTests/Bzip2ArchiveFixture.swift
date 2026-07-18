import Foundation

enum Bzip2ArchiveFixture {
    static func bzip2Archive(payload: Data = Data("compressed bzip2 payload".utf8)) -> Data {
        var data = Data([0x42, 0x5a, 0x68, 0x39])
        data.append(payload)
        return data
    }
}
