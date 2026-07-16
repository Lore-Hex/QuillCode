import Foundation
import QuillCodeTools

struct AppServerFuzzyFileSearchResult: Sendable, Equatable {
    enum MatchType: String, Sendable {
        case file
        case directory
    }

    var root: String
    var path: String
    var matchType: MatchType
    var fileName: String
    var score: Int
    var indices: [Int]

    var jsonValue: CLIJSONValue {
        .object([
            "root": .string(root),
            "path": .string(path),
            "match_type": .string(matchType.rawValue),
            "file_name": .string(fileName),
            "score": .number(Double(score)),
            "indices": .array(indices.map { .number(Double($0)) })
        ])
    }
}

struct AppServerFuzzyFileSearchIndex: Sendable {
    struct Entry: Sendable {
        var root: String
        var path: String
        var fileName: String
        var matchType: AppServerFuzzyFileSearchResult.MatchType
    }

    var entries: [Entry]
}

enum AppServerFuzzyFileSearchEngine {
    static let matchLimit = 50
    static let maximumRoots = 32
    static let maximumRootBytes = 4_096
    static let maximumQueryCharacters = 256
    static let maximumIndexedEntries = 100_000
    static let maximumEntriesPerRoot = 20_000

    static func buildIndex(roots: [String], relativeTo currentDirectory: URL) -> AppServerFuzzyFileSearchIndex {
        var entries: [AppServerFuzzyFileSearchIndex.Entry] = []
        entries.reserveCapacity(min(maximumIndexedEntries, roots.count * 4_000))

        for root in roots {
            guard !Task.isCancelled, entries.count < maximumIndexedEntries else { break }
            let rootURL = resolvedRoot(root, relativeTo: currentDirectory)
            let remaining = maximumIndexedEntries - entries.count
            let index = WorkspaceFileIndexer(workspaceRoot: rootURL).index(
                maxFiles: min(maximumEntriesPerRoot, remaining)
            )
            entries.append(contentsOf: index.entries.prefix(remaining).map { entry in
                AppServerFuzzyFileSearchIndex.Entry(
                    root: root,
                    path: entry.path,
                    fileName: entry.name,
                    matchType: entry.kind == .directory ? .directory : .file
                )
            })
        }

        return AppServerFuzzyFileSearchIndex(entries: entries)
    }

    static func search(
        query: String,
        index: AppServerFuzzyFileSearchIndex
    ) -> [AppServerFuzzyFileSearchResult] {
        guard !query.isEmpty else { return [] }

        var matches: [AppServerFuzzyFileSearchResult] = []
        matches.reserveCapacity(matchLimit)
        for entry in index.entries {
            guard !Task.isCancelled else { break }
            guard let match = AppServerFuzzyPathMatcher.match(query: query, path: entry.path) else {
                continue
            }
            matches.append(AppServerFuzzyFileSearchResult(
                root: entry.root,
                path: entry.path,
                matchType: entry.matchType,
                fileName: entry.fileName,
                score: match.score,
                indices: match.indices
            ))
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.root < $1.root
        }
        return Array(matches.prefix(matchLimit))
    }

    private static func resolvedRoot(_ root: String, relativeTo currentDirectory: URL) -> URL {
        guard !root.hasPrefix("/") else {
            return URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        }
        return currentDirectory
            .appendingPathComponent(root, isDirectory: true)
            .standardizedFileURL
    }
}

enum AppServerFuzzyPathMatcher {
    struct Match: Sendable, Equatable {
        var score: Int
        var indices: [Int]
    }

    static func match(query: String, path: String) -> Match? {
        let needle = Array(query.lowercased())
        let haystack = Array(path.lowercased())
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        var best: Match?
        for start in haystack.indices where haystack[start] == needle[0] {
            guard let indices = greedyIndices(needle: needle, haystack: haystack, start: start) else {
                continue
            }
            let candidate = Match(score: score(queryCount: needle.count, indices: indices), indices: indices)
            if isBetter(candidate, than: best) { best = candidate }
        }
        return best
    }

