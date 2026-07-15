import Foundation
import QuillCodeCore
import QuillCodePersistence

struct CLIDoctorThreadInventoryLimits: Sendable, Equatable {
    static let production = Self(maximumFiles: 5_000, maximumBytes: 8 * 1_024 * 1_024)

    var maximumFiles: Int
    var maximumBytes: Int
}

enum CLIDoctorStateChecks {
    static func paths(_ paths: QuillCodePaths) -> CLIDoctorCheck {
        var isDirectory: ObjCBool = false
        let homeExists = FileManager.default.fileExists(
            atPath: paths.home.path,
            isDirectory: &isDirectory
        )
        if homeExists, !isDirectory.boolValue {
            return CLIDoctorCheck(
                id: "state.paths",
                category: "state",
                status: .fail,
                summary: "the QuillCode state home is not a directory",
                details: .doctorDetails(["QUILLCODE_HOME": paths.home.path]),
                remediation: "Move the conflicting file and relaunch QuillCode."
            )
        }

        let readable = !homeExists || FileManager.default.isReadableFile(atPath: paths.home.path)
        let writable = !homeExists || FileManager.default.isWritableFile(atPath: paths.home.path)
        let status: CLIDoctorStatus = readable && writable ? .ok : .fail
        return CLIDoctorCheck(
            id: "state.paths",
            category: "state",
            status: status,
            summary: homeExists ? "state paths are inspectable" : "state home has not been created yet",
            details: .doctorDetails([
                "QUILLCODE_HOME": homeExists ? "\(paths.home.path) (directory)" : "\(paths.home.path) (missing)",
                "config": pathState(paths.configFile),
                "threads": pathState(paths.threadsDirectory),
                "secrets": pathState(paths.secretsDirectory),
                "app-server metadata": pathState(paths.appServerMetadataDirectory),
                "readable": String(readable),
                "writable": String(writable)
            ]),
            remediation: status == .ok ? nil : "Repair ownership and permissions for the QuillCode state directory."
        )
    }

    static func threadInventory(
        _ paths: QuillCodePaths,
        limits: CLIDoctorThreadInventoryLimits = .production
    ) -> CLIDoctorCheck {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: paths.threadsDirectory.path,
            isDirectory: &isDirectory
        ) else {
            return emptyThreadInventory(
                summary: "no saved task inventory exists yet",
                maximumFiles: limits.maximumFiles
            )
        }
        guard isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                  at: paths.threadsDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                  options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else {
            return CLIDoctorCheck(
                id: "state.thread_inventory",
                category: "threads",
                status: .fail,
                summary: "saved task inventory cannot be read",
                details: .doctorDetails(["directory": paths.threadsDirectory.path]),
                remediation: "Repair task-directory ownership or restore it from backup."
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var scanned = 0
        var healthy = 0
        var unreadable = 0
        var oversized = 0
        var identifierMismatches = 0
        var duplicateIdentifiers = 0
        var scanCapReached = false
        var identifiers = Set<UUID>()

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.caseInsensitiveCompare("json") == .orderedSame else { continue }
            guard scanned < limits.maximumFiles else {
                scanCapReached = true
                break
            }
            scanned += 1
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            ), values.isRegularFile == true, values.isSymbolicLink != true else {
                unreadable += 1
                continue
            }
            guard (values.fileSize ?? limits.maximumBytes + 1) <= limits.maximumBytes else {
                oversized += 1
                continue
            }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let thread = try? decoder.decode(ChatThread.self, from: data) else {
                unreadable += 1
                continue
            }
            healthy += 1
            if UUID(uuidString: url.deletingPathExtension().lastPathComponent) != thread.id {
                identifierMismatches += 1
            }
            if !identifiers.insert(thread.id).inserted {
                duplicateIdentifiers += 1
            }
        }

        let hasIssues = unreadable > 0
            || oversized > 0
            || identifierMismatches > 0
            || duplicateIdentifiers > 0
            || scanCapReached
        var details = [
            "directory": paths.threadsDirectory.path,
            "files scanned": String(scanned),
            "healthy tasks": String(healthy),
            "unreadable tasks": String(unreadable),
            "oversized tasks": String(oversized),
            "identifier mismatches": String(identifierMismatches),
            "duplicate identifiers": String(duplicateIdentifiers),
            "scan cap": String(limits.maximumFiles),
            "scan cap reached": String(scanCapReached)
        ]
        if scanned == 0 { details["inventory"] = "empty" }
        return CLIDoctorCheck(
            id: "state.thread_inventory",
            category: "threads",
            status: hasIssues ? .warning : .ok,
            summary: hasIssues
                ? "saved task inventory has recoverable issues"
                : "\(healthy) saved task\(healthy == 1 ? "" : "s") decoded successfully",
            details: .doctorDetails(details),
            remediation: hasIssues
                ? "Back up ~/.quillcode/threads, then inspect unreadable or mismatched task files."
                : nil
        )
    }

    private static func emptyThreadInventory(summary: String, maximumFiles: Int) -> CLIDoctorCheck {
        CLIDoctorCheck(
            id: "state.thread_inventory",
            category: "threads",
            status: .ok,
            summary: summary,
            details: .doctorDetails([
                "files scanned": "0",
                "healthy tasks": "0",
                "scan cap": String(maximumFiles),
                "scan cap reached": "false"
            ])
        )
    }

    private static func pathState(_ url: URL) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "\(url.path) (missing)"
        }
        return "\(url.path) (\(isDirectory.boolValue ? "directory" : "file"))"
    }
}
