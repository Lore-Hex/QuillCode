import Foundation

enum ToolArtifactPlaywrightJSONPreviewBuilder {
    static func playwrightJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPlaywrightJSONPreview? {
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

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactPlaywrightJSONPreview? {
        guard let suites = object["suites"] as? [[String: Any]] else { return nil }
        let stats = object["stats"] as? [String: Any]
        let counts = Counts(stats: stats)
        let failedSpecLabels = suites
            .flatMap { failureLabels(in: $0, inheritedTitles: []) }
            .prefix(previewLimit)

        guard counts.hasPlaywrightShape || !suites.isEmpty && suites.contains(where: containsSpecsOrNestedSuites) else {
            return nil
        }

        return ToolArtifactPlaywrightJSONPreview(
            totalTestCount: counts.totalTests,
            expectedTestCount: counts.expected,
            unexpectedTestCount: counts.unexpected,
            flakyTestCount: counts.flaky,
            skippedTestCount: counts.skipped,
            durationLabel: durationLabel(milliseconds: counts.durationMilliseconds),
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: Array(failedSpecLabels)
        )
    }

    private static func containsSpecsOrNestedSuites(_ suite: [String: Any]) -> Bool {
        if let specs = suite["specs"] as? [[String: Any]], !specs.isEmpty {
            return true
        }
        let nestedSuites = suite["suites"] as? [[String: Any]] ?? []
        return nestedSuites.contains(where: containsSpecsOrNestedSuites)
    }

    private static func failureLabels(in suite: [String: Any], inheritedTitles: [String]) -> [String] {
        let title = stringValue(suite["title"])
        let titles = title.map { inheritedTitles + [$0] } ?? inheritedTitles
        let specs = suite["specs"] as? [[String: Any]] ?? []
        let specLabels = specs.compactMap { failureLabel(from: $0, inheritedTitles: titles) }
        let nestedSuites = suite["suites"] as? [[String: Any]] ?? []
        return specLabels + nestedSuites.flatMap { failureLabels(in: $0, inheritedTitles: titles) }
    }

    private static func failureLabel(from spec: [String: Any], inheritedTitles: [String]) -> String? {
        let tests = spec["tests"] as? [[String: Any]] ?? []
        let hasFailedResult = tests.contains { test in
            let results = test["results"] as? [[String: Any]] ?? []
            return results.contains { result in
                guard let status = stringValue(result["status"])?.lowercased() else { return false }
                return failedResultStatuses.contains(status)
            }
        }
        let specOK = boolValue(spec["ok"])
        guard hasFailedResult || specOK == false else { return nil }
        var pieces = inheritedTitles
        if let title = stringValue(spec["title"]) {
            pieces.append(title)
        }
        if pieces.isEmpty, let file = stringValue(spec["file"]) {
            pieces.append(file)
        }
        return sanitizedLabel(pieces.isEmpty ? "Unknown test" : pieces.joined(separator: " > "))
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

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "true" { return true }
            if normalized == "false" { return false }
            return nil
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func durationLabel(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds >= 0 else { return nil }
        let seconds = Double(milliseconds) / 1_000
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
        return String((collapsedWhitespace.isEmpty ? "Unknown test" : collapsedWhitespace).prefix(characterLimit))
    }

    private struct Counts {
        var expected: Int?
        var unexpected: Int?
        var flaky: Int?
        var skipped: Int?
        var durationMilliseconds: Int?

        var totalTests: Int? {
            let values = [expected, unexpected, flaky, skipped].compactMap { $0 }
            return values.isEmpty ? nil : values.reduce(0, +)
        }

        var hasPlaywrightShape: Bool {
            expected != nil || unexpected != nil || flaky != nil || skipped != nil
        }

        init(stats: [String: Any]?) {
            expected = ToolArtifactPlaywrightJSONPreviewBuilder.intValue(stats?["expected"])
            unexpected = ToolArtifactPlaywrightJSONPreviewBuilder.intValue(stats?["unexpected"])
            flaky = ToolArtifactPlaywrightJSONPreviewBuilder.intValue(stats?["flaky"])
            skipped = ToolArtifactPlaywrightJSONPreviewBuilder.intValue(stats?["skipped"])
            durationMilliseconds = ToolArtifactPlaywrightJSONPreviewBuilder.intValue(stats?["duration"])
        }
    }

    private static let failedResultStatuses: Set<String> = ["failed", "timedout", "timed_out", "interrupted"]
    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
