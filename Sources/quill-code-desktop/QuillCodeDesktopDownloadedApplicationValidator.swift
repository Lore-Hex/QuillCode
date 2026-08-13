import Foundation

struct QuillCodeDesktopApplicationValidationRequirement: Sendable {
    var bundleIdentifier: String
    var version: String
    var build: String
    var commit: String
    var architecture: String
    var signingRequirement: QuillCodeDesktopUpdateSigningRequirement
}

enum QuillCodeDesktopDownloadedApplicationValidator {
    static func validate(
        _ applicationURL: URL,
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) throws {
        try validateSigningRequirement(release.signingRequirement, configuration: configuration)
        try validate(applicationURL, requirement: requirement(release, configuration: configuration))
    }

    static func validate(
        _ applicationURL: URL,
        requirement: QuillCodeDesktopApplicationValidationRequirement
    ) throws {
        let context = try validationContext(applicationURL, requirement: requirement)
        for command in validationCommands(context) {
            let result = try QuillCodeDesktopUpdateProcessRunner.run(
                executableURL: command.executableURL,
                arguments: command.arguments
            )
            try validate(result, for: command.kind, context: context)
        }
    }

    static func validateForPreparation(
        _ applicationURL: URL,
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws {
        try Task.checkCancellation()
        try validateSigningRequirement(release.signingRequirement, configuration: configuration)
        let context = try validationContext(
            applicationURL,
            requirement: requirement(release, configuration: configuration)
        )
        for command in validationCommands(context) {
            try Task.checkCancellation()
            let result = try await QuillCodeDesktopUpdateProcessRunner.runAsync(
                executableURL: command.executableURL,
                arguments: command.arguments
            )
            try validate(result, for: command.kind, context: context)
        }
    }

    private struct ValidationContext {
        var applicationURL: URL
        var executableURL: URL
        var requirement: QuillCodeDesktopApplicationValidationRequirement
    }

    private enum ValidationCommandKind {
        case signature
        case signingIdentity
        case gatekeeper
        case architectures
    }

    private struct ValidationCommand {
        var kind: ValidationCommandKind
        var executableURL: URL
        var arguments: [String]
    }

    private static func requirement(
        _ release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) -> QuillCodeDesktopApplicationValidationRequirement {
        QuillCodeDesktopApplicationValidationRequirement(
            bundleIdentifier: configuration.bundleIdentifier,
            version: release.version,
            build: release.build,
            commit: release.commit,
            architecture: configuration.architecture,
            signingRequirement: release.signingRequirement
        )
    }

    private static func validationContext(
        _ applicationURL: URL,
        requirement: QuillCodeDesktopApplicationValidationRequirement
    ) throws -> ValidationContext {
        guard applicationURL.pathExtension == "app",
              let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == requirement.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ==
                requirement.version,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == requirement.build,
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            throw QuillCodeDesktopUpdateError.invalidApplication("its identity or version does not match")
        }
        guard bundle.object(
            forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey
        ) as? String == requirement.commit else {
            throw QuillCodeDesktopUpdateError.invalidApplication("its source commit does not match")
        }
        return ValidationContext(
            applicationURL: applicationURL,
            executableURL: executableURL,
            requirement: requirement
        )
    }

    private static func validationCommands(_ context: ValidationContext) -> [ValidationCommand] {
        var commands = [
            ValidationCommand(
                kind: .signature,
                executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: [
                    "--verify", "--deep", "--strict", "--verbose=2", context.applicationURL.path,
                ]
            ),
            ValidationCommand(
                kind: .signingIdentity,
                executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--display", "--verbose=4", context.applicationURL.path]
            ),
        ]
        if case .developerID = context.requirement.signingRequirement {
            commands.append(ValidationCommand(
                kind: .gatekeeper,
                executableURL: URL(fileURLWithPath: "/usr/sbin/spctl"),
                arguments: [
                    "--assess", "--type", "execute", "--verbose=2", context.applicationURL.path,
                ]
            ))
        }
        commands.append(ValidationCommand(
            kind: .architectures,
            executableURL: URL(fileURLWithPath: "/usr/bin/lipo"),
            arguments: ["-archs", context.executableURL.path]
        ))
        return commands
    }

    private static func validate(
        _ result: QuillCodeDesktopUpdateProcessResult,
        for kind: ValidationCommandKind,
        context: ValidationContext
    ) throws {
        switch kind {
        case .signature:
            guard result.exitCode == 0 else {
                throw QuillCodeDesktopUpdateError.invalidApplication("its code signature is invalid")
            }
        case .signingIdentity:
            guard result.exitCode == 0,
                  QuillCodeDesktopCodeSignatureMetadata(
                    codesignOutput: result.combinedOutput
                  ).satisfies(context.requirement.signingRequirement)
            else {
                throw QuillCodeDesktopUpdateError.invalidApplication("its signing identity does not match")
            }
        case .gatekeeper:
            guard result.exitCode == 0 else {
                throw QuillCodeDesktopUpdateError.invalidApplication("Gatekeeper did not accept it")
            }
        case .architectures:
            let availableArchitectures = Set(
                result.standardOutput.split(whereSeparator: \.isWhitespace).map(String.init)
            )
            guard result.exitCode == 0,
                  availableArchitectures.contains(context.requirement.architecture)
            else {
                throw QuillCodeDesktopUpdateError.invalidApplication("it does not support this Mac")
            }
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
