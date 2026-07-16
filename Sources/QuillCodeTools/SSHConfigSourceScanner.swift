import Foundation

struct SSHConfigScanResult {
    var aliases: [String]
    var warnings: [String]
}

struct SSHConfigSourceScanner {
    let rootConfigURL: URL
    let homeDirectory: URL
    let limits: SSHHostDiscoveryLimits

    private var visitedPaths: Set<String> = []
    private var aliases: [String] = []
    private var aliasKeys: Set<String> = []
    private var warnings: [String] = []
    private var filesRead = 0
    private var totalBytes = 0

    init(rootConfigURL: URL, homeDirectory: URL, limits: SSHHostDiscoveryLimits) {
        self.rootConfigURL = rootConfigURL
        self.homeDirectory = homeDirectory
        self.limits = limits
    }

    mutating func scan() -> SSHConfigScanResult {
        scanFile(rootConfigURL, depth: 0)
        return SSHConfigScanResult(aliases: aliases, warnings: warnings)
    }

    private mutating func scanFile(_ url: URL, depth: Int) {
        guard !Task.isCancelled, aliases.count < limits.maximumAliases else { return }
        guard depth <= limits.maximumDepth else {
            warnOnce("SSH config include depth exceeded \(limits.maximumDepth).")
            return
        }
        guard filesRead < limits.maximumFiles else {
            warnOnce("SSH config scan stopped after \(limits.maximumFiles) files.")
            return
        }

        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard visitedPaths.insert(canonicalURL.path).inserted else { return }
        guard let resourceValues = try? canonicalURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              resourceValues.isRegularFile == true,
              let fileSize = resourceValues.fileSize
        else { return }
        guard fileSize <= limits.maximumTotalBytes - totalBytes else {
            warnOnce("SSH config scan exceeded \(limits.maximumTotalBytes) bytes.")
            return
        }
        guard let data = try? Data(contentsOf: canonicalURL, options: [.mappedIfSafe]) else { return }
        guard totalBytes + data.count <= limits.maximumTotalBytes else {
            warnOnce("SSH config scan exceeded \(limits.maximumTotalBytes) bytes.")
            return
        }
        filesRead += 1
        totalBytes += data.count

        let text = String(decoding: data, as: UTF8.self)
        appendAliases(from: text)
        let includePatterns = SSHConfigParser.includePatterns(
            in: text,
            limit: limits.maximumIncludePatternsPerFile
        )
        for pattern in includePatterns where !Task.isCancelled {
            for includeURL in expandedIncludeURLs(for: pattern) where !Task.isCancelled {
                scanFile(includeURL, depth: depth + 1)
            }
        }
    }

    private mutating func appendAliases(from text: String) {
        let remaining = limits.maximumAliases - aliases.count
        guard remaining > 0 else { return }
        for alias in SSHConfigParser.concreteHostAliases(in: text, limit: remaining) {
            guard aliasKeys.insert(alias.lowercased()).inserted else { continue }
            aliases.append(alias)
            if aliases.count == limits.maximumAliases {
                warnOnce("SSH host discovery stopped after \(limits.maximumAliases) aliases.")
                return
            }
        }
    }

    private func expandedIncludeURLs(for rawPattern: String) -> [URL] {
        guard let patternURL = includePatternURL(rawPattern) else { return [] }
        let path = patternURL.path
        guard path.contains("*") || path.contains("?") || path.contains("[") else {
            return [patternURL]
        }
        return SSHPathGlob.expand(path: path, maximumMatches: limits.maximumFiles)
    }

    private func includePatternURL(_ rawPattern: String) -> URL? {
        guard !rawPattern.isEmpty else { return nil }
        let expanded = rawPattern.replacingOccurrences(of: "%d", with: homeDirectory.path)
        if expanded == "~" {
            return homeDirectory
        }
        if expanded.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(expanded.dropFirst(2))).standardizedFileURL
        }
        guard !expanded.hasPrefix("~") else { return nil }
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return rootConfigURL.deletingLastPathComponent().appendingPathComponent(expanded).standardizedFileURL
    }

    private mutating func warnOnce(_ warning: String) {
        guard !warnings.contains(warning) else { return }
        warnings.append(warning)
    }
}
