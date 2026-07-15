import Foundation

public enum ChatImageFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case png
    case jpeg
    case gif
    case webp

    public var mimeType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        case .gif: "image/gif"
        case .webp: "image/webp"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    public static func detect(in data: Data) -> ChatImageFormat? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return .gif
        }
        if bytes.count >= 12,
           Array(bytes[0..<4]) == Array("RIFF".utf8),
           Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return .webp
        }
        return nil
    }

    public init?(mimeType: String) {
        switch mimeType.lowercased() {
        case "image/png": self = .png
        case "image/jpeg", "image/jpg": self = .jpeg
        case "image/gif": self = .gif
        case "image/webp": self = .webp
        default: return nil
        }
    }
}

public enum ChatImageDetail: String, Codable, Sendable, Hashable, CaseIterable {
    case auto
    case low
    case high
    case original
}

/// A bounded image copied into QuillCode-owned storage and attached to a composer turn.
/// The model stores metadata and a local file URL; the TrustedRouter adapter separately
/// verifies that URL against its configured attachment root before reading any bytes.
public struct ChatAttachment: Codable, Sendable, Hashable, Identifiable {
    public static let maximumCountPerTurn = 4
    public static let maximumByteCount = 10 * 1_024 * 1_024
    public static let maximumDisplayNameLength = 160

    public var id: UUID
    public var displayName: String
    public var format: ChatImageFormat
    public var localURL: URL
    public var byteCount: Int
    public var detail: ChatImageDetail
    public var createdAt: Date

    public var mimeType: String { format.mimeType }

    public init?(
        id: UUID = UUID(),
        displayName: String,
        format: ChatImageFormat,
        localURL: URL,
        byteCount: Int,
        detail: ChatImageDetail = .auto,
        createdAt: Date = Date()
    ) {
        guard let displayName = Self.normalizedDisplayName(displayName),
              localURL.isFileURL,
              byteCount > 0,
              byteCount <= Self.maximumByteCount
        else {
            return nil
        }
        self.id = id
        self.displayName = displayName
        self.format = format
        self.localURL = localURL.standardizedFileURL
        self.byteCount = byteCount
        self.detail = detail
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case format
        case localURL
        case byteCount
        case detail
        case createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let attachment = ChatAttachment(
            id: try container.decode(UUID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            format: try container.decode(ChatImageFormat.self, forKey: .format),
            localURL: try container.decode(URL.self, forKey: .localURL),
            byteCount: try container.decode(Int.self, forKey: .byteCount),
            detail: try container.decodeIfPresent(ChatImageDetail.self, forKey: .detail) ?? .auto,
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .localURL,
                in: container,
                debugDescription: "Image attachments must be bounded files with valid metadata."
            )
        }
        self = attachment
    }

    private static func normalizedDisplayName(_ value: String) -> String? {
        let flattened = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return nil }
        let name = URL(fileURLWithPath: flattened).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        return String(name.prefix(maximumDisplayNameLength))
    }
}
