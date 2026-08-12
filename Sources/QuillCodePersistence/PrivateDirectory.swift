import Foundation

enum PrivateDirectory {
    static func ensureExists(at directory: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                // Another app task or process may have created it after the existence check.
                guard fileManager.fileExists(atPath: directory.path) else { throw error }
            }
        }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
