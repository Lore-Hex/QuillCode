#if !canImport(CryptoKit)
enum SHA256Pure {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func digest(_ message: [UInt8]) -> [UInt8] {
        var hash = initialHash
        var padded = SHA256PaddedMessage(message)

        for chunkStart in stride(from: 0, to: padded.bytes.count, by: 64) {
            var words = messageSchedule(from: padded.bytes, chunkStart: chunkStart)
            compress(words: &words, into: &hash)
        }

        return hash.flatMap { value in
            [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff)
            ]
        }
    }

    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static func messageSchedule(from padded: [UInt8], chunkStart: Int) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let byteIndex = chunkStart + index * 4
            words[index] = (UInt32(padded[byteIndex]) << 24)
                | (UInt32(padded[byteIndex + 1]) << 16)
                | (UInt32(padded[byteIndex + 2]) << 8)
                | UInt32(padded[byteIndex + 3])
        }
        for index in 16..<64 {
            let s0 = rotateRight(words[index - 15], 7)
                ^ rotateRight(words[index - 15], 18)
                ^ (words[index - 15] >> 3)
            let s1 = rotateRight(words[index - 2], 17)
                ^ rotateRight(words[index - 2], 19)
                ^ (words[index - 2] >> 10)
            words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
        }
        return words
    }

    private static func compress(words: inout [UInt32], into hash: inout [UInt32]) {
        var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
        var e = hash[4], f = hash[5], g = hash[6], h = hash[7]

        for index in 0..<64 {
            let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
            let choose = (e & f) ^ (~e & g)
            let temp1 = h &+ s1 &+ choose &+ k[index] &+ words[index]
            let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ majority
            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        hash[0] = hash[0] &+ a
        hash[1] = hash[1] &+ b
        hash[2] = hash[2] &+ c
        hash[3] = hash[3] &+ d
        hash[4] = hash[4] &+ e
        hash[5] = hash[5] &+ f
        hash[6] = hash[6] &+ g
        hash[7] = hash[7] &+ h
    }

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}

private struct SHA256PaddedMessage {
    var bytes: [UInt8]

    init(_ message: [UInt8]) {
        bytes = message
        let bitLength = UInt64(message.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
    }
}
#endif
