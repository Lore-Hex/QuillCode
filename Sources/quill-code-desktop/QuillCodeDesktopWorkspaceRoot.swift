import Foundation

enum QuillCodeDesktopWorkspaceRootResolver {
    static let fallbackDirectoryName = "QuillCode Workspace"

    static func resolve(
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        let current = currentDirectory.standardizedFileURL
        let home = userHome.standardizedFileURL
        var isDirectory: ObjCBool = false
        if current.path != "/",
           current.path != home.path,
           fileManager.fileExists(atPath: current.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return current
        }

        let fallback = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(fallbackDirectoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        } catch {
            let temporaryFallback = fileManager.temporaryDirectory
                .appendingPathComponent("quillcode-workspace-\(UUID().uuidString)", isDirectory: true)
            try? fileManager.createDirectory(at: temporaryFallback, withIntermediateDirectories: true)
            return temporaryFallback
        }
    }
}
