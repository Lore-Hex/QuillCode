import Foundation

enum ToolArtifactJestJSONPreviewBuilder {
    static func jestJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactJestJSONPreview? {
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

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactJestJSONPreview? {
        let suites = object["testResults"] as? [[String: Any]] ?? []
        let counts = Counts(object: object, suiteCount: suites.count)
        guard counts.hasJestShape || suites.contains(where: hasAssertionResults) else { return nil }

        let failures = suites
            .flatMap(failureLabels(from:))
            .prefix(failurePreviewLimit)
        return ToolArtifactJestJSONPreview(
            success: boolValue(object["success"]),
            totalTestCount: counts.totalTests,
            passedTestCount: counts.passedTests,
            failedTestCount: counts.failedTests,
            pendingTestCount: counts.pendingTests,
            todoTestCount: counts.todoTests,
            totalSuiteCount: counts.totalSuites,
            failedSuiteCount: counts.failedSuites,
            runtimeLabel: runtimeLabel(from: suites),
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: Array(failures)
        )
    }

    private static func hasAssertionResults(_ suite: [String: Any]) -> Bool {
        guard let assertions = suite["assertionResults"] as? [[String: Any]] else { return false }
        return !assertions.isEmpty
    }

    private static func failureLabels(from suite: [String: Any]) -> [String] {
        guard let assertions = suite["assertionResults"] as? [[String: Any]] else { return [] }
        let suiteName = stringValue(suite["name"]) ?? stringValue(suite["testFilePath"])
        return assertions.compactMap { assertion in
            let status = stringValue(assertion["status"])?.lowercased()
            guard status == "failed" || status == "fail" else { return nil }
            return sanitizedLabel(assertionLabel(from: assertion, suiteName: suiteName))
        }
    }

    private static func assertionLabel(from assertion: [String: Any], suiteName: String?) -> String {
        if let fullName = stringValue(assertion["fullName"]) {
            return fullName
        }
        var pieces = (assertion["ancestorTitles"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let title = stringValue(assertion["title"]) {
            pieces.append(title)
        }
        if !pieces.isEmpty {
            return pieces.joined(separator: " > ")
        }
        if let suiteName {
            return suiteName
        }
        return "Unknown test"
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

    private static func runtimeLabel(from suites: [[String: Any]]) -> String? {
        let runtimes = suites.compactMap { suite -> Int? in
            guard let perfStats = suite["perfStats"] as? [String: Any] else { return nil }
            return intValue(perfStats["runtime"])
        }
        let milliseconds = runtimes.reduce(0, +)
        guard milliseconds > 0 else { return nil }
        return durationLabel(milliseconds: milliseconds)
    }

    private static func durationLabel(milliseconds: Int) -> String {
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
        var passedTests: Int?
        var failedTests: Int?
        var pendingTests: Int?
        var todoTests: Int?
        var totalSuites: Int?
        var failedSuites: Int?

        var hasJestShape: Bool {
            totalTests != nil
                || passedTests != nil
                || failedTests != nil
                || pendingTests != nil
                || todoTests != nil
                || totalSuites != nil
                || failedSuites != nil
        }

        init(object: [String: Any], suiteCount: Int) {
            totalTests = ToolArtifactJestJSONPreviewBuilder.intValue(object["numTotalTests"])
            passedTests = ToolArtifactJestJSONPreviewBuilder.intValue(object["numPassedTests"])
            failedTests = ToolArtifactJestJSONPreviewBuilder.intValue(object["numFailedTests"])
            pendingTests = ToolArtifactJestJSONPreviewBuilder.intValue(object["numPendingTests"])
            todoTests = ToolArtifactJestJSONPreviewBuilder.intValue(object["numTodoTests"])
            totalSuites = ToolArtifactJestJSONPreviewBuilder.intValue(object["numTotalTestSuites"])
                ?? (suiteCount > 0 ? suiteCount : nil)
            failedSuites = ToolArtifactJestJSONPreviewBuilder.intValue(object["numFailedTestSuites"])
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let failurePreviewLimit = 6
    private static let characterLimit = 96
}
