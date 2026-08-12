import Darwin
import Foundation
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence

struct QuillCodeDesktopDailyDriverSmokeSeedRequest: Sendable {
    var stateRootPath: String?

    init?(arguments: [String]) {
        guard arguments.contains("--seed-daily-driver-window-smoke") else {
            return nil
        }
        stateRootPath = Self.value(after: "--window-smoke-state-root", in: arguments)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

enum QuillCodeDesktopPerformanceWorkload: String, Equatable, Sendable {
    case firstRunEmpty = "first-run-empty"
    case dailyDriver100Chats = "daily-driver-100-chats"
}

enum QuillCodeDesktopDailyDriverSmokeFixtureError: LocalizedError, Equatable {
    case missingStateRoot
    case stateRootAlreadyExists
    case unsupportedWorkload(String)
    case invalidFixture(String)

    var errorDescription: String? {
        switch self {
        case .missingStateRoot:
            "The daily-driver smoke seed requires --window-smoke-state-root."
        case .stateRootAlreadyExists:
            "The daily-driver smoke state root must not already exist."
        case .unsupportedWorkload(let workload):
            "The packaged performance workload is unsupported: \(workload)"
        case .invalidFixture(let reason):
            "The daily-driver smoke fixture is invalid: \(reason)"
        }
    }
}

enum QuillCodeDesktopDailyDriverSmokeFixture {
    static let chatCount = 100
    static let archivedChatCount = 80
    static let shortThreadTurnCount = 3
    static let selectedThreadTurnCount = 100
    static let markerFileName = "performance-workload.json"
    static let mockCredential = "quillcode-daily-driver-smoke-credential"

    private static let projectID = deterministicUUID(namespace: 0x1000_0000, value: 1)
    private static let baseDate = Date(timeIntervalSince1970: 1_735_689_600)
    private static let topics = [
        "Release verification",
        "Crash recovery",
        "Launch performance",
        "Memory profile",
        "Navigation polish",
        "Updater health",
        "Workspace search",
        "Review workflow",
        "Plugin setup",
        "Keyboard ergonomics"
    ]

    static func runAndReport(_ request: QuillCodeDesktopDailyDriverSmokeSeedRequest) -> Int32 {
        do {
            guard let stateRootPath = request.stateRootPath, !stateRootPath.isEmpty else {
                throw QuillCodeDesktopDailyDriverSmokeFixtureError.missingStateRoot
            }
            let stateRoot = URL(fileURLWithPath: stateRootPath, isDirectory: true)
            try seed(at: stateRoot)
            FileHandle.standardOutput.write(
                Data("Seeded \(QuillCodeDesktopPerformanceWorkload.dailyDriver100Chats.rawValue).\n".utf8)
            )
            return EXIT_SUCCESS
        } catch {
            FileHandle.standardError.write(Data("quill-code-desktop seed failed: \(error)\n".utf8))
            return EXIT_FAILURE
        }
    }

    static func seed(at stateRoot: URL) throws {
        let destination = stateRoot.standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw QuillCodeDesktopDailyDriverSmokeFixtureError.stateRootAlreadyExists
        }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).seed-\(UUID().uuidString)",
            isDirectory: true
        )
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: staging)
            }
        }

        let appState = staging.appendingPathComponent("app-state", isDirectory: true)
        let workspace = staging.appendingPathComponent("workspace", isDirectory: true)
        let destinationWorkspace = destination.appendingPathComponent("workspace", isDirectory: true)
        let paths = QuillCodePaths(home: appState)
        try paths.ensure()
        try QuillSecretStoreFactory.make(for: paths).write(
            mockCredential,
            for: QuillSecretKeys.trustedRouterAPIKey
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let newestDate = baseDate.addingTimeInterval(TimeInterval(chatCount * 3_600))
        let project = ProjectRef(
            id: projectID,
            name: "Quill Cowork Daily Driver",
            path: destinationWorkspace.path,
            lastOpenedAt: newestDate
        )
        try JSONProjectStore(fileURL: paths.projectsFile).save([project])

        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        for ordinal in 1...chatCount {
            try threadStore.save(makeThread(ordinal: ordinal))
        }
        // Performance smoke represents an established daily-driver workspace. Prime per-thread
        // payload summaries outside the measured launch so the package exercises its warm path.
        _ = threadStore.bootstrapListing(
            deferArchivedBefore: .distantFuture,
            maximumResidentActivePayloads: JSONThreadStore.defaultMaximumResidentActivePayloads,
            retainingUsageSince: .distantPast,
            now: .distantFuture
        )

        let marker = Marker(
            schemaVersion: 3,
            workload: QuillCodeDesktopPerformanceWorkload.dailyDriver100Chats.rawValue,
            projectCount: 1,
            chatCount: chatCount,
            archivedChatCount: archivedChatCount,
            shortThreadTurnCount: shortThreadTurnCount,
            selectedThreadTurnCount: selectedThreadTurnCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marker).write(
            to: staging.appendingPathComponent(markerFileName),
            options: .atomic
        )

        try FileManager.default.moveItem(at: staging, to: destination)
        committed = true
    }

    @MainActor
    static func validate(
        workloadID: String,
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopWindowSmokeWorkspaceRoot
    ) throws -> QuillCodeDesktopPerformanceWorkload {
        guard let workload = QuillCodeDesktopPerformanceWorkload(rawValue: workloadID) else {
            throw QuillCodeDesktopDailyDriverSmokeFixtureError.unsupportedWorkload(workloadID)
        }
        guard workload == .dailyDriver100Chats else {
            return workload
        }

        let markerURL = workspaceRoot.root.appendingPathComponent(markerFileName)
        let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: markerURL))
        guard marker == Marker(
            schemaVersion: 3,
            workload: workload.rawValue,
            projectCount: 1,
            chatCount: chatCount,
            archivedChatCount: archivedChatCount,
            shortThreadTurnCount: shortThreadTurnCount,
            selectedThreadTurnCount: selectedThreadTurnCount
        ) else {
            throw QuillCodeDesktopDailyDriverSmokeFixtureError.invalidFixture("marker contract mismatch")
        }

        let root = controller.model.root
        try require(root.trustedRouterAPIKeyConfigured, "returning-user credential state")
        try require(root.projects.count == marker.projectCount, "loaded project count")
        try require(root.threads.count == marker.chatCount, "loaded chat count")
        try require(root.selectedProjectID == projectID, "selected project identity")
        try require(
            root.threads.allSatisfy({ $0.projectID == projectID }),
            "project binding"
        )
        try require(
            root.projects.first.map {
                URL(fileURLWithPath: $0.path, isDirectory: true)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            } == workspaceRoot.workspace
                .resolvingSymlinksInPath()
                .standardizedFileURL,
            "workspace path binding"
        )
        guard let selectedThread = root.threads.first(where: { $0.id == root.selectedThreadID }) else {
            throw QuillCodeDesktopDailyDriverSmokeFixtureError.invalidFixture("selected chat missing")
        }
        try require(selectedThread.id == threadID(ordinal: chatCount), "selected chat identity")
        try require(
            selectedThread.messages.count == marker.selectedThreadTurnCount * 2,
            "selected chat message count"
        )
        try require(
            root.threads.filter(\.isArchived).count == marker.archivedChatCount,
            "archived chat count"
        )
        try require(
            root.threads
                .filter(\.isArchived)
                .allSatisfy({ !$0.payloadResidency.isLoaded && $0.messages.isEmpty }),
            "archived chat payload residency"
        )
        let loadedActiveThreads = root.threads.filter {
            !$0.isArchived && $0.payloadResidency.isLoaded
        }
        try require(
            loadedActiveThreads.count <= JSONThreadStore.defaultMaximumResidentActivePayloads,
            "bounded active chat payload residency"
        )
        try require(
            loadedActiveThreads.allSatisfy {
                $0.id == selectedThread.id
                    || $0.messages.count == marker.shortThreadTurnCount * 2
            },
            "loaded active chat message count"
        )
        try require(
            root.threads
                .filter({ !$0.isArchived && !$0.payloadResidency.isLoaded })
                .allSatisfy({ $0.messages.isEmpty && $0.events.isEmpty }),
            "cold active chat payload residency"
        )
        return workload
    }

    private static func require(_ condition: Bool, _ invariant: String) throws {
        guard condition else {
            throw QuillCodeDesktopDailyDriverSmokeFixtureError.invalidFixture(invariant)
        }
    }

    private static func makeThread(ordinal: Int) -> ChatThread {
        let topic = topics[(ordinal - 1) % topics.count]
        let createdAt = baseDate.addingTimeInterval(TimeInterval(ordinal * 3_600))
        let turnCount = ordinal == chatCount ? selectedThreadTurnCount : shortThreadTurnCount
        return ChatThread(
            id: threadID(ordinal: ordinal),
            title: "\(topic) \(String(format: "%03d", ordinal))",
            projectID: projectID,
            messages: makeMessages(
                threadOrdinal: ordinal,
                topic: topic,
                turnCount: turnCount,
                createdAt: createdAt
            ),
            isPinned: ordinal == chatCount,
            isArchived: ordinal <= archivedChatCount,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(TimeInterval(turnCount * 120))
        )
    }

    private static func makeMessages(
        threadOrdinal: Int,
        topic: String,
        turnCount: Int,
        createdAt: Date
    ) -> [ChatMessage] {
        (1...turnCount).flatMap { turn in
            let userOrdinal = turn * 2 - 1
            let assistantOrdinal = turn * 2
            return [
                ChatMessage(
                    id: messageID(threadOrdinal: threadOrdinal, ordinal: userOrdinal),
                    role: .user,
                    content: "Review \(topic.lowercased()) for daily task \(threadOrdinal), "
                        + "turn \(turn). Identify the highest-impact next step and keep the "
                        + "response concise.",
                    createdAt: createdAt.addingTimeInterval(TimeInterval(userOrdinal * 60))
                ),
                ChatMessage(
                    id: messageID(threadOrdinal: threadOrdinal, ordinal: assistantOrdinal),
                    role: .assistant,
                    content: "Turn \(turn) is complete. The next \(topic.lowercased()) action "
                        + "is recorded with checks for speed, resilience, and usability.",
                    createdAt: createdAt.addingTimeInterval(TimeInterval(assistantOrdinal * 60))
                )
            ]
        }
    }

    private static func threadID(ordinal: Int) -> UUID {
        deterministicUUID(namespace: 0x2000_0000, value: ordinal)
    }

    private static func messageID(threadOrdinal: Int, ordinal: Int) -> UUID {
        deterministicUUID(namespace: 0x3000_0000 + UInt32(threadOrdinal), value: ordinal)
    }

    private static func deterministicUUID(namespace: UInt32, value: Int) -> UUID {
        let value = UInt64(value)
        return UUID(uuid: (
            UInt8((namespace >> 24) & 0xff), UInt8((namespace >> 16) & 0xff),
            UInt8((namespace >> 8) & 0xff), UInt8(namespace & 0xff),
            0x00, 0x00, 0x40, 0x00, 0x80, 0x00,
            UInt8((value >> 40) & 0xff), UInt8((value >> 32) & 0xff),
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ))
    }

    private struct Marker: Codable, Equatable {
        var schemaVersion: Int
        var workload: String
        var projectCount: Int
        var chatCount: Int
        var archivedChatCount: Int
        var shortThreadTurnCount: Int
        var selectedThreadTurnCount: Int
    }
}
