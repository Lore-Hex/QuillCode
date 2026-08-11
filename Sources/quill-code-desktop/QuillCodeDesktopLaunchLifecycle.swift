import AppKit
import Darwin
import Foundation

enum QuillCodeDesktopLaunchPhase: String, Codable, Sendable {
    case starting
    case ready
    case terminating

    var incidentDescription: String {
        switch self {
        case .starting:
            "during startup"
        case .ready:
            "while the app was running"
        case .terminating:
            "while the app was quitting"
        }
    }
}

struct QuillCodeDesktopLaunchRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var launchID: UUID
    var processIdentifier: Int32
    var startedAt: Date
    var phase: QuillCodeDesktopLaunchPhase
    var metadata: QuillCodeDesktopBuildMetadata

    init(
        launchID: UUID = UUID(),
        processIdentifier: Int32,
        startedAt: Date,
        phase: QuillCodeDesktopLaunchPhase = .starting,
        metadata: QuillCodeDesktopBuildMetadata
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.launchID = launchID
        self.processIdentifier = processIdentifier
        self.startedAt = startedAt
        self.phase = phase
        self.metadata = metadata
    }

    var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && processIdentifier > 0
            && metadata.isSafeForIncidentReporting
    }
}

struct QuillCodeDesktopUnexpectedExit: Identifiable, Equatable, Sendable {
    static let maximumIncidentAge: TimeInterval = 30 * 24 * 60 * 60
    static let maximumFutureClockSkew: TimeInterval = 5 * 60

    var id: UUID { launchID }
    var launchID: UUID
    var startedAt: Date
    var phase: QuillCodeDesktopLaunchPhase
    var metadata: QuillCodeDesktopBuildMetadata

    init?(record: QuillCodeDesktopLaunchRecord, now: Date) {
        let age = now.timeIntervalSince(record.startedAt)
        guard record.isValid,
              record.phase != .terminating,
              age <= Self.maximumIncidentAge,
              age >= -Self.maximumFutureClockSkew
        else { return nil }
        self.launchID = record.launchID
        self.startedAt = record.startedAt
        self.phase = record.phase
        self.metadata = record.metadata
    }

    var userMessage: String {
        if requiresRecoveryStartup {
            return "The previous session ended during startup. Automatic background work is paused "
                + "for this launch to avoid repeating the problem, including project refreshes, "
                + "automations, and account checks. Your saved workspace is available. Previous build: "
                + "\(metadata.version) (\(metadata.build))."
        }
        return "The previous session ended \(phase.incidentDescription) without a normal quit. "
            + "Your saved workspace reopened, but work from an in-progress command may be incomplete. "
            + "Previous build: \(metadata.version) (\(metadata.build))."
    }

    var requiresRecoveryStartup: Bool {
        phase == .starting
    }
}

enum QuillCodeDesktopStartupMode: Equatable, Sendable {
    case normal
    case recovery

    init(unexpectedExit: QuillCodeDesktopUnexpectedExit?) {
        self = unexpectedExit?.requiresRecoveryStartup == true ? .recovery : .normal
    }

    var pausesAutomaticWorkspaceServices: Bool {
        self == .recovery
    }
}

struct QuillCodeDesktopLaunchSession: Equatable, Sendable {
    var currentRecord: QuillCodeDesktopLaunchRecord
    var unexpectedExit: QuillCodeDesktopUnexpectedExit?
}

