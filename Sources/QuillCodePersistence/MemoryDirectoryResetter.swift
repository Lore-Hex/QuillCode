import Foundation

public enum MemoryDirectoryResetError: Error, Equatable, LocalizedError {
    case unsafeRoot

    public var errorDescription: String? {
        switch self {
        case .unsafeRoot:
            "The global memory root must be a real directory, not a file or symbolic link."
        }
    }
}

public enum MemoryDirectoryResetter {
    /// Removes app-managed global memories while preserving the private memory directory itself.
    public static func clear(_ directory: URL) throws {
        let fileManager = FileManager.default
        let root = directory.standardizedFileURL

        if fileManager.fileExists(atPath: root.path) {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw MemoryDirectoryResetError.unsafeRoot
            }
        }

        try PrivateDirectory.ensureExists(at: root)
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        )
        for child in children {
            try fileManager.removeItem(at: child)
        }
        try PrivateDirectory.ensureExists(at: root)
    }
}
