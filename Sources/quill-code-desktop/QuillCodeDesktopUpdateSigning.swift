import Foundation

enum QuillCodeDesktopUpdateSigningRequirement: Equatable, Sendable {
    case adHoc
    case developerID(teamIdentifier: String)
}

struct QuillCodeDesktopCodeSignatureMetadata: Equatable, Sendable {
    var signature: String?
    var teamIdentifier: String?
    var authorities: [String]

    init(codesignOutput: String) {
        var signature: String?
        var teamIdentifier: String?
        var authorities: [String] = []

        for rawLine in codesignOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let key = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "Signature":
                signature = value
            case "TeamIdentifier":
                teamIdentifier = value
            case "Authority":
                authorities.append(value)
            default:
                break
            }
        }

        self.signature = signature
        self.teamIdentifier = teamIdentifier
        self.authorities = authorities
    }

    func satisfies(_ requirement: QuillCodeDesktopUpdateSigningRequirement) -> Bool {
        switch requirement {
        case .adHoc:
            return signature == "adhoc" && teamIdentifier == "not set" && authorities.isEmpty
        case .developerID(let expectedTeamIdentifier):
            return teamIdentifier == expectedTeamIdentifier && authorities.contains { authority in
                authority.hasPrefix("Developer ID Application:")
            }
        }
    }
}
