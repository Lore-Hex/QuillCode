import Foundation

enum QuillCodeDesktopUpdateLaunchHandshake {
    static let argument = "--quillcode-update-handshake"

    static func acknowledgeIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1)
        else {
            return
        }
        let url = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        guard isAllowed(url) else { return }
        try? Data("ready\n".utf8).write(to: url, options: [.atomic, .completeFileProtection])
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
