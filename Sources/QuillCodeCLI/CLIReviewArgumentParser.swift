import Foundation

struct CLIReviewArgumentParser: Sendable {
    func parse(
        _ arguments: [String],
        currentDirectory: URL,
        home: URL?
    ) throws -> CLIReviewRequest {
        var request = CLIReviewRequest(cwd: currentDirectory, home: home)
        var promptParts: [String] = []
        var optionsEnded = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
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

            let option = cliSplitOption(token)
            switch option.name {
            case "--uncommitted":
                try select(.uncommitted, into: &request)
            case "--base":
                try select(
                    .baseBranch(try cliValue(for: option, tokens: arguments, index: &index)),
                    into: &request
                )
            case "--commit":
                try select(
                    .commit(try cliValue(for: option, tokens: arguments, index: &index)),
                    into: &request
                )
            case "--title":
                request.title = try cliValue(for: option, tokens: arguments, index: &index)
            case "--live":
                request.live = true
            case "--mock":
                request.live = false
            case "--api-key":
                request.apiKey = try cliValue(for: option, tokens: arguments, index: &index)
            case "--model", "-m":
                request.model = try cliValue(for: option, tokens: arguments, index: &index)
            case "--base-url":
                request.baseURL = try cliValue(for: option, tokens: arguments, index: &index)
            case "--cwd", "-C":
                request.cwd = cliPathURL(
                    try cliValue(for: option, tokens: arguments, index: &index),
                    relativeTo: currentDirectory
                )
            case "--ignore-user-config":
                request.ignoresUserConfig = true
            case "--help", "-h":
                request.showsHelp = true
            default:
                if token.hasPrefix("-") {
                    throw CLIError.unknownOption(option.name)
                }
                promptParts.append(token)
            }
            index += 1
        }

        try applyPrompt(promptParts, to: &request)
        try validate(request)
        return request
    }

    private func select(
        _ target: CLIReviewTarget,
        into request: inout CLIReviewRequest
    ) throws {
        guard request.target == nil else { throw CLIError.conflictingReviewTargets }
        request.target = target
    }

    private func applyPrompt(
        _ parts: [String],
        to request: inout CLIReviewRequest
    ) throws {
        guard !parts.isEmpty else { return }
        if parts.contains("-"), parts.count != 1 {
            throw CLIError.invalidOptionValue(
                option: "review prompt",
                value: parts.joined(separator: " ")
            )
        }
        let prompt = parts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try select(.custom(prompt), into: &request)
    }

    private func validate(_ request: CLIReviewRequest) throws {
        if request.showsHelp { return }
        guard request.target != nil else { throw CLIError.missingReviewTarget }
        if request.title != nil, case .commit? = request.target {
            // Commit titles are validated by the shared review request below.
        } else if request.title != nil {
            throw CLIError.reviewTitleRequiresCommit
        }
        _ = try request.workspaceRequest()
    }
}
