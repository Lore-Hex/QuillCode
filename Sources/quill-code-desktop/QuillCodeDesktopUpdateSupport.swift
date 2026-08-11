import Foundation

struct QuillCodeDesktopUpdateLaunchHandshake: Equatable, Sendable {
    static let argument = "--quillcode-update-handshake"

    private let url: URL
    private let cacheRoot: URL

    init?(arguments: [String] = CommandLine.arguments) {
        guard let cacheRoot = try? QuillCodeDesktopUpdatePaths.cacheRoot() else {
            return nil
        }
        self.init(arguments: arguments, cacheRoot: cacheRoot)
    }

    init?(arguments: [String], cacheRoot: URL) {
        guard let index = arguments.firstIndex(of: Self.argument),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        let url = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        let cacheRoot = cacheRoot.standardizedFileURL
        guard Self.isAllowed(url, cacheRoot: cacheRoot) else { return nil }
        self.url = url
        self.cacheRoot = cacheRoot
    }

    /// Acknowledges only after the desktop root has crossed its first-window-ready boundary.
    /// The updater keeps the previous app available until this write and its stability wait pass.
    @discardableResult
    func acknowledge() -> Bool {
        guard Self.isAllowed(url, cacheRoot: cacheRoot) else { return false }
        do {
            try Data("ready\n".utf8).write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
            return true
        } catch {
            return false
        }
    }

    static func isAllowed(_ url: URL) -> Bool {
        guard let cacheRoot = try? QuillCodeDesktopUpdatePaths.cacheRoot() else { return false }
        return isAllowed(url, cacheRoot: cacheRoot)
    }

    static func isAllowed(_ url: URL, cacheRoot: URL) -> Bool {
        let rootPath = cacheRoot.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath) &&
            url.pathExtension == "ack" &&
            url.lastPathComponent.hasPrefix("launch-")
    }
}

struct QuillCodeDesktopUpdateInstallResult: Codable, Equatable, Sendable {
    static let maximumEncodedBytes = 64 * 1_024

    enum Status: String, Codable, Sendable {
        case success
        case failure
    }

    var status: Status
    var message: String
    var version: String?
    var build: String?
    var recordedAt: Date

    static func success(version: String, build: String) -> Self {
        Self(
            status: .success,
            message: "Quill Cowork was updated successfully.",
            version: version,
            build: build,
            recordedAt: Date()
        )
    }

    static func failure(message: String) -> Self {
        Self(status: .failure, message: message, version: nil, build: nil, recordedAt: Date())
    }
}

enum QuillCodeDesktopUpdatePaths {
    static func cacheRoot() throws -> URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw QuillCodeDesktopUpdateError.installationUnavailable
        }
        return caches
            .appendingPathComponent("co.lorehex.QuillCowork", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static func installResultURL() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw QuillCodeDesktopUpdateError.installationUnavailable
        }
        return applicationSupport
            .appendingPathComponent("co.lorehex.QuillCowork", isDirectory: true)
            .appendingPathComponent("UpdateResult.json", isDirectory: false)
    }

    static func isAllowedInstallResultURL(_ url: URL) -> Bool {
        guard let expected = try? installResultURL() else { return false }
        return url.standardizedFileURL == expected.standardizedFileURL
    }
}
