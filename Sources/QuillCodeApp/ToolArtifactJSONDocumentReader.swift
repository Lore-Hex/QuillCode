import Foundation

enum ToolArtifactJSONDocumentReader {
    struct Document {
        var root: Any
        var byteSize: Int
    }

    struct Diagnostics: Equatable {
        var fileReadCount: Int
        var parseCount: Int
        var cacheHitCount: Int
    }

    static func document(for fileURL: URL, byteLimit: Int) throws -> Document? {
        guard byteLimit > 0 else { return nil }

        var refreshedFileURL = fileURL.standardizedFileURL
        refreshedFileURL.removeAllCachedResourceValues()
        let resourceValues = try refreshedFileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .isRegularFileKey
        ])
        guard resourceValues.isRegularFile == true else { return nil }
        let fileSize = max(resourceValues.fileSize ?? 0, 0)
        guard fileSize > 0, fileSize <= byteLimit else { return nil }

        let key = CacheKey(
            path: refreshedFileURL.path,
            fileSize: fileSize,
            modificationDate: resourceValues.contentModificationDate,
            resourceIdentifier: resourceValues.fileResourceIdentifier
        )
        return try cache.document(for: key, fileURL: refreshedFileURL, fileSize: fileSize)
    }

    static func diagnosticsForTesting() -> Diagnostics {
        cache.diagnosticsSnapshot()
    }

    static func resetCacheForTesting() {
        cache.reset()
    }

    private static func validatedDocument(from data: Data, byteSize: Int) -> (Document, Int)? {
        guard !data.contains(0),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else { return nil }

        var nodeCount = 0
        guard validate(root, depth: 0, nodeCount: &nodeCount) else { return nil }
        let estimatedCost = byteSize + (nodeCount * estimatedBytesPerNode)
        return (Document(root: root, byteSize: byteSize), estimatedCost)
    }

    private static func validate(_ value: Any, depth: Int, nodeCount: inout Int) -> Bool {
        guard depth <= maximumDepth, nodeCount < maximumNodeCount else { return false }
        nodeCount += 1

        if let dictionary = value as? [String: Any] {
            for child in dictionary.values {
                guard validate(child, depth: depth + 1, nodeCount: &nodeCount) else { return false }
            }
            return true
        }
        if let array = value as? [Any] {
            for child in array {
                guard validate(child, depth: depth + 1, nodeCount: &nodeCount) else { return false }
            }
            return true
        }
        return value is String || value is NSNumber || value is NSNull
    }

    private final class CacheKey: NSObject {
        private let path: String
        private let fileSize: Int
        private let modificationTime: TimeInterval
        private let resourceIdentifier: String

        init(path: String, fileSize: Int, modificationDate: Date?, resourceIdentifier: Any?) {
            self.path = path
            self.fileSize = fileSize
            self.modificationTime = modificationDate?.timeIntervalSinceReferenceDate ?? 0
            self.resourceIdentifier = resourceIdentifier.map(String.init(describing:)) ?? ""
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(path)
            hasher.combine(fileSize)
            hasher.combine(modificationTime)
            hasher.combine(resourceIdentifier)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return path == other.path
                && fileSize == other.fileSize
                && modificationTime == other.modificationTime
                && resourceIdentifier == other.resourceIdentifier
        }
    }

    private final class Cache: @unchecked Sendable {
        private final class Box: NSObject {
            let document: Document?

            init(_ document: Document?) {
                self.document = document
            }
        }

        private let lock = NSLock()
        private let storage: NSCache<CacheKey, Box>
        private var diagnostics = Diagnostics(fileReadCount: 0, parseCount: 0, cacheHitCount: 0)

        init() {
            let storage = NSCache<CacheKey, Box>()
            storage.countLimit = cacheEntryLimit
            storage.totalCostLimit = cacheEstimatedByteLimit
            self.storage = storage
        }

        func document(for key: CacheKey, fileURL: URL, fileSize: Int) throws -> Document? {
            lock.lock()
            defer { lock.unlock() }

            if let cached = storage.object(forKey: key) {
                diagnostics.cacheHitCount += 1
                return cached.document
            }

            diagnostics.fileReadCount += 1
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])

            diagnostics.parseCount += 1
            let result = validatedDocument(from: data, byteSize: fileSize)
            storage.setObject(Box(result?.0), forKey: key, cost: max(result?.1 ?? 1, 1))
            return result?.0
        }

        func diagnosticsSnapshot() -> Diagnostics {
            lock.lock()
            defer { lock.unlock() }
            return diagnostics
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAllObjects()
            diagnostics = Diagnostics(fileReadCount: 0, parseCount: 0, cacheHitCount: 0)
        }
    }

    private static let cache = Cache()
    private static let cacheEntryLimit = 4
    private static let cacheEstimatedByteLimit = 4 * 1_024 * 1_024
    private static let maximumDepth = 64
    private static let maximumNodeCount = 16_384
    private static let estimatedBytesPerNode = 64
}
