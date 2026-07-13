import Foundation

enum ManagedWorktreeDirectory {
    static func prepare(_ directory: URL) throws -> URL {
        let standardized = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
            return standardized
        }
        let permissions = NSNumber(value: Int16(0o700))
        try FileManager.default.createDirectory(
            at: standardized,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: permissions]
        )
        return standardized
    }
}
