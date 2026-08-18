import Foundation
import QuillCodeApp

enum QuillCodeDesktopWorkspaceRootResolver {
    static var fallbackDirectoryName: String { "\(QuillCodeProduct.displayName) Workspace" }
    private static let legacyFallbackDirectoryName = "QuillCode Workspace"

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
        if existingDirectory(fallback, fileManager: fileManager) {
            return fallback
        }
        let legacyFallback = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(legacyFallbackDirectoryName, isDirectory: true)
        if existingDirectory(legacyFallback, fileManager: fileManager) {
            return legacyFallback
        }
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

    private static func existingDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
