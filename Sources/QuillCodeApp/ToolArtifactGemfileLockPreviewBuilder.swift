import Foundation

enum ToolArtifactGemfileLockPreviewBuilder {
    static func gemfileLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactGemfileLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "gemfile.lock"
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
            let parsed = parsedLockfile(from: text)
            guard parsed.packageCount > 0 || parsed.dependencyCount > 0 else { return nil }
            let preview = ToolArtifactGemfileLockPreview(
                bundledWith: parsed.bundledWith,
                packageCount: parsed.packageCount,
                dependencyCount: parsed.dependencyCount,
                platformCount: parsed.platformCount,
                sourceCount: parsed.sourceLabels.count,
                sourcePreviewLabels: parsed.sourceLabels,
                packagePreviewLabels: parsed.packageLabels,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func parsedLockfile(from text: String) -> ParsedLockfile {
        var section: Section?
        var inSpecs = false
        var packages: [PackageRecord] = []
        var dependencies = Set<String>()
        var platforms = Set<String>()
        var sourceLabels: [String] = []
        var bundledWith: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let originalLine = String(rawLine)
            let line = originalLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let nextSection = Section(rawValue: line) {
                section = nextSection
                inSpecs = false
                continue
            }

            switch section {
            case .gem:
                if line == "specs:" {
                    inSpecs = true
                    continue
                }
                if line.hasPrefix("remote:") {
                    appendSourceLabels(from: line, into: &sourceLabels)
                    continue
                }
                if inSpecs, let package = packageRecord(from: originalLine) {
                    packages.append(package)
                }
            case .git, .path:
                if line.hasPrefix("remote:") {
                    appendSourceLabels(from: line, into: &sourceLabels)
                } else if line == "specs:" {
                    inSpecs = true
                } else if inSpecs, let package = packageRecord(from: originalLine) {
                    packages.append(package)
                }
            case .platforms:
                platforms.insert(sanitizedLabel(line))
            case .dependencies:
                if let dependencyName = dependencyName(from: line) {
                    dependencies.insert(dependencyName)
                }
            case .bundledWith:
                bundledWith = bundledWith ?? sanitizedLabel(line)
            case nil:
                continue
            }
        }

        return ParsedLockfile(
            bundledWith: bundledWith,
            packageCount: packages.count,
            dependencyCount: dependencies.count,
            platformCount: platforms.count,
            sourceLabels: Array(sourceLabels.prefix(previewLabelLimit)),
            packageLabels: Array(packages.sorted().prefix(previewLabelLimit)).map(\.label)
        )
    }

    private static func packageRecord(from line: String) -> PackageRecord? {
        guard line.hasPrefix("    "), !line.hasPrefix("      ") else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "("),
              trimmed.hasSuffix(")")
        else {
            return nil
        }
        let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let versionStart = trimmed.index(after: open)
        let versionEnd = trimmed.index(before: trimmed.endIndex)
        let version = trimmed[versionStart..<versionEnd].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !version.isEmpty else { return nil }
        return PackageRecord(
            name: sanitizedLabel(String(name)),
            version: sanitizedLabel(String(version))
        )
    }

    private static func dependencyName(from line: String) -> String? {
        let name = line.split { $0.isWhitespace || $0 == "(" }.first.map(String.init) ?? ""
        let sanitized = sanitizedLabel(name)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func appendSourceLabels(from line: String, into labels: inout [String]) {
        for label in hosts(in: line) where labels.count < previewLabelLimit && !labels.contains(label) {
            labels.append(label)
        }
    }

    private static func hosts(in value: String) -> [String] {
        value
            .split { $0.isWhitespace || $0 == "," }
            .compactMap { token in
                var text = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\\\",'()[]{}<>"))
                if text.lowercased().hasPrefix("git+") {
                    text.removeFirst(4)
                }
                guard text.hasPrefix("http://") || text.hasPrefix("https://"),
                      let host = URL(string: text)?.host?.lowercased()
                else {
                    return nil
                }
                return sanitizedLabel(host)
            }
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

    private enum Section: String {
        case gem = "GEM"
        case git = "GIT"
        case path = "PATH"
        case platforms = "PLATFORMS"
        case dependencies = "DEPENDENCIES"
        case bundledWith = "BUNDLED WITH"
    }

    private struct ParsedLockfile {
        var bundledWith: String?
        var packageCount: Int
        var dependencyCount: Int
        var platformCount: Int
        var sourceLabels: [String]
        var packageLabels: [String]
    }

    private struct PackageRecord: Comparable {
        var name: String
        var version: String

        var label: String {
            sanitizedLabel("\(name)@\(version)")
        }

        static func < (lhs: PackageRecord, rhs: PackageRecord) -> Bool {
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
