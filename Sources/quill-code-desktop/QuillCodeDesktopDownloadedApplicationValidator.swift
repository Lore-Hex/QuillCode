import Foundation

enum QuillCodeDesktopDownloadedApplicationValidator {
    static func validate(
        _ applicationURL: URL,
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) throws {
        guard applicationURL.pathExtension == "app",
              let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == configuration.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == release.build,
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            throw QuillCodeDesktopUpdateError.invalidApplication("its identity or version does not match")
        }
        guard bundle.object(
            forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey
        ) as? String == release.commit else {
            throw QuillCodeDesktopUpdateError.invalidApplication("its source commit does not match")
        }

        let signature = try QuillCodeDesktopUpdateProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", "--verbose=2", applicationURL.path]
        )
        guard signature.exitCode == 0 else {
            throw QuillCodeDesktopUpdateError.invalidApplication("its code signature is invalid")
        }

        try validateSigningRequirement(release.signingRequirement, configuration: configuration)
        let details = try QuillCodeDesktopUpdateProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--display", "--verbose=4", applicationURL.path]
        )
        guard details.exitCode == 0,
              QuillCodeDesktopCodeSignatureMetadata(
                codesignOutput: details.combinedOutput
              ).satisfies(release.signingRequirement)
        else {
            throw QuillCodeDesktopUpdateError.invalidApplication("its signing identity does not match")
        }

        if case .developerID = release.signingRequirement {
            let assessment = try QuillCodeDesktopUpdateProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/spctl"),
                arguments: ["--assess", "--type", "execute", "--verbose=2", applicationURL.path]
            )
            guard assessment.exitCode == 0 else {
                throw QuillCodeDesktopUpdateError.invalidApplication("Gatekeeper did not accept it")
            }
        }

        let architectures = try QuillCodeDesktopUpdateProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/lipo"),
            arguments: ["-archs", executableURL.path]
        )
        let availableArchitectures = Set(
            architectures.standardOutput.split(whereSeparator: \.isWhitespace).map(String.init)
        )
        guard architectures.exitCode == 0,
              availableArchitectures.contains(configuration.architecture)
        else {
            throw QuillCodeDesktopUpdateError.invalidApplication("it does not support this Mac")
        }
    }

    private static func validateSigningRequirement(
        _ requirement: QuillCodeDesktopUpdateSigningRequirement,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) throws {
        if let expectedTeam = configuration.expectedSigningTeamIdentifier {
            guard requirement == .developerID(teamIdentifier: expectedTeam) else {
                throw QuillCodeDesktopUpdateError.invalidApplication("its signing identity does not match")
            }
        }
        if configuration.channel == .stable,
           case .adHoc = requirement {
            throw QuillCodeDesktopUpdateError.invalidApplication("the stable app is not Developer ID signed")
        }
    }
}

struct QuillCodeDesktopUpdateProcessResult: Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String

    var combinedOutput: String {
        [standardOutput, standardError].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var failureSummary: String {
        let value = combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "the system extraction tool failed" : String(value.prefix(500))
    }
}

enum QuillCodeDesktopUpdateProcessRunner {
    private static let outputByteLimit = 64 * 1_024

    static func run(executableURL: URL, arguments: [String]) throws -> QuillCodeDesktopUpdateProcessResult {
        let captureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quill-cowork-process-\(UUID().uuidString)",
            isDirectory: true
        )
        let outputURL = captureRoot.appendingPathComponent("stdout")
        let errorURL = captureRoot.appendingPathComponent("stderr")
        try FileManager.default.createDirectory(at: captureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: captureRoot) }
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        else {
            throw QuillCodeDesktopUpdateError.installationFailed("system-tool output could not be captured")
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        do {
            try process.run()
        } catch {
            throw QuillCodeDesktopUpdateError.installationFailed("a required system tool could not start")
        }
        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()
        return QuillCodeDesktopUpdateProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: try capturedText(at: outputURL),
            standardError: try capturedText(at: errorURL)
        )
    }

    private static func capturedText(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: outputByteLimit) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