    private static func greedyIndices(
        needle: [Character],
        haystack: [Character],
        start: Int
    ) -> [Int]? {
        var indices = [start]
        var cursor = start + 1
        for character in needle.dropFirst() {
            guard let index = haystack[cursor...].firstIndex(of: character) else { return nil }
            indices.append(index)
            cursor = index + 1
        }
        return indices
    }

    private static func score(queryCount: Int, indices: [Int]) -> Int {
        let leadingPenalty = (indices[0] * 3 + 1) / 2
        let gapPenalty = zip(indices, indices.dropFirst()).reduce(into: 0) { penalty, pair in
            let skipped = pair.1 - pair.0 - 1
            guard skipped > 0 else { return }
            penalty += skipped * 6
            if skipped > 1 { penalty += 1 }
        }
        return max(1, queryCount * 28 - leadingPenalty - gapPenalty)
    }

    private static func isBetter(_ candidate: Match, than current: Match?) -> Bool {
        guard let current else { return true }
        if candidate.score != current.score { return candidate.score > current.score }
        return candidate.indices.lexicographicallyPrecedes(current.indices)
    }
}

struct AppServerFuzzyFileSearchRequest: Sendable {
    var query: String
    var roots: [String]
    var cancellationToken: String?

    init(params: CLIJSONValue) throws {
        let params = try AppServerParams(params)
        self.query = try params.requiredString("query", allowingEmpty: true)
        self.roots = try Self.roots(from: params)
        self.cancellationToken = try params.optionalString("cancellationToken")
        try Self.validateQuery(query)
    }

    static func roots(from params: AppServerParams) throws -> [String] {
        guard let values = try params.optionalArray("roots") else {
            throw AppServerRPCError.invalidParams("roots is required")
        }
        guard values.count <= AppServerFuzzyFileSearchEngine.maximumRoots else {
            throw AppServerRPCError.invalidParams(
                "roots may contain at most \(AppServerFuzzyFileSearchEngine.maximumRoots) entries"
            )
        }
        return try values.enumerated().map { index, value in
            guard let root = value.stringValue else {
                throw AppServerRPCError.invalidParams("roots[\(index)] must be a string")
            }
            guard root.utf8.count <= AppServerFuzzyFileSearchEngine.maximumRootBytes else {
                throw AppServerRPCError.invalidParams("roots[\(index)] is too long")
            }
            return root
        }
    }

    static func validateQuery(_ query: String) throws {
        guard query.count <= AppServerFuzzyFileSearchEngine.maximumQueryCharacters else {
            throw AppServerRPCError.invalidParams(
                "query may contain at most \(AppServerFuzzyFileSearchEngine.maximumQueryCharacters) characters"
            )
        }
    }
}

struct AppServerActiveFuzzyFileSearch: Sendable {
    var cancellationToken: String?
    var task: Task<Void, Never>
}

struct AppServerFuzzyFileSearchSession: Sendable {
    var indexTask: Task<AppServerFuzzyFileSearchIndex, Never>
    var queryGeneration: UInt64 = 0
    var queryTask: Task<Void, Never>?

    func cancel() {
        indexTask.cancel()
        queryTask?.cancel()
    }
}

