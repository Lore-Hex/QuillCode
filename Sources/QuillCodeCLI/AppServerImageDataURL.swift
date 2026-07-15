import Foundation
import QuillCodeCore

enum AppServerImageDataURLError: LocalizedError, Equatable {
    case unsupportedURL
    case invalidEncoding
    case unsupportedImage
    case imageTooLarge
    case declaredTypeMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "image.url must be a base64 data URL; remote http and https image URLs are not supported"
        case .invalidEncoding:
            "image.url must contain valid base64 image data"
        case .unsupportedImage:
            "image.url must contain a PNG, JPEG, GIF, or WebP image"
        case .imageTooLarge:
            "image.url exceeds the (ChatAttachment.maximumByteCount / 1_024 / 1_024) MB image limit"
        case .declaredTypeMismatch:
            "image.url media type does not match the encoded image"
        }
    }
}

struct AppServerImageDataURL: Sendable, Equatable {
    static let maximumEncodedBytes = ((ChatAttachment.maximumByteCount + 2) / 3) * 4

    var data: Data
    var format: ChatImageFormat

    var displayName: String { "image.\(format.fileExtension)" }

    init(_ value: String) throws {
        guard let comma = value.firstIndex(of: ",") else {
            throw AppServerImageDataURLError.unsupportedURL
        }
        guard value.utf8.count <= Self.maximumEncodedBytes + 64 else {
            throw AppServerImageDataURLError.imageTooLarge
        }

        let header = String(value[..<comma])
        let encoded = String(value[value.index(after: comma)...])
        let headerParts = header.split(separator: ";", omittingEmptySubsequences: false)
        guard headerParts.count == 2,
              headerParts[1].caseInsensitiveCompare("base64") == .orderedSame,
              headerParts[0].lowercased().hasPrefix("data:"),
              let declaredFormat = ChatImageFormat(
                  mimeType: String(headerParts[0].dropFirst("data:".count))
              )
        else {
            throw AppServerImageDataURLError.unsupportedURL
        }
        guard encoded.utf8.count <= Self.maximumEncodedBytes else {
            throw AppServerImageDataURLError.imageTooLarge
        }
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else {
            throw AppServerImageDataURLError.invalidEncoding
        }
        guard data.count <= ChatAttachment.maximumByteCount else {
            throw AppServerImageDataURLError.imageTooLarge
        }
        guard let detectedFormat = ChatImageFormat.detect(in: data) else {
            throw AppServerImageDataURLError.unsupportedImage
        }
        guard detectedFormat == declaredFormat else {
            throw AppServerImageDataURLError.declaredTypeMismatch
        }

        self.data = data
        self.format = detectedFormat
    }
}
