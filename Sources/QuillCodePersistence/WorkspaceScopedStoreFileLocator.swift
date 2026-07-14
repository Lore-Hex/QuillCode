import Foundation
import QuillCodeCore

enum WorkspaceScopedStoreFileLocator {
    static func fileURL(directory: URL, workspaceRoot: URL) -> URL {
        let canonicalPath = WorkspaceBoundary.symlinkResolvedPath(workspaceRoot.standardizedFileURL)
        let component = sanitizedComponent(
            URL(fileURLWithPath: canonicalPath).lastPathComponent,
            fallback: "project",
            maxLength: 40
        )
        return directory.appendingPathComponent("\(component)-\(fnv1a64Hex(canonicalPath)).json")
    }

    static func sanitizedComponent(
        _ component: String,
        fallback: String,
        maxLength: Int
    ) -> String {
        let allowed = component.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        let name = String(allowed.prefix(maxLength))
        return name.isEmpty ? fallback : name
    }

    static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
