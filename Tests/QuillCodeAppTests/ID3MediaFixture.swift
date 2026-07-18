import Foundation

enum ID3MediaFixture {
    static func mp3(
        title: String,
        artist: String,
        audioBytes: Data = Data([0xFF, 0xFB, 0x90, 0x64])
    ) -> Data {
        let titleFrame = textFrame(id: "TIT2", text: title)
        let artistFrame = textFrame(id: "TPE1", text: artist)
        let tagPayload = titleFrame + artistFrame
        var bytes = Array("ID3".utf8)
        bytes.append(contentsOf: [0x03, 0x00, 0x00])
        bytes.append(contentsOf: syncSafeBytes(tagPayload.count))
        bytes.append(contentsOf: tagPayload)
        bytes.append(contentsOf: audioBytes)
        return Data(bytes)
    }

    private static func textFrame(id: String, text: String) -> [UInt8] {
        let payload = [UInt8(0x03)] + Array(text.utf8)
        var bytes = Array(id.utf8)
        bytes.append(contentsOf: bigEndianBytes(payload.count))
        bytes.append(contentsOf: [0x00, 0x00])
        bytes.append(contentsOf: payload)
        return bytes
    }

    private static func syncSafeBytes(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ]
    }

    private static func bigEndianBytes(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }
}
