import Foundation
import QuillCodeCore

public enum ImageAttachmentStoreError: LocalizedError, Equatable {
    case notARegularFile
    case fileTooLarge(maximumBytes: Int)
    case unsupportedImage
    case attachmentLimitReached(maximumCount: Int)
    case unmanagedAttachment
    case attachmentChanged

    public var errorDescription: String? {
        switch self {
        case .notARegularFile:
            "Choose an image file."
        case .fileTooLarge(let maximumBytes):
            "Images must be \(maximumBytes / 1_024 / 1_024) MB or smaller."
        case .unsupportedImage:
            "Choose a PNG, JPEG, GIF, or WebP image."
        case .attachmentLimitReached(let maximumCount):
            "You can attach up to \(maximumCount) images to one message."
        case .unmanagedAttachment:
            "The attachment is outside QuillCode's managed image storage."
        case .attachmentChanged:
            "The attachment changed after it was added. Remove it and attach it again."
        }
    }
}

/// Copies user-selected images into a private, QuillCode-owned directory and is the only reader
/// used by the TrustedRouter prompt adapter. The root and content checks prevent hand-edited thread
/// JSON or replaced symlinks from turning an attachment into an arbitrary local-file upload.
public struct ImageAttachmentStore: Sendable, Hashable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public func importImage(from sourceURL: URL, threadID: UUID) throws -> ChatAttachment {
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw ImageAttachmentStoreError.notARegularFile
        }
        if let fileSize = values.fileSize, fileSize > ChatAttachment.maximumByteCount {
            throw ImageAttachmentStoreError.fileTooLarge(maximumBytes: ChatAttachment.maximumByteCount)
        }

        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard data.count <= ChatAttachment.maximumByteCount else {
            throw ImageAttachmentStoreError.fileTooLarge(maximumBytes: ChatAttachment.maximumByteCount)
        }
        guard let format = ChatImageFormat.detect(in: data) else {
            throw ImageAttachmentStoreError.unsupportedImage
        }

        let id = UUID()
        let threadDirectory = directory.appendingPathComponent(threadID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: threadDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = threadDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension(format.fileExtension)
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        guard let attachment = ChatAttachment(
            id: id,
            displayName: sourceURL.lastPathComponent,
            format: format,
            localURL: destination,
            byteCount: data.count
        ) else {
            try? FileManager.default.removeItem(at: destination)
            throw ImageAttachmentStoreError.unsupportedImage
        }
        return attachment
    }

    public func data(for attachment: ChatAttachment) throws -> Data {
        guard contains(attachment.localURL) else {
            throw ImageAttachmentStoreError.unmanagedAttachment
        }
        let values = try attachment.localURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw ImageAttachmentStoreError.notARegularFile
        }
        guard values.fileSize == attachment.byteCount,
              attachment.byteCount <= ChatAttachment.maximumByteCount
        else {
            throw ImageAttachmentStoreError.attachmentChanged
        }
        let data = try Data(contentsOf: attachment.localURL, options: .mappedIfSafe)
        guard data.count == attachment.byteCount,
              ChatImageFormat.detect(in: data) == attachment.format
        else {
            throw ImageAttachmentStoreError.attachmentChanged
        }
        return data
    }

    public func dataURL(for attachment: ChatAttachment) throws -> String {
        let data = try data(for: attachment)
        return "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
    }

    public func remove(_ attachment: ChatAttachment) throws {
        guard contains(attachment.localURL) else {
            throw ImageAttachmentStoreError.unmanagedAttachment
        }
        guard FileManager.default.fileExists(atPath: attachment.localURL.path) else { return }
        try FileManager.default.removeItem(at: attachment.localURL)
    }

    public func contains(_ fileURL: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        return candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
