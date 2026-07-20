import Foundation

enum ToolArtifactMochaJSONPreviewBuilder {
    static func mochaJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactMochaJSONPreview? {
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

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactMochaJSONPreview? {
        guard let stats = object["stats"] as? [String: Any] else { return nil }
        let tests = object["tests"] as? [[String: Any]] ?? []
        let failures = object["failures"] as? [[String: Any]] ?? []
        let pending = object["pending"] as? [[String: Any]] ?? []
        let passes = object["passes"] as? [[String: Any]] ?? []
        let counts = Counts(stats: stats, tests: tests, passes: passes, failures: failures, pending: pending)
        guard counts.hasMochaShape || !tests.isEmpty || !failures.isEmpty || !pending.isEmpty || !passes.isEmpty else {
            return nil
        }

        let failureLabels = failures.compactMap(testLabel)
            .prefix(previewLimit)
        let pendingLabels = pending.compactMap(testLabel)
            .prefix(previewLimit)
        return ToolArtifactMochaJSONPreview(
            totalTestCount: counts.totalTests,
            passedTestCount: counts.passes,
            failedTestCount: counts.failures,
            pendingTestCount: counts.pending,
            durationLabel: durationLabel(milliseconds: counts.durationMilliseconds),
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: Array(failureLabels),
            pendingPreviewLabels: Array(pendingLabels)
        )
    }

    private static func testLabel(from test: [String: Any]) -> String? {
        (stringValue(test["fullTitle"]) ?? stringValue(test["title"]))
            .map(sanitizedLabel)
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
        var totalTests: Int?
        var passes: Int?
        var failures: Int?
        var pending: Int?
        var durationMilliseconds: Int?

        var hasMochaShape: Bool {
            totalTests != nil || passes != nil || failures != nil || pending != nil
        }

        init(
            stats: [String: Any],
            tests: [[String: Any]],
            passes passList: [[String: Any]],
            failures failureList: [[String: Any]],
            pending pendingList: [[String: Any]]
        ) {
            totalTests = ToolArtifactMochaJSONPreviewBuilder.intValue(stats["tests"])
                ?? (tests.isEmpty ? nil : tests.count)
            passes = ToolArtifactMochaJSONPreviewBuilder.intValue(stats["passes"])
                ?? (passList.isEmpty ? nil : passList.count)
            failures = ToolArtifactMochaJSONPreviewBuilder.intValue(stats["failures"])
                ?? (failureList.isEmpty ? nil : failureList.count)
            pending = ToolArtifactMochaJSONPreviewBuilder.intValue(stats["pending"])
                ?? ToolArtifactMochaJSONPreviewBuilder.intValue(stats["skipped"])
                ?? (pendingList.isEmpty ? nil : pendingList.count)
            durationMilliseconds = ToolArtifactMochaJSONPreviewBuilder.intValue(stats["duration"])
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
