import Foundation

enum ToolArtifactValueClassifier {
    static func kind(for value: String) -> ToolArtifactKind {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return value.hasPrefix("/") ? .file : .path
        }
        if scheme == "http" || scheme == "https" {
            return .url
        }
        if isInlineImageData(value) {
            return .url
        }
        if scheme == "file" {
            return .file
        }
        return .path
    }

    static func label(for value: String) -> String {
        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "data"].contains(scheme) {
            if scheme == "data" {
                return isInlineImageData(value) ? "Inline image" : value
            }
            if scheme == "http" || scheme == "https" {
                let host = url.host ?? value
                return url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
            }
            if !url.lastPathComponent.isEmpty {
                return url.lastPathComponent
            }
            return value
        }
        let url = URL(fileURLWithPath: value)
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? value : lastPathComponent
    }

    static func detail(for value: String, kind: ToolArtifactKind) -> String {
        switch kind {
        case .url:
            if isInlineImageData(value) {
                return "Image artifact"
            }
            guard let url = URL(string: value), let host = url.host else { return value }
            return url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
        case .file:
            let url = value.hasPrefix("file://")
                ? URL(string: value)
                : URL(fileURLWithPath: value)
            guard let path = url?.deletingLastPathComponent().path, !path.isEmpty else {
                return "File artifact"
            }
            return path
        case .path:
            return value
        }
    }

    static func href(for value: String, kind: ToolArtifactKind) -> String? {
        switch kind {
        case .url:
            return value
        case .file:
            if value.hasPrefix("file://") {
                return value
            }
            if value.hasPrefix("/") {
                return URL(fileURLWithPath: value).absoluteString
            }
            return nil
        case .path:
            return nil
        }
    }

    static func pathExtension(for value: String) -> String {
        if let url = URL(string: value), url.scheme != nil {
            return url.pathExtension.lowercased()
        }
        return URL(fileURLWithPath: value).pathExtension.lowercased()
    }

    static func isInlineImageData(_ value: String) -> Bool {
        value.lowercased().hasPrefix("data:image/")
    }
}
