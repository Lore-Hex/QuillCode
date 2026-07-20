import Foundation

enum ToolArtifactRSpecJSONPreviewBuilder {
    static func rspecJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactRSpecJSONPreview? {
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
            guard let report = root as? [String: Any] else { return nil }
            return preview(
                from: report,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(from report: [String: Any], byteSizeLabel: String?) -> ToolArtifactRSpecJSONPreview? {
        guard let examples = report["examples"] as? [[String: Any]], !examples.isEmpty else { return nil }
        let summary = report["summary"] as? [String: Any]
        guard hasRSpecShape(summary: summary, examples: examples) else { return nil }

        let statuses = examples.compactMap { stringValue($0["status"])?.lowercased() }
        let total = intValue(summary?["example_count"]) ?? examples.count
        let failed = intValue(summary?["failure_count"]) ?? statuses.filter { $0 == "failed" }.count
        let pending = intValue(summary?["pending_count"]) ?? statuses.filter { $0 == "pending" }.count
        let passed = max(total - failed - pending, 0)
        let duration = doubleValue(summary?["duration"]) ?? examples.compactMap { doubleValue($0["run_time"]) }.reduce(0, +)
        let failures = examples
            .filter { stringValue($0["status"])?.lowercased() == "failed" }
            .compactMap(exampleLabel(from:))
            .prefix(previewLimit)
        let pendings = examples
            .filter { stringValue($0["status"])?.lowercased() == "pending" }
            .compactMap(exampleLabel(from:))
            .prefix(previewLimit)

        return ToolArtifactRSpecJSONPreview(
            totalExampleCount: total,
            passedExampleCount: passed,
            failedExampleCount: failed,
            pendingExampleCount: pending,
            durationLabel: durationLabel(seconds: duration),
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: Array(failures),
            pendingPreviewLabels: Array(pendings)
        )
    }

    private static func hasRSpecShape(summary: [String: Any]?, examples: [[String: Any]]) -> Bool {
        if let summary,
           intValue(summary["example_count"]) != nil,
           intValue(summary["failure_count"]) != nil,
           intValue(summary["pending_count"]) != nil {
            return true
        }

        return examples.contains { example in
            stringValue(example["full_description"]) != nil
                && stringValue(example["status"]) != nil
                && (stringValue(example["file_path"]) != nil || intValue(example["line_number"]) != nil)
        }
    }

    private static func exampleLabel(from example: [String: Any]) -> String? {
        let description = stringValue(example["full_description"])
            ?? stringValue(example["description"])
            ?? stringValue(example["id"])
        guard let description else { return nil }
        let location = [stringValue(example["file_path"]), intValue(example["line_number"]).map(String.init)]
            .compactMap { $0 }
            .joined(separator: ":")
        if location.isEmpty {
            return sanitizedLabel(description)
        }
        return sanitizedLabel("\(description) · \(location)")
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

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
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

    private static func durationLabel(seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        if seconds < 10 {
            return String(format: "%.2fs", seconds)
        }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.rounded()) % 60
        return "\(minutes)m \(remainder)s"
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown example" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
