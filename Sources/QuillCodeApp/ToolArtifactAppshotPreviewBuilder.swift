import Foundation

enum ToolArtifactAppshotPreviewBuilder {
    static func appshotPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactAppshotPreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.kind == .appshot,
              let fileURL = localArtifactFileURL(for: value),
              let root = appshotRoot(from: fileURL)
        else {
            return nil
        }

        let preview = ToolArtifactAppshotPreview(
            title: nestedString(in: root, keys: ["title", "name"]),
            appLabel: appLabel(from: root),
            summary: nestedString(in: root, keys: ["summary", "description"]),
            capturedAt: nestedString(in: root, keys: ["capturedAt", "createdAt", "timestamp"]),
            viewportLabel: viewportLabel(from: root),
            windowCount: (root["windows"] as? [Any])?.count,
            screenshotURL: screenshotURL(from: root, relativeTo: fileURL.deletingLastPathComponent())
        )
        return preview.hasDisplayContent ? preview : nil
    }

    private static func appshotRoot(from fileURL: URL) -> [String: Any]? {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: byteLimit + 1),
                  !data.isEmpty,
                  data.count <= byteLimit
            else {
                return nil
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func appLabel(from root: [String: Any]) -> String? {
        if let app = nestedString(in: root, keys: ["app", "appName", "application", "bundleIdentifier"]) {
            return app
        }
        return string(from: root["app"], nestedKeys: ["name", "displayName", "bundleIdentifier"])
    }

    private static func viewportLabel(from root: [String: Any]) -> String? {
        if let viewport = root["viewport"] as? [String: Any],
           let width = dimensionValue(viewport["width"]),
           let height = dimensionValue(viewport["height"]) {
            return "\(width) x \(height)"
        }
        guard let width = dimensionValue(root["width"]),
              let height = dimensionValue(root["height"])
        else {
            return nil
        }
        return "\(width) x \(height)"
    }

    private static func screenshotURL(from root: [String: Any], relativeTo directory: URL) -> String? {
        for key in screenshotKeys {
            guard let candidate = string(from: root[key], nestedKeys: ["path", "url", "file", "imagePath"]) else {
                continue
            }
            if let url = resolvedImageFileURL(from: candidate, relativeTo: directory) {
                return url.absoluteString
            }
        }
        return nil
    }

    private static func resolvedImageFileURL(from candidate: String, relativeTo directory: URL) -> URL? {
        let imageURL: URL
        if candidate.hasPrefix("file://"),
           let url = URL(string: candidate),
           ToolArtifactImagePreviewBuilder.isImagePreview(for: url.path, kind: .file) {
            imageURL = url
        } else if candidate.hasPrefix("/") {
            guard ToolArtifactImagePreviewBuilder.isImagePreview(for: candidate, kind: .file) else {
                return nil
            }
            imageURL = URL(fileURLWithPath: candidate)
        } else {
            guard !candidate.contains("://") else { return nil }
            imageURL = directory.appendingPathComponent(candidate)
        }
        let standardizedURL = imageURL.standardizedFileURL
        guard isContained(standardizedURL, in: directory.standardizedFileURL),
              ToolArtifactImagePreviewBuilder.isImagePreview(for: standardizedURL.path, kind: .file)
        else {
            return nil
        }
        return standardizedURL
    }

    private static func isContained(_ fileURL: URL, in directory: URL) -> Bool {
        let filePath = fileURL.path
        let directoryPath = directory.path
        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }

    private static func nestedString(in root: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = string(from: root[key], nestedKeys: ["value", "text", "name"]) else {
                continue
            }
            return value
        }
        return nil
    }

    private static func string(from value: Any?, nestedKeys: [String]) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        guard let object = value as? [String: Any] else { return nil }
        for key in nestedKeys {
            if let nested = string(from: object[key], nestedKeys: []) {
                return nested
            }
        }
        return nil
    }

    private static func dimensionValue(_ value: Any?) -> Int? {
        if let int = value as? Int, int > 0 { return int }
        if let number = value as? NSNumber {
            let int = number.intValue
            return int > 0 ? int : nil
        }
        if let string = value as? String,
           let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           int > 0 {
            return int
        }
        return nil
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }

    private static let byteLimit = 128 * 1024
    private static let screenshotKeys = [
        "screenshot",
        "screenshotPath",
        "image",
        "imagePath",
        "thumbnail",
        "thumbnailPath",
        "preview",
        "previewImage"
    ]
}
