import Foundation

enum ToolArtifactAllureJSONPreviewBuilder {
    static func allureJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactAllureJSONPreview? {
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

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactAllureJSONPreview? {
        guard isAllureResult(object) else { return nil }

        let status = stringValue(object["status"])?.lowercased()
        let stepCounts = StepCounts(steps: object["steps"] as? [[String: Any]] ?? [])
        let durationMilliseconds = durationMilliseconds(from: object)
        let failureLabels = failureLabel(from: object, status: status).map { [$0] } ?? []
        return ToolArtifactAllureJSONPreview(
            resultName: stringValue(object["name"]) ?? stringValue(object["fullName"]),
            statusLabel: status.map(statusDisplayLabel),
            passedCount: status == "passed" ? 1 : 0,
            failedCount: status == "failed" ? 1 : 0,
            brokenCount: status == "broken" ? 1 : 0,
            skippedCount: status == "skipped" ? 1 : 0,
            unknownCount: isUnknown(status) ? 1 : 0,
            stepCount: stepCounts.total,
            failedStepCount: stepCounts.failed,
            durationLabel: durationLabel(milliseconds: durationMilliseconds),
            byteSizeLabel: byteSizeLabel,
            suitePreviewLabels: suiteLabels(from: object),
            failurePreviewLabels: failureLabels
        )
    }

    private static func isAllureResult(_ object: [String: Any]) -> Bool {
        guard stringValue(object["uuid"]) != nil,
              stringValue(object["status"]) != nil,
              stringValue(object["name"]) != nil || stringValue(object["fullName"]) != nil
        else {
            return false
        }

        let hasResultTime = doubleValue(object["start"]) != nil || doubleValue(object["stop"]) != nil
        let hasAllureCollections = object["labels"] is [[String: Any]]
            || object["steps"] is [[String: Any]]
            || object["attachments"] is [[String: Any]]
        return hasResultTime || hasAllureCollections
    }

    private static func suiteLabels(from object: [String: Any]) -> [String] {
        guard let labels = object["labels"] as? [[String: Any]] else { return [] }
        let acceptedNames: Set<String> = ["parentSuite", "suite", "subSuite", "package"]
        var result: [String] = []
        for label in labels {
            guard let name = stringValue(label["name"]),
                  acceptedNames.contains(name),
                  let value = stringValue(label["value"])
            else {
                continue
            }
            let sanitized = sanitizedLabel(value)
            guard !result.contains(sanitized) else { continue }
            result.append(sanitized)
            if result.count == previewLimit { break }
        }
        return result
    }

    private static func failureLabel(from object: [String: Any], status: String?) -> String? {
        guard isFailure(status) || isUnknown(status) else { return nil }
        let label = stringValue(object["fullName"]) ?? stringValue(object["name"]) ?? "Unknown test"
        return sanitizedLabel(label)
    }

    private static func durationMilliseconds(from object: [String: Any]) -> Int? {
        guard let start = doubleValue(object["start"]),
              let stop = doubleValue(object["stop"]),
              stop >= start
        else {
            return nil
        }
        return Int((stop - start).rounded())
    }

    private static func isFailure(_ status: String?) -> Bool {
        status == "failed" || status == "broken"
    }

    private static func isUnknown(_ status: String?) -> Bool {
        guard let status else { return true }
        return !["passed", "failed", "broken", "skipped"].contains(status)
    }

    private static func statusDisplayLabel(_ status: String) -> String {
        switch status {
        case "passed":
            return "passed"
        case "failed":
            return "failed"
        case "broken":
            return "broken"
        case "skipped":
            return "skipped"
        default:
            return "unknown"
        }
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

    private static func durationLabel(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds >= 0 else { return nil }
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
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

    private struct StepCounts {
        var total = 0
        var failed = 0

        init(steps: [[String: Any]]) {
            for step in steps {
                add(step)
            }
        }

        private mutating func add(_ step: [String: Any]) {
            total += 1
            let status = ToolArtifactAllureJSONPreviewBuilder.stringValue(step["status"])?.lowercased()
            if ToolArtifactAllureJSONPreviewBuilder.isFailure(status) {
                failed += 1
            }
            for nestedStep in step["steps"] as? [[String: Any]] ?? [] {
                add(nestedStep)
            }
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
