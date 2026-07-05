import Foundation

enum OfficePackageFixture {
    static func zipPackage(fileNames: [String]) -> Data {
        var data = Data()
        var centralDirectory = Data()
        var offsets: [UInt32] = []

        for fileName in fileNames {
            let nameBytes = Array(fileName.utf8)
            offsets.append(UInt32(data.count))

            data.appendUInt32LE(0x0403_4B50)
            data.appendUInt16LE(20)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(0)
            data.appendUInt32LE(0)
            data.appendUInt32LE(0)
            data.appendUInt16LE(UInt16(nameBytes.count))
            data.appendUInt16LE(0)
            data.append(contentsOf: nameBytes)
        }

        let centralDirectoryOffset = UInt32(data.count)
        for (index, fileName) in fileNames.enumerated() {
            let nameBytes = Array(fileName.utf8)
            centralDirectory.appendUInt32LE(0x0201_4B50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt16LE(UInt16(nameBytes.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(offsets[index])
            centralDirectory.append(contentsOf: nameBytes)
        }
        data.append(centralDirectory)

        data.appendUInt32LE(0x0605_4B50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(UInt16(fileNames.count))
        data.appendUInt16LE(UInt16(fileNames.count))
        data.appendUInt32LE(UInt32(centralDirectory.count))
        data.appendUInt32LE(centralDirectoryOffset)
        data.appendUInt16LE(0)

        return data
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x0000_00FF))
        append(UInt8((value >> 8) & 0x0000_00FF))
        append(UInt8((value >> 16) & 0x0000_00FF))
        append(UInt8((value >> 24) & 0x0000_00FF))
    }
}
