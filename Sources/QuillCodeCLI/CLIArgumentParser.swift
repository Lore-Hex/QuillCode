import Foundation
import QuillCodeCore

public struct CLIArgumentParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String], currentDirectory: URL) throws -> CLICommand {
        var arguments = arguments
        let home = try removeGlobalValue("--home", from: &arguments).map {
            pathURL($0, relativeTo: currentDirectory)
        }

        guard let first = arguments.first else { return .help }
        if first == "--help" || first == "-h" || first == "help" { return .help }
        if first == "--version" || first == "version" { return .version }
        if first == "auth" {
            return try parseAuth(Array(arguments.dropFirst()), home: home)
        }
        if first == "exec" {
            return .run(try parseRun(
                Array(arguments.dropFirst()),
                style: .exec,
                currentDirectory: currentDirectory,
                home: home
            ))
        }
        return .run(try parseRun(
            arguments,
            style: .legacy,
            currentDirectory: currentDirectory,
            home: home
        ))
    }

    private func parseAuth(_ arguments: [String], home: URL?) throws -> CLICommand {
        guard let command = arguments.first else { return .help }
        switch command {
        case "status":
            guard arguments.count == 1 else { throw CLIError.unknownOption(arguments[1]) }
            return .auth(.status, home: home)
        case "set-key":
            guard arguments.count >= 2 else { throw CLIError.missingOptionValue("auth set-key") }
            guard arguments.count == 2 else { throw CLIError.unknownOption(arguments[2]) }
            let key = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw CLIError.missingOptionValue("auth set-key") }
            return .auth(.setKey(key), home: home)
        case "clear":
            guard arguments.count == 1 else { throw CLIError.unknownOption(arguments[1]) }
            return .auth(.clear, home: home)
        default:
            throw CLIError.unknownOption(command)
        }
    }

    private func parseRun(
        _ arguments: [String],
        style: CLIInvocationStyle,
        currentDirectory: URL,
        home: URL?
    ) throws -> CLIRunRequest {
        var tokens = arguments
        var resumeTarget: CLIResumeTarget?
        if style == .exec, tokens.first == "resume" {
            tokens.removeFirst()
            guard let target = tokens.first else { throw CLIError.missingOptionValue("exec resume") }
            tokens.removeFirst()
            if target == "--last" {
                resumeTarget = .last
            } else if let id = UUID(uuidString: target) {
                resumeTarget = .id(id)
            } else {
                throw CLIError.invalidResumeTarget(target)
            }
        }

        var request = CLIRunRequest(
            style: style,
            prompt: "",
            resumeTarget: resumeTarget,
            live: style == .exec,
            cwd: currentDirectory,
            home: home,
            sandbox: style == .exec ? .readOnly : nil
        )
        var promptParts: [String] = []
        var index = 0
        var optionsEnded = false
        while index < tokens.count {
            let token = tokens[index]
            if optionsEnded {
                promptParts.append(token)
                index += 1
                continue
            }
            if token == "--" {
                optionsEnded = true
                index += 1
                continue
            }
            if token == "-" {
                promptParts.append(token)
                index += 1
                continue
            }

            let option = splitOption(token)
            switch option.name {
            case "--live":
                request.live = true
            case "--mock":
                request.live = false
            case "--ephemeral":
                request.ephemeral = true
            case "--json":
                request.emitsJSONLines = true
            case "--ignore-user-config":
                request.ignoresUserConfig = true
            case "--ignore-rules":
                request.ignoresPermissionRules = true
            case "--skip-git-repo-check":
                request.skipsGitRepositoryCheck = true
            case "--full-auto":
                request.sandbox = .workspaceWrite
                request.usedDeprecatedFullAuto = true
            case "--api-key":
                request.apiKey = try value(for: option, tokens: tokens, index: &index)
            case "--model", "-m":
                request.model = try value(for: option, tokens: tokens, index: &index)
            case "--base-url":
                request.baseURL = try value(for: option, tokens: tokens, index: &index)
            case "--cwd", "-C":
                request.cwd = pathURL(
                    try value(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                )
            case "--image":
                request.imageURLs.append(pathURL(
                    try value(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                ))
            case "--output-last-message", "-o":
                request.outputLastMessageURL = pathURL(
                    try value(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                )
            case "--output-schema":
                request.outputSchemaURL = pathURL(
                    try value(for: option, tokens: tokens, index: &index),
                    relativeTo: currentDirectory
                )
            case "--sandbox":
                let raw = try value(for: option, tokens: tokens, index: &index)
                guard let sandbox = CLISandboxMode(rawValue: raw) else {
                    throw CLIError.invalidOptionValue(option: option.name, value: raw)
                }
                request.sandbox = sandbox
            case "--mode":
                let raw = try value(for: option, tokens: tokens, index: &index)
                guard let mode = AgentMode(rawValue: raw) else {
                    throw CLIError.invalidOptionValue(option: option.name, value: raw)
                }
                request.explicitMode = mode
            case "--help", "-h":
                throw CLIError.unknownOption("Use `quill-code help` for command help.")
            default:
                if token.hasPrefix("-") {
                    throw CLIError.unknownOption(option.name)
                }
                promptParts.append(token)
            }
            index += 1
        }

        if promptParts.contains("-"), promptParts.count != 1 {
            throw CLIError.invalidOptionValue(option: "prompt", value: promptParts.joined(separator: " "))
        }
        request.prompt = promptParts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return request
    }

    private func removeGlobalValue(_ name: String, from arguments: inout [String]) throws -> String? {
        var found: String?
        var index = 0
        while index < arguments.count {
            let option = splitOption(arguments[index])
            guard option.name == name else {
                index += 1
                continue
            }
            guard found == nil else { throw CLIError.invalidOptionValue(option: name, value: "duplicate") }
            if let inlineValue = option.inlineValue {
                found = inlineValue
                arguments.remove(at: index)
            } else {
                let valueIndex = index + 1
                guard arguments.indices.contains(valueIndex) else { throw CLIError.missingOptionValue(name) }
                found = arguments[valueIndex]
                arguments.removeSubrange(index...valueIndex)
            }
        }
        return found
    }

    private func value(
        for option: ParsedOption,
        tokens: [String],
        index: inout Int
    ) throws -> String {
        if let inlineValue = option.inlineValue { return inlineValue }
        let valueIndex = index + 1
        guard tokens.indices.contains(valueIndex) else { throw CLIError.missingOptionValue(option.name) }
        index = valueIndex
        return tokens[valueIndex]
    }

    private func splitOption(_ token: String) -> ParsedOption {
        guard token.hasPrefix("--"), let separator = token.firstIndex(of: "=") else {
            return ParsedOption(name: token, inlineValue: nil)
        }
        return ParsedOption(
            name: String(token[..<separator]),
            inlineValue: String(token[token.index(after: separator)...])
        )
    }

    private func pathURL(_ value: String, relativeTo directory: URL) -> URL {
        let expanded = value.cliExpandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return directory.appendingPathComponent(expanded).standardizedFileURL
    }
}

private struct ParsedOption {
    var name: String
    var inlineValue: String?
}
