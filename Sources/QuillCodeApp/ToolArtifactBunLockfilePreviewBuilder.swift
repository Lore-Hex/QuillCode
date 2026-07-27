import Foundation

enum ToolArtifactBunLockfilePreviewBuilder {
    static func bunLockfilePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactBunLockfilePreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }
        let filename = fileURL.lastPathComponent.lowercased()
        guard filename == "bun.lock" || filename == "bun.lockb" else { return nil }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            if filename == "bun.lockb" {
                return ToolArtifactBunLockfilePreview(
                    formatLabel: "Bun binary lockfile",
                    byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
                )
            }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0),
                  let text = String(data: data, encoding: .utf8),
                  let root = try JSONSerialization.jsonObject(with: Data(jsonString(fromJSONC: text).utf8)) as? [String: Any],
                  isBunLockfile(root)
            else {
                return nil
            }
            let preview = preview(
                from: root,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func isBunLockfile(_ root: [String: Any]) -> Bool {
        root["lockfileVersion"] != nil
            && (root["workspaces"] is [String: Any]
                || root["packages"] is [String: Any]
                || root["catalog"] is [String: Any]
                || root["catalogs"] is [String: Any])
    }

    private static func preview(from root: [String: Any], byteSizeLabel: String?) -> ToolArtifactBunLockfilePreview {
        let workspaces = root["workspaces"] as? [String: Any] ?? [:]
        let packages = packageRecords(from: root["packages"])
        return ToolArtifactBunLockfilePreview(
            formatLabel: "Bun text lockfile",
            lockfileVersion: versionLabel(root["lockfileVersion"]),
            workspaceCount: workspaces.count,
            packageCount: packages.count,
            dependencyCount: dependencyCount(from: workspaces),
            catalogCount: catalogCount(from: root),
            sourceHostLabels: sourceHostLabels(from: packages),
            packagePreviewLabels: Array(packages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from value: Any?) -> [PackageRecord] {
        guard let packages = value as? [String: Any] else { return [] }
        return packages.compactMap { rawName, value -> PackageRecord? in
            guard value is [Any] || value is [String: Any] || value is String else { return nil }
            return PackageRecord(
                name: packageName(from: rawName),
                resolved: resolvedURL(from: value)
            )
        }
        .filter { !$0.name.isEmpty }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func dependencyCount(from workspaces: [String: Any]) -> Int {
        workspaces.values.reduce(0) { total, value in
            guard let workspace = value as? [String: Any] else { return total }
            return total + dependencyKeys.reduce(0) { count, key in
                count + ((workspace[key] as? [String: Any])?.count ?? 0)
            }
        }
    }

    private static func catalogCount(from root: [String: Any]) -> Int {
        let catalog = (root["catalog"] as? [String: Any])?.count ?? 0
        let catalogs = (root["catalogs"] as? [String: Any])?.values.reduce(0) { total, value in
            total + ((value as? [String: Any])?.count ?? 0)
        } ?? 0
        return catalog + catalogs
    }

    private static func sourceHostLabels(from packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            guard labels.count < previewLabelLimit,
                  let resolved = package.resolved,
                  let host = URL(string: resolved)?.host?.lowercased(),
                  seen.insert(host).inserted
            else {
                continue
            }
            labels.append(sanitizedLabel(host))
        }
        return labels
    }

    private static func resolvedURL(from value: Any) -> String? {
        if let string = value as? String {
            return URL(string: string)?.host == nil ? nil : string
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }.first { URL(string: $0)?.host != nil }
        }
        if let object = value as? [String: Any] {
            for key in ["resolved", "resolution", "url", "tarball"] {
                if let string = object[key] as? String, URL(string: string)?.host != nil {
                    return string
                }
            }
        }
        return nil
    }

    private static func packageName(from rawName: String) -> String {
        var text = rawName
        if text.hasPrefix("@"), let at = text.dropFirst().firstIndex(of: "@") {
            text = String(text[..<at])
        } else if let at = text.firstIndex(of: "@") {
            text = String(text[..<at])
        }
        return sanitizedLabel(text)
    }

    private static func versionLabel(_ value: Any?) -> String? {
        if let string = value as? String {
            let label = sanitizedLabel(string)
            return label.isEmpty ? nil : label
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func jsonString(fromJSONC text: String) -> String {
        var output = ""
        var iterator = text.makeIterator()
        var previous: Character?
        var inString = false
        var escaping = false
        var inLineComment = false
        var inBlockComment = false

        while let character = iterator.next() {
            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
                previous = character
                continue
            }
            if inBlockComment {
                if previous == "*", character == "/" {
                    inBlockComment = false
                    previous = nil
                } else {
                    previous = character
                }
                continue
            }
            if inString {
                output.append(character)
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
                previous = character
                continue
            }
            if previous == "/", character == "/" {
                output.removeLast()
                inLineComment = true
                previous = character
                continue
            }
            if previous == "/", character == "*" {
                output.removeLast()
                inBlockComment = true
                previous = character
                continue
            }
            if character == "\"" {
                inString = true
            }
            output.append(character)
            previous = character
        }
        return removingTrailingCommas(from: output)
    }

    private static func removingTrailingCommas(from text: String) -> String {
        var output = ""
        var pendingComma = false
        var inString = false
        var escaping = false
        for character in text {
            if inString {
                if pendingComma {
                    output.append(",")
                    pendingComma = false
                }
                output.append(character)
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                if pendingComma {
                    output.append(",")
                    pendingComma = false
                }
                inString = true
                output.append(character)
                continue
            }
            if character == "," {
                pendingComma = true
                continue
            }
            if pendingComma {
                if character == "}" || character == "]" {
                    pendingComma = false
                } else if !character.isWhitespace {
                    output.append(",")
                    pendingComma = false
                }
            }
            output.append(character)
        }
        if pendingComma {
            output.append(",")
        }
        return output
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsedWhitespace.prefix(characterLimit))
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

    private struct PackageRecord {
        var name: String
        var resolved: String?

        var label: String {
            name
        }
    }

    private static let dependencyKeys = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
