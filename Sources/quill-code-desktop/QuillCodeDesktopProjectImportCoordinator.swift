import Foundation

struct QuillCodeDesktopProjectImportSelection: Equatable {
    let url: URL
}

struct QuillCodeDesktopProjectImportCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func selectedProject(from result: Result<[URL], any Error>) -> QuillCodeDesktopProjectImportSelection? {
        guard case let .success(urls) = result else {
            return nil
        }

        return urls.lazy
            .map(\.standardizedFileURL)
            .first(where: isDirectory)
            .map(QuillCodeDesktopProjectImportSelection.init(url:))
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
