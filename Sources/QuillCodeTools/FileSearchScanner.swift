import Foundation

struct FileSearchResult: Sendable, Hashable {
    var output: FileSearchToolOutput
    var artifacts: [String]
}

struct FileSearchScanner: Sendable {
    var pathResolver: FileWorkspacePathResolver

    func search(query: String, path: String, maxResults: Int?) throws -> FileSearchResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw FileToolError.emptySearchQuery
        }

        let searchPath = pathResolver.normalizedDirectoryPath(path)
        let searchRoot = try pathResolver.resolve(searchPath)
        guard FileManager.default.fileExists(atPath: searchRoot.path) else {
            throw FileToolError.pathNotFound(path)
        }

        let limit = FileToolLimits.boundedSearchResultLimit(maxResults)
        var matches: [FileSearchMatch] = []
        let scan = scanSearchableFiles(
            startingAt: searchRoot,
            query: normalizedQuery,
            limit: limit,
            matches: &matches
        )
        let output = FileSearchToolOutput(
            query: normalizedQuery,
            path: pathResolver.relativePath(for: searchRoot),
            matches: matches,
            scannedFiles: scan.scannedFiles,
            skippedFiles: scan.skippedFiles,
            truncated: scan.truncated
        )
        return FileSearchResult(
            output: output,
            artifacts: Array(Set(matches.map { pathResolver.workspaceRoot.appendingPathComponent($0.path).path }))
                .sorted()
        )
    }

    private func scanSearchableFiles(
        startingAt url: URL,
        query: String,
        limit: Int,
        matches: inout [FileSearchMatch]
    ) -> FileSearchScan {
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var scan = FileSearchScan()
        guard isDirectory.boolValue else {
            _ = scanFile(url, query: query, limit: limit, matches: &matches, scan: &scan)
            return scan
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return scan
        }

        for case let candidate as URL in enumerator {
            if shouldSkipSearchDescendant(candidate) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            guard scanFile(candidate, query: query, limit: limit, matches: &matches, scan: &scan) else {
                break
            }
        }
        return scan
    }

    private func scanFile(
        _ fileURL: URL,
        query: String,
        limit: Int,
        matches: inout [FileSearchMatch],
        scan: inout FileSearchScan
    ) -> Bool {
        if scan.scannedFiles >= FileToolLimits.maxSearchScannedFiles || matches.count >= limit {
            scan.truncated = true
            return false
        }

        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else {
            scan.skippedFiles += 1
            return true
        }
        if (values?.fileSize ?? 0) > FileToolLimits.maxSearchFileBytes {
            scan.skippedFiles += 1
            return true
        }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            scan.skippedFiles += 1
            return true
        }

        scan.scannedFiles += 1
        appendMatches(in: text, fileURL: fileURL, query: query, limit: limit, matches: &matches)
        if matches.count >= limit {
            scan.truncated = true
            return false
        }
        return true
    }

    private func shouldSkipSearchDescendant(_ url: URL) -> Bool {
        guard FileToolLimits.excludedWorkspaceDirectoryNames.contains(url.lastPathComponent) else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func appendMatches(
        in text: String,
        fileURL: URL,
        query: String,
        limit: Int,
        matches: inout [FileSearchMatch]
    ) {
        let lowerQuery = query.lowercased()
        for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
            guard matches.count < limit else { return }
            guard line.lowercased().contains(lowerQuery) else { continue }
            matches.append(FileSearchMatch(
                path: pathResolver.relativePath(for: fileURL),
                line: offset + 1,
                preview: FileToolLimits.boundedSearchPreview(line)
            ))
        }
    }
}
