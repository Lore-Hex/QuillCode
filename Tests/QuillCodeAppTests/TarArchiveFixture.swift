import Foundation

enum TarArchiveFixture {
    static func tarArchive(entries: [(name: String, contents: Data)]) -> Data {
        var data = Data()
        for entry in entries {
            let header = headerBlock(name: entry.name, size: entry.contents.count)
            data.append(header)
            data.append(entry.contents)
            let padding = (blockSize - (entry.contents.count % blockSize)) % blockSize
            if padding > 0 {
                data.append(Data(repeating: 0, count: padding))
            }
        }
        data.append(Data(repeating: 0, count: blockSize * 2))
        return data
    }

    private static func headerBlock(name: String, size: Int) -> Data {
        var header = Data(repeating: 0, count: blockSize)
        write(name, to: &header, at: 0, length: 100)
        write("0000644", to: &header, at: 100, length: 8)
        write("0000000", to: &header, at: 108, length: 8)
        write("0000000", to: &header, at: 116, length: 8)
        write(String(format: "%011o", size), to: &header, at: 124, length: 12)
        write("00000000000", to: &header, at: 136, length: 12)
        write("        ", to: &header, at: 148, length: 8)
        write("0", to: &header, at: 156, length: 1)
        write("ustar", to: &header, at: 257, length: 6)
        write("00", to: &header, at: 263, length: 2)

        let checksum = header.reduce(0) { $0 + Int($1) }
        write(String(format: "%06o", checksum) + "\0 ", to: &header, at: 148, length: 8)
        return header
    }

    private static func write(_ text: String, to data: inout Data, at offset: Int, length: Int) {
        let bytes = Array(text.utf8.prefix(length))
        for (index, byte) in bytes.enumerated() {
            data[offset + index] = byte
        }
    }

    private static let blockSize = 512
}