extension AppServerSession {
    func startFuzzyFileSearchRequest(id: AppServerRequestID, params: CLIJSONValue) throws {
        let request = try AppServerFuzzyFileSearchRequest(params: params)
        if let token = request.cancellationToken,
           let activeID = fuzzyFileSearchTokens[token],
           let active = activeFuzzyFileSearches[activeID] {
            active.task.cancel()
        }

        let activeID = UUID()
        let currentDirectory = self.currentDirectory
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let index = AppServerFuzzyFileSearchEngine.buildIndex(
                roots: request.roots,
                relativeTo: currentDirectory
            )
            let files = AppServerFuzzyFileSearchEngine.search(query: request.query, index: index)
            await self?.completeFuzzyFileSearchRequest(
                activeID: activeID,
                id: id,
                cancellationToken: request.cancellationToken,
                files: files
            )
        }
        activeFuzzyFileSearches[activeID] = AppServerActiveFuzzyFileSearch(
            cancellationToken: request.cancellationToken,
            task: task
        )
        if let token = request.cancellationToken { fuzzyFileSearchTokens[token] = activeID }
    }

    func startFuzzyFileSearchSession(_ params: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "fuzzyFileSearch/sessionStart")
        let params = try AppServerParams(params)
        let sessionID = try params.requiredString("sessionId")
        let roots = try AppServerFuzzyFileSearchRequest.roots(from: params)
        fuzzyFileSearchSessions.removeValue(forKey: sessionID)?.cancel()

        let currentDirectory = self.currentDirectory
        let indexTask = Task.detached(priority: .userInitiated) {
            AppServerFuzzyFileSearchEngine.buildIndex(roots: roots, relativeTo: currentDirectory)
        }
        fuzzyFileSearchSessions[sessionID] = AppServerFuzzyFileSearchSession(indexTask: indexTask)
        return .object([:])
    }

    func updateFuzzyFileSearchSession(_ params: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "fuzzyFileSearch/sessionUpdate")
        let params = try AppServerParams(params)
        let sessionID = try params.requiredString("sessionId")
        let query = try params.requiredString("query", allowingEmpty: true)
        try AppServerFuzzyFileSearchRequest.validateQuery(query)
        guard var session = fuzzyFileSearchSessions[sessionID] else {
            throw AppServerRPCError.invalidRequest("fuzzy file search session not found: \(sessionID)")
        }

        session.queryTask?.cancel()
        session.queryGeneration &+= 1
        let generation = session.queryGeneration
        let indexTask = session.indexTask
        session.queryTask = Task.detached(priority: .userInitiated) { [weak self] in
            let index = await indexTask.value
            guard !Task.isCancelled else { return }
            let files = AppServerFuzzyFileSearchEngine.search(query: query, index: index)
            guard !Task.isCancelled else { return }
            await self?.publishFuzzyFileSearchSession(
                sessionID: sessionID,
                generation: generation,
                query: query,
                files: files
            )
        }
        fuzzyFileSearchSessions[sessionID] = session
        return .object([:])
    }

    func stopFuzzyFileSearchSession(_ params: CLIJSONValue) throws -> CLIJSONValue {
        try requireExperimentalAPI(for: "fuzzyFileSearch/sessionStop")
        let params = try AppServerParams(params)
        let sessionID = try params.requiredString("sessionId")
        fuzzyFileSearchSessions.removeValue(forKey: sessionID)?.cancel()
        return .object([:])
    }

    func cancelAllFuzzyFileSearches() async {
        let activeTasks = activeFuzzyFileSearches.values.map(\.task)
        let sessions = Array(fuzzyFileSearchSessions.values)
        for task in activeTasks { task.cancel() }
        for session in sessions { session.cancel() }
        for task in activeTasks { await task.value }
        for session in sessions {
            _ = await session.indexTask.value
            await session.queryTask?.value
        }
        activeFuzzyFileSearches.removeAll()
        fuzzyFileSearchTokens.removeAll()
        fuzzyFileSearchSessions.removeAll()
    }

    private func completeFuzzyFileSearchRequest(
        activeID: UUID,
        id: AppServerRequestID,
        cancellationToken: String?,
        files: [AppServerFuzzyFileSearchResult]
    ) async {
        guard activeFuzzyFileSearches.removeValue(forKey: activeID) != nil else { return }
        if let cancellationToken, fuzzyFileSearchTokens[cancellationToken] == activeID {
            fuzzyFileSearchTokens.removeValue(forKey: cancellationToken)
        }
        guard !inputFinished else { return }
        await send(.response(id: id, result: .object([
            "files": .array(files.map(\.jsonValue))
        ])))
    }

    private func publishFuzzyFileSearchSession(
        sessionID: String,
        generation: UInt64,
        query: String,
        files: [AppServerFuzzyFileSearchResult]
    ) async {
        guard !inputFinished,
              fuzzyFileSearchSessions[sessionID]?.queryGeneration == generation else { return }
        await sendNotification("fuzzyFileSearch/sessionUpdated", params: .object([
            "sessionId": .string(sessionID),
            "query": .string(query),
            "files": .array(files.map(\.jsonValue))
        ]))

        guard !inputFinished,
              fuzzyFileSearchSessions[sessionID]?.queryGeneration == generation else { return }
        await sendNotification("fuzzyFileSearch/sessionCompleted", params: .object([
            "sessionId": .string(sessionID)
        ]))
    }
}
