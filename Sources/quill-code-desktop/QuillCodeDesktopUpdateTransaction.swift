import Foundation

struct QuillCodeDesktopUpdateTransaction: Codable, Equatable, Sendable {
    static let fileName = "UpdateTransaction.json"
    static let maximumEncodedBytes = 16 * 1_024
    private static let schemaVersion = 1

    var schemaVersion: Int
    var operationIdentifier: String
    var parentProcessID: Int32
    var helperPath: String
    var incomingApplicationPath: String
    var destinationApplicationPath: String
    var handshakePath: String
    var resultPath: String
    var logPath: String
    var expectedBundleIdentifier: String
    var expectedVersion: String
    var expectedBuild: String
    var expectedCommit: String
    var activationMode: QuillCodeDesktopApplicationActivationMode

    static func persist(
        for request: QuillCodeDesktopUpdateHelperRequest,
        cacheRoot: URL
    ) throws {
        let transaction = try make(for: request, cacheRoot: cacheRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(transaction)
        guard !data.isEmpty, data.count <= maximumEncodedBytes else {
            throw recoveryRecordError
        }

        let url = transactionURL(for: request.helperURL.deletingLastPathComponent())
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw recoveryRecordError
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            guard try read(from: url) == transaction else {
                throw recoveryRecordError
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw recoveryRecordError
        }
    }

    static func validate(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        cacheRoot: URL
    ) throws {
        do {
            let workspace = request.helperURL.deletingLastPathComponent().standardizedFileURL
            let transaction = try read(from: transactionURL(for: workspace))
            guard transaction.matches(request, workspace: workspace, cacheRoot: cacheRoot) else {
                throw recoveryRecordError
            }
        } catch {
            throw recoveryRecordError
        }
    }

    @discardableResult
    static func discardUnactivated(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        cacheRoot: URL
    ) -> Bool {
        do {
            try validate(request, cacheRoot: cacheRoot)
            let incoming = request.incomingApplicationURL.standardizedFileURL
            guard applicationMatchesExpected(incoming, request: request) else { return false }
            try FileManager.default.removeItem(at: incoming)
            let workspace = request.helperURL.deletingLastPathComponent().standardizedFileURL
            try? FileManager.default.removeItem(at: workspace)
            return true
        } catch {
            return false
        }
    }

    static func read(
        fromWorkspace workspace: URL,
        cacheRoot: URL
    ) throws -> Self {
        let workspace = workspace.standardizedFileURL
        let cacheRoot = cacheRoot.standardizedFileURL
        guard workspace != cacheRoot,
              workspace.deletingLastPathComponent() == cacheRoot,
              let values = try? workspace.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw recoveryRecordError
        }
        return try read(from: transactionURL(for: workspace))
    }

    func hasValidRecoveryLayout(
        workspace: URL,
        cacheRoot: URL,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) -> Bool {
        let workspace = workspace.standardizedFileURL
        let cacheRoot = cacheRoot.standardizedFileURL
        let destination = destinationApplicationURL
        let incoming = incomingApplicationURL
        guard schemaVersion == Self.schemaVersion,
              activationMode == .replaceExisting,
              operationIdentifier == Self.operationIdentifier(
                incomingApplicationURL: incoming,
                destinationApplicationURL: destination
              ),
              workspace.path != cacheRoot.path,
              workspace.deletingLastPathComponent().path == cacheRoot.path,
              destination.path == configuration.applicationURL.standardizedFileURL.path,
              incoming.deletingLastPathComponent().path == destination.deletingLastPathComponent().path,
              expectedBundleIdentifier == configuration.bundleIdentifier,
              !expectedBundleIdentifier.isEmpty,
              QuillCodeDesktopSemanticVersion(expectedVersion) != nil,
              UInt64(expectedBuild) != nil,
              QuillCodeDesktopBuildMetadata.isCanonicalCommit(expectedCommit),
              URL(fileURLWithPath: helperPath).standardizedFileURL
                .deletingLastPathComponent().path == workspace.path,
              URL(fileURLWithPath: handshakePath).standardizedFileURL
                .deletingLastPathComponent().path == workspace.path,
              URL(fileURLWithPath: logPath).standardizedFileURL
                .deletingLastPathComponent().path == workspace.path
        else {
            return false
        }
        return true
    }

    var incomingApplicationURL: URL {
        URL(fileURLWithPath: incomingApplicationPath).standardizedFileURL
    }

    var destinationApplicationURL: URL {
        URL(fileURLWithPath: destinationApplicationPath).standardizedFileURL
    }

