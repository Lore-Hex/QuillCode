import Foundation
import QuillCodeCore

struct ClaudeCodeImportCatalog: Sendable {
    var preview: AgentImportPreview
    var descriptors: [String: ClaudeCodeImportDescriptor]
    var receiptIDs: Set<String>
}

struct ClaudeCodeImportDescriptor: Sendable {
    enum Payload: Sendable {
        case project(URL)
        case transcript(URL, ClaudeCodeTranscriptSummary)
        case instruction(URL)
        case settings(URL)
        case skill(URL)
        case plugin(URL)
        case settingsSection(URL, String)
        case slashCommand(URL)
        case subagent(URL)
    }

    var candidate: AgentImportCandidate
    var payload: Payload
    var sourceRoot: URL
}

enum ClaudeCodeImportDiscovery {
    static let recentChatInterval: TimeInterval = 30 * 24 * 60 * 60
    static let maximumProjects = 64
    static let maximumTranscripts = 200

    static func discover(
        sourceHomeDirectory: URL,
        existingProjects: [ProjectRef],
        receipt: AgentImportReceipt,
        now: Date
    ) -> ClaudeCodeImportCatalog {
        let sourceRoot = sourceHomeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL
        guard AgentImportFileSystem.directory(sourceRoot, inside: sourceHomeDirectory) != nil else {
            return missingSourceCatalog(receipt: receipt)
        }

        let transcripts = recentTranscripts(sourceRoot: sourceRoot, now: now)
        let projectURLs = discoveredProjectURLs(
            sourceHomeDirectory: sourceHomeDirectory,
            existingProjects: existingProjects,
            transcripts: transcripts
        )
        let projects = projectRows(projectURLs, existingProjects: existingProjects)
        var descriptors: [String: ClaudeCodeImportDescriptor] = [:]
        appendCandidates(
            sourceRoot: sourceRoot,
            projectURLs: projectURLs,
            transcripts: transcripts,
            receipt: receipt,
            into: &descriptors
        )
        updateImportState(
            in: &descriptors,
            receipt: receipt,
            projectURLs: projectURLs
        )
        let candidates = descriptors.values.map(\.candidate).sorted(
            by: ClaudeCodeImportCandidateBuilder.sort
        )
        return ClaudeCodeImportCatalog(
            preview: AgentImportPreview(
                source: .claudeCode,
                projects: projects,
                candidates: candidates,
                diagnostics: diagnostics(projects: projects, candidates: candidates)
            ),
            descriptors: descriptors,
            receiptIDs: receipt.candidateIDs
        )
    }

    private static func appendCandidates(
        sourceRoot: URL,
        projectURLs: [URL],
        transcripts: [(URL, ClaudeCodeTranscriptSummary)],
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        ClaudeCodeImportCandidateBuilder.appendProjects(
            projectURLs,
            receipt: receipt,
            into: &descriptors
        )
        ClaudeCodeImportCandidateBuilder.appendSetup(
            root: sourceRoot,
            projectPath: nil,
            receipt: receipt,
            into: &descriptors
        )
        for projectURL in projectURLs {
            ClaudeCodeImportCandidateBuilder.appendSetup(
                root: projectURL.appendingPathComponent(".claude", isDirectory: true),
                projectPath: projectURL.path,
                receipt: receipt,
                into: &descriptors
            )
            ClaudeCodeImportCandidateBuilder.appendInstruction(
                projectURL.appendingPathComponent("CLAUDE.md"),
                sourceRoot: projectURL,
                projectPath: projectURL.path,
                title: "Project instructions for \(projectURL.lastPathComponent)",
                receipt: receipt,
                into: &descriptors
            )
        }
        ClaudeCodeImportCandidateBuilder.appendTranscripts(
            transcripts,
            sourceRoot: sourceRoot,
            projectPaths: Set(projectURLs.map(\.path)),
            receipt: receipt,
            into: &descriptors
        )
    }

    private static func updateImportState(
        in descriptors: inout [String: ClaudeCodeImportDescriptor],
        receipt: AgentImportReceipt,
        projectURLs: [URL]
    ) {
        let availableProjectPaths = Set(projectURLs.map(\.path))
        for id in descriptors.keys {
            guard var descriptor = descriptors[id] else { continue }
            descriptor.candidate.isPreviouslyImported = AgentImportReceiptKey.isFullyImported(
                descriptor.candidate,
                receiptIDs: receipt.candidateIDs,
                availableProjectPaths: availableProjectPaths
            )
            descriptors[id] = descriptor
        }
    }

