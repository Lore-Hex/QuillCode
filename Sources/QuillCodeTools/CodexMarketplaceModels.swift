import Foundation

public enum CodexMarketplaceMaterializationError:
    Error, CustomStringConvertible, Sendable, Equatable
{
    case invalidSource
    case invalidRef
    case invalidSparsePath(String)
    case invalidMarketplace(String)
    case gitFailed(String)
    case destinationExists(String)
    case filesystem(String)

    public var description: String {
        switch self {
        case .invalidSource:
            "source must be a local directory, HTTP(S) Git URL, SSH Git URL, or GitHub owner/repo"
        case .invalidRef:
            "refName must be a bounded Git ref"
        case .invalidSparsePath(let path):
            "invalid sparse marketplace path `\(path)`"
        case .invalidMarketplace(let reason):
            "invalid marketplace: \(reason)"
        case .gitFailed(let message):
            message
        case .destinationExists(let name):
            "marketplace `\(name)` is already installed from another source"
        case .filesystem(let message):
            message
        }
    }
}

public enum CodexMarketplaceSourceKind: String, Sendable, Equatable {
    case local
    case git
}

public struct CodexPreparedMarketplace: Sendable, Equatable {
    public var name: String
    public var root: URL
    public var sourceType: CodexMarketplaceSourceKind
    public var source: String
    public var refName: String?
    public var sparsePaths: [String]
    public var revision: String?
    public var managed: Bool
}

public struct CodexMarketplaceActivation: Sendable, Equatable {
    public var name: String
    public var installedRoot: URL
    var backupRoot: URL?
    var managed: Bool
}

public struct CodexMarketplaceRemoval: Sendable, Equatable {
    public var installedRoot: URL
    var stagedRoot: URL
}
