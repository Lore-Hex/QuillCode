import Foundation

enum ToolArtifactCucumberJSONPreviewBuilder {
    static func cucumberJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCucumberJSONPreview? {
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
            guard let features = root as? [[String: Any]] else { return nil }
            return preview(
                from: features,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(from features: [[String: Any]], byteSizeLabel: String?) -> ToolArtifactCucumberJSONPreview? {
        guard !features.isEmpty, features.contains(where: hasCucumberFeatureShape) else { return nil }
        let scenarios = features.flatMap(scenarios(in:))
        guard !scenarios.isEmpty else { return nil }
        let stepStatuses = scenarios.flatMap(stepStatuses(in:))
        let failingScenarios = scenarios.compactMap(failureLabel(from:)).prefix(previewLimit)
        let durations = scenarios.flatMap(stepDurations(in:))
        return ToolArtifactCucumberJSONPreview(
            featureCount: features.count,
            scenarioCount: scenarios.count,
            stepCount: stepStatuses.count,
            passedStepCount: stepStatuses.filter { $0 == "passed" }.count,
            failedStepCount: stepStatuses.filter { $0 == "failed" }.count,
            skippedStepCount: stepStatuses.filter { $0 == "skipped" }.count,
            pendingStepCount: stepStatuses.filter { $0 == "pending" }.count,
            undefinedStepCount: stepStatuses.filter { $0 == "undefined" }.count,
            durationLabel: durationLabel(nanoseconds: durations.reduce(0, +)),
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: Array(failingScenarios)
        )
    }

    private static func hasCucumberFeatureShape(_ feature: [String: Any]) -> Bool {
        guard let elements = feature["elements"] as? [[String: Any]], !elements.isEmpty else { return false }
        return stringValue(feature["keyword"])?.lowercased() == "feature"
            || stringValue(feature["uri"]) != nil
            || elements.contains { stringValue($0["keyword"]) != nil && ($0["steps"] as? [[String: Any]]) != nil }
    }

    private static func scenarios(in feature: [String: Any]) -> [Scenario] {
        let featureName = stringValue(feature["name"])
        let elements = feature["elements"] as? [[String: Any]] ?? []
        return elements.compactMap { element in
            guard let steps = element["steps"] as? [[String: Any]], !steps.isEmpty else { return nil }
            return Scenario(
                featureName: featureName,
                name: stringValue(element["name"]),
                steps: steps
            )
        }
    }

    private static func stepStatuses(in scenario: Scenario) -> [String] {
        scenario.steps.compactMap { step in
            guard let result = step["result"] as? [String: Any] else { return nil }
            return stringValue(result["status"])?.lowercased()
        }
    }

    private static func stepDurations(in scenario: Scenario) -> [Int] {
        scenario.steps.compactMap { step in
            guard let result = step["result"] as? [String: Any] else { return nil }
            return intValue(result["duration"])
        }
    }

    private static func failureLabel(from scenario: Scenario) -> String? {
        guard stepStatuses(in: scenario).contains("failed") else { return nil }
        return sanitizedLabel([scenario.featureName, scenario.name]
            .compactMap { $0 }
            .joined(separator: " > "))
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

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func durationLabel(nanoseconds: Int) -> String? {
        guard nanoseconds > 0 else { return nil }
        let seconds = Double(nanoseconds) / 1_000_000_000
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
        return String((collapsedWhitespace.isEmpty ? "Unknown scenario" : collapsedWhitespace).prefix(characterLimit))
    }

    private struct Scenario {
        var featureName: String?
        var name: String?
        var steps: [[String: Any]]
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
