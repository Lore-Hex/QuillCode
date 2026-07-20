import Foundation

enum ToolArtifactGoTestJSONLinesPreviewBuilder {
    static func goTestJSONLinesPreview(
        for value: String,
        kind: ToolArtifactKind
    ) -> ToolArtifactGoTestJSONLinesPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              supportedExtensions.contains(documentPreview.extensionLabel.lowercased()),
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
            guard !data.contains(0),
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            let records = try decodeRecords(from: text)
            return preview(
                from: records,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func decodeRecords(from text: String) throws -> [[String: Any]] {
        try text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: []) as? [String: Any]
            }
    }

    private static func preview(
        from records: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactGoTestJSONLinesPreview? {
        let events = records.compactMap(goTestEvent)
        guard events.count == records.count,
              !events.isEmpty,
              events.contains(where: { $0.testName != nil }),
              events.contains(where: { terminalActions.contains($0.action) })
        else {
            return nil
        }

        var packages = Set<String>()
        var tests = Set<TestIdentifier>()
        var passedTests = Set<TestIdentifier>()
        var failedTests = Set<TestIdentifier>()
        var skippedTests = Set<TestIdentifier>()
        var packageFailureCount = 0
        var packagePassCount = 0
        var outputCount = 0
        var failedLabels: [String] = []
        var skippedLabels: [String] = []

        for event in events {
            packages.insert(event.packageName)
            if event.action == "output" {
                outputCount += 1
            }
            guard let testName = event.testName else {
                if event.action == "fail" {
                    packageFailureCount += 1
                } else if event.action == "pass" {
                    packagePassCount += 1
                }
                continue
            }

            let test = TestIdentifier(packageName: event.packageName, testName: testName)
            tests.insert(test)
            switch event.action {
            case "pass":
                passedTests.insert(test)
            case "fail":
                failedTests.insert(test)
                appendUnique(sanitizedLabel(test.previewLabel), to: &failedLabels, limit: previewLimit)
            case "skip":
                skippedTests.insert(test)
                appendUnique(sanitizedLabel(test.previewLabel), to: &skippedLabels, limit: previewLimit)
            default:
                break
            }
        }

        return ToolArtifactGoTestJSONLinesPreview(
            eventCount: events.count,
            packageCount: packages.count,
            testCount: tests.count,
            passedTestCount: passedTests.count,
            failedTestCount: failedTests.count,
            skippedTestCount: skippedTests.count,
            packagePassCount: packagePassCount,
            packageFailureCount: packageFailureCount,
            outputEventCount: outputCount,
            byteSizeLabel: byteSizeLabel,
            failedTestPreviewLabels: failedLabels,
            skippedTestPreviewLabels: skippedLabels
        )
    }

    private static func goTestEvent(from record: [String: Any]) -> GoTestEvent? {
        guard let action = stringValue(record["Action"])?.lowercased(),
              recognizedActions.contains(action),
              let packageName = stringValue(record["Package"])
        else {
            return nil
        }
        return GoTestEvent(
            action: action,
            packageName: packageName,
            testName: stringValue(record["Test"])
        )
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

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendUnique(_ value: String, to values: inout [String], limit: Int) {
        guard values.count < limit, !values.contains(value) else { return }
        values.append(value)
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown" : collapsedWhitespace).prefix(characterLimit))
    }

    private struct GoTestEvent {
        var action: String
        var packageName: String
        var testName: String?
    }

    private struct TestIdentifier: Hashable {
        var packageName: String
        var testName: String

        var previewLabel: String {
            "\(packageName).\(testName)"
        }
    }

    private static let supportedExtensions: Set<String> = ["jsonl", "ndjson"]
    private static let recognizedActions: Set<String> = ["run", "pause", "cont", "pass", "bench", "fail", "output", "skip"]
    private static let terminalActions: Set<String> = ["pass", "fail", "skip"]
    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
