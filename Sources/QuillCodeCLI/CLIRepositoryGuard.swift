import Foundation

struct CLIRepositoryGuard: Sendable {
    func validate(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
        }
        guard repositoryRoot(containing: directory) != nil else {
            throw CLIError.notGitRepository(directory.path)
        }
    }

    func repositoryRoot(containing directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while true {
            let marker = candidate.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: marker.path) { return candidate }
            guard !candidate.path.isEmpty, candidate.path != "/" else { return nil }
            let parent = candidate.deletingLastPathComponent()
            guard !parent.path.isEmpty, parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }
}