    private static func recentTranscripts(
        sourceRoot: URL,
        now: Date
    ) -> [(URL, ClaudeCodeTranscriptSummary)] {
        let projectsDirectory = sourceRoot.appendingPathComponent("projects", isDirectory: true)
        guard let directory = AgentImportFileSystem.directory(projectsDirectory, inside: sourceRoot),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(transcriptResourceKeys),
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        var candidates: [(URL, Date)] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "jsonl" {
            guard let modifiedAt = recentTranscriptModificationDate(file, now: now) else { continue }
            candidates.append((file, modifiedAt))
        }
        return candidates
            .sorted { $0.1 > $1.1 }
            .prefix(maximumTranscripts)
            .compactMap { file, _ in
                ClaudeCodeTranscriptParser.parse(
                    fileURL: file,
                    sourceRoot: sourceRoot
                ).map { (file, $0) }
            }
    }

    private static func recentTranscriptModificationDate(_ file: URL, now: Date) -> Date? {
        guard let values = try? file.resourceValues(forKeys: transcriptResourceKeys),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= ClaudeCodeTranscriptParser.maximumFileBytes,
              let modifiedAt = values.contentModificationDate,
              now.timeIntervalSince(modifiedAt) <= recentChatInterval
        else { return nil }
        return modifiedAt
    }

    private static func discoveredProjectURLs(
        sourceHomeDirectory: URL,
        existingProjects: [ProjectRef],
        transcripts: [(URL, ClaudeCodeTranscriptSummary)]
    ) -> [URL] {
        var paths = existingProjects.compactMap { project in
            project.connection.isRemote ? nil : project.path
        }
        paths.append(contentsOf: transcripts.compactMap { $0.1.cwd })
        paths.append(
            contentsOf: registryProjectPaths(
                sourceHomeDirectory.appendingPathComponent(".claude.json"),
                sourceHomeDirectory: sourceHomeDirectory
            )
        )

        var seen = Set<String>()
        return paths.compactMap { rawPath -> URL? in
            guard rawPath.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: rawPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard seen.insert(url.path).inserted,
                  let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                  ),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { return nil }
            return url
        }
        .prefix(maximumProjects)
        .map { $0 }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func registryProjectPaths(
        _ file: URL,
        sourceHomeDirectory: URL
    ) -> [String] {
        guard let data = AgentImportFileSystem.readData(
            file,
            inside: sourceHomeDirectory,
            maximumBytes: 4_000_000
        ),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = object["projects"] as? [String: Any]
        else { return [] }
        return projects.keys.filter { $0.hasPrefix("/") }
    }

    private static func projectRows(
        _ projectURLs: [URL],
        existingProjects: [ProjectRef]
    ) -> [AgentImportProject] {
        let existingPaths = Set(existingProjects.compactMap { project -> String? in
            guard !project.connection.isRemote else { return nil }
            return URL(fileURLWithPath: project.path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
        })
        return projectURLs.map {
            AgentImportProject(
                name: $0.lastPathComponent.isEmpty ? $0.path : $0.lastPathComponent,
                path: $0.path,
                isAlreadyRegistered: existingPaths.contains($0.path)
            )
        }
    }

    private static func diagnostics(
        projects: [AgentImportProject],
        candidates: [AgentImportCandidate]
    ) -> [String] {
        var values: [String] = []
        if candidates.isEmpty { values.append("No supported Claude Code items were found.") }
        if projects.isEmpty {
            values.append(
                "No local Claude Code projects were detected; project-scoped setup cannot be imported yet."
            )
        }
        return values
    }

    private static func missingSourceCatalog(receipt: AgentImportReceipt) -> ClaudeCodeImportCatalog {
        ClaudeCodeImportCatalog(
            preview: AgentImportPreview(
                source: .claudeCode,
                diagnostics: ["Claude Code setup was not found in ~/.claude."]
            ),
            descriptors: [:],
            receiptIDs: receipt.candidateIDs
        )
    }

    private static let transcriptResourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]
}
