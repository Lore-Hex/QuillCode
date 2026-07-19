import Foundation

enum ToolArtifactPytestJSONPreviewBuilder {
    static func pytestJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPytestJSONPreview? {
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

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactPytestJSONPreview? {
        guard let summary = object["summary"] as? [String: Any] else { return nil }
        let tests = object["tests"] as? [[String: Any]] ?? []
        let counts = Counts(summary: summary, testCount: tests.count)
        guard counts.hasPytestShape || !tests.isEmpty else { return nil }

        let failures = tests.compactMap(failureLabel(from:))
            .prefix(failurePreviewLimit)
        return ToolArtifactPytestJSONPreview(
            exitCode: intValue(object["exitcode"]),
            durationLabel: durationLabel(from: object["duration"]),
            totalCount: counts.total,
            passedCount: counts.passed,
            failedCount: counts.failed,
            errorCount: counts.error,
            skippedCount: counts.skipped,
            xfailedCount: counts.xfailed,
            xpassedCount: counts.xpassed,
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: Array(failures)
        )
    }

    private static func failureLabel(from test: [String: Any]) -> String? {
        let outcome = stringValue(test["outcome"])?.lowercased()
        guard outcome == "failed" || outcome == "error" else { return nil }
        let nodeID = stringValue(test["nodeid"]) ?? stringValue(test["name"])
        return nodeID.map(sanitizedLabel)
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

    private static func durationLabel(from value: Any?) -> String? {
        guard let duration = doubleValue(value), duration >= 0 else { return nil }
        if duration < 10 {
            return String(format: "%.2fs", duration)
        }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let minutes = Int(duration / 60)
        let seconds = Int(duration.rounded()) % 60
        return "\(minutes)m \(seconds)s"
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown test" : collapsedWhitespace).prefix(characterLimit))
    }

    private struct Counts {
        var total: Int?
        var passed: Int?
        var failed: Int?
        var error: Int?
        var skipped: Int?
        var xfailed: Int?
        var xpassed: Int?

        var hasPytestShape: Bool {
            total != nil
                || passed != nil
                || failed != nil
                || error != nil
                || skipped != nil
                || xfailed != nil
                || xpassed != nil
        }

        init(summary: [String: Any], testCount: Int) {
            passed = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["passed"])
            failed = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["failed"])
            error = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["error"])
                ?? ToolArtifactPytestJSONPreviewBuilder.intValue(summary["errors"])
            skipped = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["skipped"])
            xfailed = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["xfailed"])
            xpassed = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["xpassed"])
            total = ToolArtifactPytestJSONPreviewBuilder.intValue(summary["total"])
                ?? ToolArtifactPytestJSONPreviewBuilder.intValue(summary["collected"])
                ?? (testCount > 0 ? testCount : nil)
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let failurePreviewLimit = 6
    private static let characterLimit = 96
}
