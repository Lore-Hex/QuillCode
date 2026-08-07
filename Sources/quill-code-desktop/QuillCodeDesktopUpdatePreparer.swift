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
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopPreparedUpdate
}

protocol QuillCodeDesktopUpdateDownloading: Sendable {
    func download(from url: URL, to destinationURL: URL, maximumBytes: Int64) async throws
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
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopPreparedUpdate {
        let workspaceURL = try await makeCleanWorkspace(for: release)
        let archiveURL = workspaceURL.appendingPathComponent(release.asset.name, isDirectory: false)
        try await downloader.download(
            from: release.asset.url,
            to: archiveURL,
            maximumBytes: release.asset.sizeBytes
        )
        try Task.checkCancellation()

        try await Task.detached(priority: .utility) {
            try Self.verifyArchive(
                at: archiveURL,
                expectedSize: release.asset.sizeBytes,
                expectedSHA256: release.asset.sha256
            )
        }.value

        let extractedURL = workspaceURL.appendingPathComponent("Extracted", isDirectory: true)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: extractedURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let result = try QuillCodeDesktopUpdateProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, extractedURL.path]
            )
            guard result.exitCode == 0 else {
                throw QuillCodeDesktopUpdateError.invalidApplication(result.failureSummary)
            }
        }.value

        let applicationURL = try await Task.detached(priority: .utility) {
            let appURL = try Self.singleApplication(in: extractedURL)
            try Self.validateContainedLinks(in: extractedURL)
            try QuillCodeDesktopDownloadedApplicationValidator.validate(
                appURL,
                release: release,
                configuration: configuration
            )
            return appURL
        }.value

        return QuillCodeDesktopPreparedUpdate(
            release: release,
            applicationURL: applicationURL,
            workspaceURL: workspaceURL
        )
    }

    private func makeCleanWorkspace(for release: QuillCodeDesktopUpdateRelease) async throws -> URL {
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
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw QuillCodeDesktopUpdateError.checksumMismatch
        }
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
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw QuillCodeDesktopUpdateError.invalidApplication("the app archive could not be inspected")
        }

        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else { continue }
            let resolvedPath = itemURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolvedPath == rootURL.standardizedFileURL.path || resolvedPath.hasPrefix(canonicalRoot) else {
                throw QuillCodeDesktopUpdateError.invalidApplication(
                    "the app archive contains a link outside its bundle"
                )
            }
        }
    }
}

struct QuillCodeDesktopUpdateDownloader: QuillCodeDesktopUpdateDownloading, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    func download(from url: URL, to destinationURL: URL, maximumBytes: Int64) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        request.setValue("Quill-Cowork-Updater/1", forHTTPHeaderField: "User-Agent")

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.expectedContentLength <= 0 || response.expectedContentLength <= maximumBytes
        else {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) <= maximumBytes else {
            throw QuillCodeDesktopUpdateError.downloadSizeMismatch
        }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw QuillCodeDesktopUpdateError.installationFailed("the download could not be staged")
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }
}
