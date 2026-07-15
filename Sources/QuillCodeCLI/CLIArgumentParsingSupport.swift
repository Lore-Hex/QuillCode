import Foundation

struct CLIParsedOption {
    var name: String
    var inlineValue: String?
}

func cliSplitOption(_ token: String) -> CLIParsedOption {
    guard token.hasPrefix("--"), let separator = token.firstIndex(of: "=") else {
        return CLIParsedOption(name: token, inlineValue: nil)
    }
    return CLIParsedOption(
        name: String(token[..<separator]),
        inlineValue: String(token[token.index(after: separator)...])
    )
}

func cliValue(
    for option: CLIParsedOption,
    tokens: [String],
    index: inout Int
) throws -> String {
    if let inlineValue = option.inlineValue { return inlineValue }
    let valueIndex = index + 1
    guard tokens.indices.contains(valueIndex) else {
        throw CLIError.missingOptionValue(option.name)
    }
    index = valueIndex
    return tokens[valueIndex]
}

func cliPathURL(_ value: String, relativeTo directory: URL) -> URL {
    let expanded = value.cliExpandingTildeInPath
    if NSString(string: expanded).isAbsolutePath {
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
    return directory.appendingPathComponent(expanded).standardizedFileURL
}
