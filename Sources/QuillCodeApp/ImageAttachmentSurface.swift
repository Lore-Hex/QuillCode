import Foundation
import QuillCodeCore

public struct ImageAttachmentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var mimeType: String
    public var previewURL: String
    public var byteCountLabel: String
    public var accessibilityLabel: String

    public init(_ attachment: ChatAttachment) {
        self.id = attachment.id
        self.displayName = attachment.displayName
        self.mimeType = attachment.mimeType
        self.previewURL = attachment.localURL.absoluteString
        self.byteCountLabel = ByteCountFormatter.string(
            fromByteCount: Int64(attachment.byteCount),
            countStyle: .file
        )
        self.accessibilityLabel = "Attached image \(attachment.displayName), \(byteCountLabel)"
    }
}
