import CryptoKit
import Foundation

struct QuillCodeDesktopPreparedUpdate: Equatable, Sendable {
    var release: QuillCodeDesktopUpdateRelease
    var applicationURL: URL
    var workspaceURL: URL
}

protocol QuillCodeDesktopUpdatePreparing: Sendable {
    func prepare(
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        progress: @escaping @Sendable (QuillCodeDesktopUpdatePreparationProgress) -> Void
    ) async throws -> QuillCodeDesktopPreparedUpdate
}

extension QuillCodeDesktopUpdatePreparing {
    func prepare(
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopPreparedUpdate {
        try await prepare(release: release, configuration: configuration, progress: { _ in })
    }
}

struct QuillCodeDesktopUpdatePreparer: QuillCodeDesktopUpdatePreparing, Sendable {
    private let downloader: any QuillCodeDesktopUpdateDownloading
    private let cacheRoot: URL?

    init(
        downloader: any QuillCodeDesktopUpdateDownloading = QuillCodeDesktopUpdateDownloader(),
        cacheRoot: URL? = nil
    ) {
        self.downloader = downloader
        self.cacheRoot = cacheRoot
    }

    func prepare(
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        progress: @escaping @Sendable (QuillCodeDesktopUpdatePreparationProgress) -> Void
    ) async throws -> QuillCodeDesktopPreparedUpdate {
        let workspaceURL = try await makeCleanWorkspace(for: release)
        do {
            let archiveURL = workspaceURL.appendingPathComponent(release.asset.name, isDirectory: false)
            progress(.downloading(receivedBytes: 0, totalBytes: release.asset.sizeBytes))
            try await downloader.download(
                from: release.asset.url,
                to: archiveURL,
                maximumBytes: release.asset.sizeBytes,
                progress: { receivedBytes in
                    progress(.downloading(
                        receivedBytes: receivedBytes,
                        totalBytes: release.asset.sizeBytes
                    ))
                }
            )
            try Task.checkCancellation()

            progress(.verifying)
            try await Self.verifyArchiveAsync(
                at: archiveURL,
                expectedSize: release.asset.sizeBytes,
                expectedSHA256: release.asset.sha256
            )

            let extractedURL = workspaceURL.appendingPathComponent("Extracted", isDirectory: true)
            progress(.extracting)
            try await Self.runCancellableUtilityOperation {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(
                    at: extractedURL,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            let extractionResult = try await QuillCodeDesktopUpdateProcessRunner.runAsync(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, extractedURL.path],
                timeout: QuillCodeDesktopUpdateProcessRunner.extractionTimeout
            )
            guard extractionResult.exitCode == 0 else {
                throw QuillCodeDesktopUpdateError.invalidApplication(
                    extractionResult.failureSummary
                )
            }

            progress(.validatingApplication)
            let applicationURL = try await Self.runCancellableUtilityOperation {
                try Task.checkCancellation()
                let appURL = try Self.singleApplication(in: extractedURL)
                try Self.validateContainedLinks(in: extractedURL)
                return appURL
            }
            try await QuillCodeDesktopDownloadedApplicationValidator.validateForPreparation(
                applicationURL,
                release: release,
                configuration: configuration
            )

            return QuillCodeDesktopPreparedUpdate(
                release: release,
                applicationURL: applicationURL,
                workspaceURL: workspaceURL
            )
        } catch {
            await Self.removeFailedWorkspace(at: workspaceURL)
            throw error
        }
    }

    func makeCleanWorkspace(for release: QuillCodeDesktopUpdateRelease) async throws -> URL {
        let configuredCacheRoot = cacheRoot
        return try await Task.detached(priority: .utility) {
            let root = try configuredCacheRoot ?? Self.defaultCacheRoot()
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let workspace = root.appendingPathComponent(
                "\(release.commit.prefix(12))-\(release.build)",
                isDirectory: true
            )
            let staleEntries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: []
            )
            for entry in staleEntries where entry.standardizedFileURL != workspace.standardizedFileURL {
                try? FileManager.default.removeItem(at: entry)
            }
            if FileManager.default.fileExists(atPath: workspace.path) {
                try FileManager.default.removeItem(at: workspace)
            }
            try FileManager.default.createDirectory(
                at: workspace,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return workspace
        }.value
    }

    private static func defaultCacheRoot() throws -> URL {
        try QuillCodeDesktopUpdatePaths.cacheRoot()
    }

    static func verifyArchive(
        at archiveURL: URL,
        expectedSize: Int64,
        expectedSHA256: String
    ) throws {
        try verifyArchive(
            at: archiveURL,
            expectedSize: expectedSize,
            expectedSHA256: expectedSHA256,
            checkCancellation: {}
        )
    }

    static func verifyArchiveAsync(
        at archiveURL: URL,
        expectedSize: Int64,
        expectedSHA256: String
    ) async throws {
        try await runCancellableUtilityOperation {
            try verifyArchive(
                at: archiveURL,
                expectedSize: expectedSize,
                expectedSHA256: expectedSHA256,
                checkCancellation: { try Task.checkCancellation() }
            )
        }
    }

    private static func verifyArchive(
        at archiveURL: URL,
        expectedSize: Int64,
        expectedSHA256: String,
        checkCancellation: () throws -> Void
    ) throws {
        try checkCancellation()
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? -1) == expectedSize
        else {
            throw QuillCodeDesktopUpdateError.downloadSizeMismatch
        }

        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try checkCancellation()
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        try checkCancellation()
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw QuillCodeDesktopUpdateError.checksumMismatch
        }
    }

    private static func removeFailedWorkspace(at workspaceURL: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: workspaceURL)
        }.value
    }

    private static func singleApplication(in extractedURL: URL) throws -> URL {
        let children = try FileManager.default.contentsOfDirectory(
            at: extractedURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let applications = children.filter { child in
            child.pathExtension == "app" &&
                (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard applications.count == 1 else {
            throw QuillCodeDesktopUpdateError.invalidApplication(
                "the archive must contain exactly one app bundle"
            )
        }
        return applications[0]
    }

    private static func validateContainedLinks(in rootURL: URL) throws {
        let canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw QuillCodeDesktopUpdateError.invalidApplication("the app archive could not be inspected")
        }

        for case let itemURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else { continue }
            let resolvedPath = itemURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolvedPath == rootURL.standardizedFileURL.path || resolvedPath.hasPrefix(canonicalRoot) else {
                throw QuillCodeDesktopUpdateError.invalidApplication(
                    "the app archive contains a link outside its bundle"
                )
            }
        }
        guard !enumerationFailed else {
            throw QuillCodeDesktopUpdateError.invalidApplication("the app archive could not be inspected")
        }
    }

    private static func runCancellableUtilityOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .utility, operation: operation)
        let value = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        return value
    }
}
