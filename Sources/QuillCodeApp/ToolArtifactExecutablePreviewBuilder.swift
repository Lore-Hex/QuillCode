import Foundation

enum ToolArtifactExecutablePreviewBuilder {
    static func executablePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactExecutablePreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              executableExtensions.contains(documentPreview.extensionLabel.lowercased()),
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize >= minimumHeaderSize else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: headerReadLimit) ?? Data()
            guard header.count >= minimumHeaderSize else { return nil }

            return executablePreview(from: header, fileSize: fileSize)
        } catch {
            return nil
        }
    }

    private static func executablePreview(from header: Data, fileSize: Int) -> ToolArtifactExecutablePreview? {
        if header.starts(with: elfMagic) {
            return elfPreview(from: header, fileSize: fileSize)
        }
        if header.starts(with: mzMagic) {
            return pePreview(from: header, fileSize: fileSize)
        }
        return machOPreview(from: header, fileSize: fileSize)
    }

    private static func elfPreview(from header: Data, fileSize: Int) -> ToolArtifactExecutablePreview? {
        guard header.count >= 20 else { return nil }
        let isLittleEndian = header[5] == 1
        let machine = unsigned16(in: header, offset: 18, littleEndian: isLittleEndian)
        return ToolArtifactExecutablePreview(
            formatLabel: "ELF",
            architectureLabel: elfArchitectureLabel(for: machine),
            bitnessLabel: header[4] == 2 ? "64-bit" : header[4] == 1 ? "32-bit" : nil,
            endianLabel: isLittleEndian ? "Little" : header[5] == 2 ? "Big" : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func pePreview(from header: Data, fileSize: Int) -> ToolArtifactExecutablePreview? {
        guard header.count >= 64,
              let peOffset = unsigned32(in: header, offset: 60, littleEndian: true),
              peOffset <= UInt32(header.count - 6),
              header[Int(peOffset)..<Int(peOffset) + 4].elementsEqual(peMagic)
        else {
            return nil
        }
        let machine = unsigned16(in: header, offset: Int(peOffset) + 4, littleEndian: true)
        return ToolArtifactExecutablePreview(
            formatLabel: "PE",
            architectureLabel: peArchitectureLabel(for: machine),
            bitnessLabel: peBitnessLabel(for: machine),
            endianLabel: "Little",
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func machOPreview(from header: Data, fileSize: Int) -> ToolArtifactExecutablePreview? {
        guard header.count >= 8,
              let magic = unsigned32(in: header, offset: 0, littleEndian: false)
        else {
            return nil
        }
        let littleEndian: Bool
        let bitnessLabel: String
        switch magic {
        case 0xFEEDFACE:
            littleEndian = false
            bitnessLabel = "32-bit"
        case 0xCEFAEDFE:
            littleEndian = true
            bitnessLabel = "32-bit"
        case 0xFEEDFACF:
            littleEndian = false
            bitnessLabel = "64-bit"
        case 0xCFFAEDFE:
            littleEndian = true
            bitnessLabel = "64-bit"
        case 0xCAFEBABE, 0xBEBAFECA:
            return ToolArtifactExecutablePreview(
                formatLabel: "Mach-O Universal",
                architectureLabel: "Fat binary",
                bitnessLabel: nil,
                endianLabel: magic == 0xCAFEBABE ? "Big" : "Little",
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        default:
            return nil
        }

        let cpuType = unsigned32(in: header, offset: 4, littleEndian: littleEndian)
        return ToolArtifactExecutablePreview(
            formatLabel: "Mach-O",
            architectureLabel: cpuType.flatMap(machOArchitectureLabel),
            bitnessLabel: bitnessLabel,
            endianLabel: littleEndian ? "Little" : "Big",
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func elfArchitectureLabel(for machine: UInt16?) -> String? {
        switch machine {
        case 0x03:
            return "x86"
        case 0x3E:
            return "x86_64"
        case 0x28:
            return "ARM"
        case 0xB7:
            return "ARM64"
        case 0xF3:
            return "RISC-V"
        case .some(let value):
            return "machine 0x\(String(value, radix: 16).uppercased())"
        case nil:
            return nil
        }
    }

    private static func peArchitectureLabel(for machine: UInt16?) -> String? {
        switch machine {
        case 0x014C:
            return "x86"
        case 0x8664:
            return "x86_64"
        case 0x01C0, 0x01C4:
            return "ARM"
        case 0xAA64:
            return "ARM64"
        case .some(let value):
            return "machine 0x\(String(value, radix: 16).uppercased())"
        case nil:
            return nil
        }
    }

    private static func peBitnessLabel(for machine: UInt16?) -> String? {
        switch machine {
        case 0x8664, 0xAA64:
            return "64-bit"
        case 0x014C, 0x01C0, 0x01C4:
            return "32-bit"
        default:
            return nil
        }
    }

    private static func machOArchitectureLabel(for cpuType: UInt32) -> String {
        switch cpuType {
        case 0x00000007:
            return "x86"
        case 0x01000007:
            return "x86_64"
        case 0x0000000C:
            return "ARM"
        case 0x0100000C:
            return "ARM64"
        default:
            return "CPU 0x\(String(cpuType, radix: 16).uppercased())"
        }
    }

    private static func unsigned16(in data: Data, offset: Int, littleEndian: Bool) -> UInt16? {
        guard data.count >= offset + 2 else { return nil }
        let first = UInt16(data[offset])
        let second = UInt16(data[offset + 1])
        return littleEndian ? first | second << 8 : first << 8 | second
    }

    private static func unsigned32(in data: Data, offset: Int, littleEndian: Bool) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        let bytes = (0..<4).map { UInt32(data[offset + $0]) }
        if littleEndian {
            return bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24
        }
        return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else {
            return nil
        }
        return url
    }

    private static let executableExtensions: Set<String> = ["bin", "dll", "dylib", "exe", "o", "so"]
    private static let minimumHeaderSize = 8
    private static let headerReadLimit = 512
    private static let elfMagic = Data([0x7F, 0x45, 0x4C, 0x46])
    private static let mzMagic = Data([0x4D, 0x5A])
    private static let peMagic = Data([0x50, 0x45, 0x00, 0x00])
}
