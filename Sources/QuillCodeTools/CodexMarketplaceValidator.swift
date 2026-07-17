import Foundation
import QuillCodeCore

enum CodexMarketplaceValidator {
    static func validatedRef(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let ref = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty,
              !ref.contains("\0"),
              !ref.hasPrefix("-"),
              ref.utf8.count <= 1_024
        else { throw CodexMarketplaceMaterializationError.invalidRef }
        return ref
    }

    static func validatedSparsePaths(_ values: [String]) throws -> [String] {
        guard values.count <= CodexMarketplaceMaterializer.maximumSparsePaths else {
            throw CodexMarketplaceMaterializationError.invalidSparsePath("too many paths")
        }
        var result: [String] = []
        var seen = Set<String>()
        for value in values {
            let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let components = NSString(string: path).pathComponents
            guard !path.isEmpty,
                  !path.contains("\0"),
                  !NSString(string: path).isAbsolutePath,
                  !path.hasPrefix("-"),
                  path.utf8.count <= CodexMarketplaceMaterializer.maximumSparsePathBytes,
                  !components.contains("..")
            else { throw CodexMarketplaceMaterializationError.invalidSparsePath(value) }
            if seen.insert(path).inserted { result.append(path) }
        }
        return result
    }

    static func normalizedGitSource(_ source: String, currentDirectory: URL) throws -> String {
        if let components = URLComponents(string: source),
           let scheme = components.scheme?.lowercased(),
           ["http", "https", "ssh"].contains(scheme),
           components.host?.isEmpty == false,
           components.query == nil,
           components.fragment == nil,
           components.password == nil,
           (scheme == "ssh" || components.user == nil) {
            return source
        }
        if source.hasPrefix("git@"),
           source.contains(":"),
           !source.contains(where: \.isWhitespace) {
            return source
        }
        let shorthand = source.split(separator: "/", omittingEmptySubsequences: false)
        if shorthand.count == 2, shorthand.allSatisfy(isGitHubShorthandComponent) {
            let suffix = source.hasSuffix(".git") ? "" : ".git"
            return "https://github.com/\(source)\(suffix)"
        }
        let local = NSString(string: source).isAbsolutePath
            ? URL(fileURLWithPath: source)
            : currentDirectory.appendingPathComponent(source)
        let canonical = local.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? canonical.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isDirectory == true, values?.isSymbolicLink != true {
            return canonical.path
        }
        throw CodexMarketplaceMaterializationError.invalidSource
    }

    static func validatedMarketplace(at root: URL) throws -> CodexPluginMarketplaceCatalog {
        let catalogs = defaultCatalogPaths(in: root).map {
            CodexPluginMarketplaceCatalogLoader.load(at: $0)
        }
        let marketplaces = catalogs.flatMap(\.marketplaces)
        let errors = catalogs.flatMap(\.errors)
        guard errors.isEmpty else {
            throw CodexMarketplaceMaterializationError.invalidMarketplace(
                errors.map(\.message).joined(separator: "; ")
            )
        }
        guard marketplaces.count == 1, let marketplace = marketplaces.first else {
            throw CodexMarketplaceMaterializationError.invalidMarketplace(
                "expected exactly one standard marketplace catalog"
            )
        }
        return marketplace
    }

    static func validateTree(at root: URL) throws {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CodexMarketplaceMaterializationError.invalidMarketplace(
                "cannot enumerate repository"
            )
        }
        var entries = 0
        var bytes: Int64 = 0
        for case let entry as URL in enumerator {
            entries += 1
            guard entries <= CodexMarketplaceMaterializer.maximumEntries else {
                throw CodexMarketplaceMaterializationError.invalidMarketplace(
                    "repository has too many entries"
                )
            }
            let values = try entry.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ])
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true
            else {
                throw CodexMarketplaceMaterializationError.invalidMarketplace(
                    "repository contains symbolic or special entries"
                )
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size <= CodexMarketplaceMaterializer.maximumFileBytes else {
                    throw CodexMarketplaceMaterializationError.invalidMarketplace(
                        "repository file is too large"
                    )
                }
                bytes += size
                guard bytes <= CodexMarketplaceMaterializer.maximumBytes else {
                    throw CodexMarketplaceMaterializationError.invalidMarketplace(
                        "repository is too large"
                    )
                }
            }
        }
        if let enumerationError {
            throw CodexMarketplaceMaterializationError.invalidMarketplace(
                "cannot fully enumerate repository: \(enumerationError.localizedDescription)"
            )
        }
    }

    private static func isGitHubShorthandComponent(_ component: Substring) -> Bool {
        !component.isEmpty && component.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
    }

    private static func defaultCatalogPaths(in root: URL) -> [URL] {
        CodexPluginMarketplaceCatalogLoader.defaultCatalogPaths.compactMap { relativePath in
            guard let path = WorkspaceBoundary.safeURL(relativePath, root: root),
                  FileManager.default.fileExists(atPath: path.path)
            else { return nil }
            return path
        }
    }
}
