import Foundation

enum ToolArtifactHyperfineJSONPreviewBuilder {
    static func hyperfineJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactHyperfineJSONPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "json",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0) else { return nil }
            let root = try JSONSerialization.jsonObject(with: data, options: [])
            guard let object = root as? [String: Any] else { return nil }
            return preview(
                from: object,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from object: [String: Any],
        byteSizeLabel: String?
    ) -> ToolArtifactHyperfineJSONPreview? {
        let results = object["results"] as? [[String: Any]] ?? []
        guard isHyperfineReport(results) else { return nil }

        let commandLabels = Array(results.compactMap(commandLabel).prefix(previewLimit))
        let fastest = fastestResult(in: results)
        return ToolArtifactHyperfineJSONPreview(
            commandCount: results.count,
            fastestCommandLabel: fastest.flatMap(commandLabel),
            fastestMeanLabel: fastest.flatMap { secondsLabel(doubleValue($0["mean"])) },
            byteSizeLabel: byteSizeLabel,
            commandPreviewLabels: commandLabels
        )
    }

    private static func isHyperfineReport(_ results: [[String: Any]]) -> Bool {
        guard !results.isEmpty else { return false }
        return results.allSatisfy { result in
            commandLabel(from: result) != nil
                && (doubleValue(result["mean"]) != nil || doubleValue(result["median"]) != nil)
        }
    }

    private static func fastestResult(in results: [[String: Any]]) -> [String: Any]? {
        results
            .compactMap { result -> (result: [String: Any], mean: Double)? in
                guard let mean = doubleValue(result["mean"]) else { return nil }
                return (result, mean)
            }
            .min { lhs, rhs in lhs.mean < rhs.mean }?
            .result
    }

    private static func commandLabel(from result: [String: Any]) -> String? {
        stringValue(result["command"]).map(sanitizedLabel)
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

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func secondsLabel(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        if seconds < 0.001 {
            return String(format: "%.0f us", seconds * 1_000_000)
        }
        if seconds < 1 {
            return String(format: "%.2f ms", seconds * 1_000)
        }
        if seconds < 60 {
            return String(format: "%.2fs", seconds)
        }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.rounded()) % 60
        return "\(minutes)m \(remainder)s"
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown command" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