    private static func make(
        for request: QuillCodeDesktopUpdateHelperRequest,
        cacheRoot: URL
    ) throws -> Self {
        let incoming = request.incomingApplicationURL.standardizedFileURL
        let destination = request.destinationApplicationURL.standardizedFileURL
        guard let identifier = operationIdentifier(
            incomingApplicationURL: incoming,
            destinationApplicationURL: destination
        ) else {
            throw recoveryRecordError
        }
        let transaction = Self(
            schemaVersion: schemaVersion,
            operationIdentifier: identifier,
            parentProcessID: request.parentProcessID,
            helperPath: request.helperURL.standardizedFileURL.path,
            incomingApplicationPath: incoming.path,
            destinationApplicationPath: destination.path,
            handshakePath: request.handshakeURL.standardizedFileURL.path,
            resultPath: request.resultURL.standardizedFileURL.path,
            logPath: request.logURL.standardizedFileURL.path,
            expectedBundleIdentifier: request.expectedBundleIdentifier,
            expectedVersion: request.expectedVersion,
            expectedBuild: request.expectedBuild,
            expectedCommit: request.expectedCommit,
            activationMode: request.activationMode
        )
        let workspace = request.helperURL.deletingLastPathComponent().standardizedFileURL
        guard transaction.matches(request, workspace: workspace, cacheRoot: cacheRoot) else {
            throw recoveryRecordError
        }
        return transaction
    }

    private func matches(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        workspace: URL,
        cacheRoot: URL
    ) -> Bool {
        guard schemaVersion == Self.schemaVersion,
              operationIdentifier == Self.operationIdentifier(
                incomingApplicationURL: request.incomingApplicationURL,
                destinationApplicationURL: request.destinationApplicationURL
              ),
              parentProcessID == request.parentProcessID,
              helperPath == request.helperURL.standardizedFileURL.path,
              incomingApplicationPath == request.incomingApplicationURL.standardizedFileURL.path,
              destinationApplicationPath == request.destinationApplicationURL.standardizedFileURL.path,
              handshakePath == request.handshakeURL.standardizedFileURL.path,
              resultPath == request.resultURL.standardizedFileURL.path,
              logPath == request.logURL.standardizedFileURL.path,
              expectedBundleIdentifier == request.expectedBundleIdentifier,
              expectedVersion == request.expectedVersion,
              expectedBuild == request.expectedBuild,
              expectedCommit == request.expectedCommit,
              activationMode == request.activationMode,
              workspace != cacheRoot.standardizedFileURL,
              workspace.deletingLastPathComponent() == cacheRoot.standardizedFileURL,
              request.handshakeURL.deletingLastPathComponent().standardizedFileURL == workspace,
              request.logURL.deletingLastPathComponent().standardizedFileURL == workspace,
              !expectedBundleIdentifier.isEmpty,
              QuillCodeDesktopSemanticVersion(expectedVersion) != nil,
              UInt64(expectedBuild) != nil,
              QuillCodeDesktopBuildMetadata.isCanonicalCommit(expectedCommit)
        else {
            return false
        }
        return true
    }

    private static func read(from url: URL) throws -> Self {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumEncodedBytes
        else {
            throw recoveryRecordError
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == size else { throw recoveryRecordError }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw recoveryRecordError
        }
    }

    private static func transactionURL(for workspace: URL) -> URL {
        workspace.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func operationIdentifier(
        incomingApplicationURL: URL,
        destinationApplicationURL: URL
    ) -> String? {
        let baseName = destinationApplicationURL.deletingPathExtension().lastPathComponent
        let prefix = ".\(baseName).update-"
        let suffix = ".app"
        let name = incomingApplicationURL.lastPathComponent
        guard name.hasPrefix(prefix),
              name.hasSuffix(suffix),
              name.count > prefix.count + suffix.count
        else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        let identifier = String(name[start..<end])
        guard let uuid = UUID(uuidString: identifier),
              uuid.uuidString.lowercased() == identifier
        else {
            return nil
        }
        return identifier
    }

    private static func applicationMatchesExpected(
        _ applicationURL: URL,
        request: QuillCodeDesktopUpdateHelperRequest
    ) -> Bool {
        guard let values = try? applicationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == request.expectedBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ==
                request.expectedVersion,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ==
                request.expectedBuild,
              bundle.object(forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey)
                as? String == request.expectedCommit
        else {
            return false
        }
        return true
    }

    private static var recoveryRecordError: QuillCodeDesktopUpdateError {
        .installationFailed("the update recovery record is unavailable")
    }
}