struct QuillCodeDesktopLaunchStore {
    private static let maximumRecordBytes = 16 * 1_024
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
    }

    static func standard() -> Self {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quillcode/runtime", isDirectory: true)
        return Self(fileURL: directory.appendingPathComponent("active-launch.json"))
    }

    func beginLaunch(
        metadata: QuillCodeDesktopBuildMetadata,
        now: Date = Date(),
        processIdentifier: Int32 = getpid(),
        processIsRunning: (Int32) -> Bool = QuillCodeDesktopProcessInspector.isRunning
    ) throws -> QuillCodeDesktopLaunchSession {
        try withExclusiveLock {
            let previous = loadRecordUnlocked()
            let current = QuillCodeDesktopLaunchRecord(
                processIdentifier: processIdentifier,
                startedAt: now,
                metadata: metadata
            )
            try writeRecordUnlocked(current)

            let incident = previous.flatMap { record -> QuillCodeDesktopUnexpectedExit? in
                guard record.processIdentifier != processIdentifier,
                      !processIsRunning(record.processIdentifier)
                else { return nil }
                return QuillCodeDesktopUnexpectedExit(record: record, now: now)
            }
            return QuillCodeDesktopLaunchSession(currentRecord: current, unexpectedExit: incident)
        }
    }

    func markReady(launchID: UUID) throws {
        try withExclusiveLock {
            guard var record = loadRecordUnlocked(), record.launchID == launchID else { return }
            guard record.phase != .ready else { return }
            record.phase = .ready
            try writeRecordUnlocked(record)
        }
    }

    func finishLaunch(launchID: UUID) throws {
        try withExclusiveLock {
            guard var record = loadRecordUnlocked(), record.launchID == launchID else { return }
            record.phase = .terminating
            try writeRecordUnlocked(record)
            try fileManager.removeItem(at: fileURL)
        }
    }

    func currentRecord() throws -> QuillCodeDesktopLaunchRecord? {
        try withExclusiveLock { loadRecordUnlocked() }
    }

    private var lockURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("lock")
    }

    private func withExclusiveLock<Value>(_ operation: () throws -> Value) throws -> Value {
        try ensurePrivateDirectory()
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(Self.filePermissions))
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: lockURL.path])
        }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: lockURL.path])
        }
        defer { flock(descriptor, LOCK_UN) }
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: lockURL.path
        )
        return try operation()
    }

    private func ensurePrivateDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    private func loadRecordUnlocked() -> QuillCodeDesktopLaunchRecord? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= Self.maximumRecordBytes,
              let data = try? Data(contentsOf: fileURL),
              data.count <= Self.maximumRecordBytes
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(QuillCodeDesktopLaunchRecord.self, from: data)
    }

    private func writeRecordUnlocked(_ record: QuillCodeDesktopLaunchRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= Self.maximumRecordBytes else {
            throw CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: fileURL.path
        )
    }
}

enum QuillCodeDesktopProcessInspector {
    static func isRunning(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if Darwin.kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

@MainActor
final class QuillCodeDesktopLaunchLifecycleController: NSObject {
    private let store: QuillCodeDesktopLaunchStore
    private let metadata: QuillCodeDesktopBuildMetadata
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let processIdentifier: Int32
    private let processIsRunning: (Int32) -> Bool
    private(set) var unexpectedExit: QuillCodeDesktopUnexpectedExit?
    private var currentLaunchID: UUID?
    private var didStart = false

    init(
        store: QuillCodeDesktopLaunchStore = .standard(),
        metadata: QuillCodeDesktopBuildMetadata,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        processIdentifier: Int32 = getpid(),
        processIsRunning: @escaping (Int32) -> Bool = QuillCodeDesktopProcessInspector.isRunning
    ) {
        self.store = store
        self.metadata = metadata
        self.notificationCenter = notificationCenter
        self.now = now
        self.processIdentifier = processIdentifier
        self.processIsRunning = processIsRunning
        super.init()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @discardableResult
    func startIfNeeded() -> QuillCodeDesktopUnexpectedExit? {
        guard !didStart else { return unexpectedExit }
        didStart = true
        do {
            let session = try store.beginLaunch(
                metadata: metadata,
                now: now(),
                processIdentifier: processIdentifier,
                processIsRunning: processIsRunning
            )
            currentLaunchID = session.currentRecord.launchID
            unexpectedExit = session.unexpectedExit
            notificationCenter.addObserver(
                self,
                selector: #selector(applicationWillTerminate),
                name: NSApplication.willTerminateNotification,
                object: nil
            )
        } catch {
            currentLaunchID = nil
            unexpectedExit = nil
        }
        return unexpectedExit
    }

    func markReady() {
        guard let currentLaunchID else { return }
        try? store.markReady(launchID: currentLaunchID)
    }

    func takeUnexpectedExit() -> QuillCodeDesktopUnexpectedExit? {
        defer { unexpectedExit = nil }
        return unexpectedExit
    }

    func finishCurrentLaunch() {
        guard let currentLaunchID else { return }
        try? store.finishLaunch(launchID: currentLaunchID)
        self.currentLaunchID = nil
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        finishCurrentLaunch()
    }
}
