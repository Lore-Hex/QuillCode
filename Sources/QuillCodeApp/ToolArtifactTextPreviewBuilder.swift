import Foundation

enum ToolArtifactTextPreviewBuilder {
    static func textPreview(for value: String) -> String? {
        let artifact = ToolArtifactState(value: value)
        return payload(for: value, kind: artifact.kind)?.text
    }

    static func sourceTextPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSourceTextPreview? {
        payload(for: value, kind: kind).map {
            ToolArtifactSourceTextPreview(
                typeLabel: $0.typeLabel,
                lineCountLabel: $0.lineCountLabel,
                byteSizeLabel: $0.byteSizeLabel,
                isTruncated: $0.wasTruncated
            )
        }
    }

    private static func payload(for value: String, kind: ToolArtifactKind) -> TextPreviewPayload? {
        let artifact = ToolArtifactState(value: value)
        guard artifact.canLoadLocalPreview,
              kind == .file,
              !artifact.isImagePreview,
              artifact.documentPreview?.kind != .appshot,
              artifact.documentPreview?.extensionLabel.lowercased() != "env",
              artifact.tablePreview == nil,
              let fileURL = localArtifactFileURL(for: value),
              isTextPreviewCandidate(fileURL)
        else { return nil }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileResourceIdentifierKey,
                .fileSizeKey,
                .isRegularFileKey
            ])
            guard resourceValues.isRegularFile == true else { return nil }
            let cacheKey = TextPreviewCacheKey(
                path: fileURL.standardizedFileURL.path,
                fileSize: resourceValues.fileSize ?? 0,
                modificationDate: resourceValues.contentModificationDate,
                resourceIdentifier: resourceValues.fileResourceIdentifier
            )
            if let cached = cache.value(for: cacheKey) {
                return cached
            }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            guard let data = try handle.read(upToCount: byteLimit + 1),
                  !data.isEmpty
            else { return nil }

            var wasTruncated = data.count > byteLimit
            let previewData = Data(data.prefix(byteLimit))
            guard !previewData.contains(0),
                  var text = String(data: previewData, encoding: .utf8)
            else { return nil }

            text = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > lineLimit {
                wasTruncated = true
                text = lines.prefix(lineLimit).joined(separator: "\n")
            }
            if wasTruncated {
                if !text.hasSuffix("\n") {
                    text += "\n"
                }
                text += "..."
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let payload = TextPreviewPayload(
                text: text,
                typeLabel: typeLabel(for: fileURL),
                lineCountLabel: lineCountLabel(for: text, wasTruncated: wasTruncated),
                byteSizeLabel: resourceValues.fileSize.flatMap(ToolArtifactByteSizeFormatter.label),
                wasTruncated: wasTruncated
            )
            cache.insert(payload, for: cacheKey)
            return payload
        } catch {
            return nil
        }
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }

    private static func isTextPreviewCandidate(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        if filenames.contains(filename) {
            return true
        }
        let pathExtension = url.pathExtension.lowercased()
        return extensions.contains(pathExtension)
    }

    private static func typeLabel(for url: URL) -> String {
        let filename = url.lastPathComponent.lowercased()
        if let label = filenameLabels[filename] {
            return label
        }
        return extensionLabels[url.pathExtension.lowercased()] ?? "Text"
    }

    private static func lineCountLabel(for text: String, wasTruncated: Bool) -> String {
        let countedText = text.hasSuffix("\n...") ? String(text.dropLast(4)) : text
        var lines = countedText.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last == "" {
            lines.removeLast()
        }
        let lineCount = max(lines.count, 1)
        let suffix = lineCount == 1 ? "line" : "lines"
        return "\(lineCount)\(wasTruncated ? "+" : "") \(suffix)"
    }

    private struct TextPreviewPayload {
        var text: String
        var typeLabel: String
        var lineCountLabel: String
        var byteSizeLabel: String?
        var wasTruncated: Bool

        var estimatedByteCount: Int {
            text.utf8.count
                + typeLabel.utf8.count
                + lineCountLabel.utf8.count
                + (byteSizeLabel?.utf8.count ?? 0)
        }
    }

    private final class TextPreviewCacheKey: NSObject {
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
            guard let other = object as? TextPreviewCacheKey else { return false }
            return path == other.path
                && fileSize == other.fileSize
                && modificationTime == other.modificationTime
                && resourceIdentifier == other.resourceIdentifier
        }
    }

    private final class TextPreviewCache: @unchecked Sendable {
        private final class Box: NSObject {
            let payload: TextPreviewPayload

            init(_ payload: TextPreviewPayload) {
                self.payload = payload
            }
        }

        private let storage: NSCache<TextPreviewCacheKey, Box>

        init() {
            let storage = NSCache<TextPreviewCacheKey, Box>()
            storage.countLimit = ToolArtifactTextPreviewBuilder.cacheEntryLimit
            storage.totalCostLimit = ToolArtifactTextPreviewBuilder.cacheByteLimit
            self.storage = storage
        }

        func value(for key: TextPreviewCacheKey) -> TextPreviewPayload? {
            storage.object(forKey: key)?.payload
        }

        func insert(_ payload: TextPreviewPayload, for key: TextPreviewCacheKey) {
            storage.setObject(Box(payload), forKey: key, cost: payload.estimatedByteCount)
        }

    }

    private static let cache = TextPreviewCache()
    private static let cacheEntryLimit = 16
    private static let cacheByteLimit = 128 * 1024

    private static let byteLimit = 6 * 1024
    private static let lineLimit = 80
    private static let filenames: Set<String> = [
        ".gitignore",
        ".dockerignore",
        ".editorconfig",
        ".gitattributes",
        ".npmrc",
        ".prettierrc",
        ".prettierrc.json",
        "build",
        "build.bazel",
        "build.gradle",
        "build.gradle.kts",
        "brewfile",
        "cargo.lock",
        "cargo.toml",
        "composer.json",
        "composer.lock",
        "cmakelists.txt",
        "default.nix",
        "deno.lock",
        "bun.lock",
        "dockerfile",
        "eslint.config.js",
        "eslint.config.mjs",
        "eslint.config.ts",
        "flake.nix",
        "gemfile",
        "gemfile.lock",
        "go.mod",
        "go.sum",
        "justfile",
        "license",
        "makefile",
        "meson.build",
        "next.config.js",
        "next.config.mjs",
        "next.config.ts",
        "package-lock.json",
        "package.json",
        "package.resolved",
        "pipfile.lock",
        "podfile",
        "podfile.lock",
        "poetry.lock",
        "procfile",
        "pyproject.toml",
        "readme",
        "requirements.txt",
        "settings.gradle",
        "settings.gradle.kts",
        "shell.nix",
        "tailwind.config.js",
        "tailwind.config.ts",
        "taskfile.yml",
        "taskfile.yaml",
        "tsconfig.json",
        "vite.config.js",
        "vite.config.mjs",
        "vite.config.ts",
        "workspace",
        "workspace.bazel",
        "yarn.lock",
        "pnpm-lock.yaml",
        "uv.lock"
    ]
    private static let filenameLabels: [String: String] = [
        ".gitignore": "Git ignore",
        ".dockerignore": "Docker ignore",
        ".editorconfig": "EditorConfig",
        ".gitattributes": "Git attributes",
        ".npmrc": "npm config",
        ".prettierrc": "Prettier config",
        ".prettierrc.json": "Prettier config",
        "build": "Bazel build",
        "build.bazel": "Bazel build",
        "build.gradle": "Gradle",
        "build.gradle.kts": "Gradle Kotlin",
        "brewfile": "Homebrew bundle",
        "cargo.lock": "Cargo lockfile",
        "cargo.toml": "Cargo manifest",
        "composer.json": "Composer package",
        "composer.lock": "Composer lockfile",
        "cmakelists.txt": "CMake",
        "default.nix": "Nix expression",
        "deno.lock": "Deno lockfile",
        "bun.lock": "Bun lockfile",
        "dockerfile": "Dockerfile",
        "eslint.config.js": "ESLint config",
        "eslint.config.mjs": "ESLint config",
        "eslint.config.ts": "ESLint config",
        "flake.nix": "Nix flake",
        "gemfile": "Gemfile",
        "gemfile.lock": "Bundler lockfile",
        "go.mod": "Go module",
        "go.sum": "Go checksum",
        "justfile": "Justfile",
        "license": "License",
        "makefile": "Makefile",
        "meson.build": "Meson build",
        "next.config.js": "Next.js config",
        "next.config.mjs": "Next.js config",
        "next.config.ts": "Next.js config",
        "package-lock.json": "npm lockfile",
        "package.json": "npm package",
        "package.resolved": "SwiftPM resolved packages",
        "pipfile.lock": "Pipfile lockfile",
        "podfile": "Podfile",
        "podfile.lock": "CocoaPods lockfile",
        "poetry.lock": "Poetry lockfile",
        "procfile": "Procfile",
        "pyproject.toml": "Python project",
        "readme": "README",
        "requirements.txt": "Python requirements",
        "settings.gradle": "Gradle settings",
        "settings.gradle.kts": "Gradle Kotlin settings",
        "shell.nix": "Nix shell",
        "tailwind.config.js": "Tailwind config",
        "tailwind.config.ts": "Tailwind config",
        "taskfile.yml": "Taskfile",
        "taskfile.yaml": "Taskfile",
        "tsconfig.json": "TypeScript config",
        "vite.config.js": "Vite config",
        "vite.config.mjs": "Vite config",
        "vite.config.ts": "Vite config",
        "workspace": "Bazel workspace",
        "workspace.bazel": "Bazel workspace",
        "yarn.lock": "Yarn lockfile",
        "pnpm-lock.yaml": "pnpm lockfile",
        "uv.lock": "uv lockfile"
    ]
    private static let extensions: Set<String> = [
        "astro",
        "c",
        "cc",
        "conf",
        "cpp",
        "cs",
        "csproj",
        "css",
        "csv",
        "diff",
        "fs",
        "fsproj",
        "go",
        "h",
        "hpp",
        "html",
        "java",
        "js",
        "json",
        "jsonl",
        "jsx",
        "kts",
        "kt",
        "log",
        "m",
        "md",
        "mdx",
        "mm",
        "ndjson",
        "nix",
        "patch",
        "php",
        "py",
        "rb",
        "rs",
        "sh",
        "sql",
        "svelte",
        "swift",
        "toml",
        "ts",
        "tsx",
        "txt",
        "vue",
        "xml",
        "yaml",
        "yml"
    ]
    private static let extensionLabels: [String: String] = [
        "astro": "Astro",
        "c": "C",
        "cc": "C++",
        "conf": "Config",
        "cpp": "C++",
        "cs": "C#",
        "csproj": "C# project",
        "css": "CSS",
        "csv": "CSV",
        "diff": "Diff",
        "fs": "F#",
        "fsproj": "F# project",
        "go": "Go",
        "h": "C/C++ header",
        "hpp": "C++ header",
        "html": "HTML",
        "java": "Java",
        "js": "JavaScript",
        "json": "JSON",
        "jsonl": "JSON Lines",
        "jsx": "React JSX",
        "kt": "Kotlin",
        "kts": "Kotlin Script",
        "log": "Log",
        "m": "Objective-C",
        "md": "Markdown",
        "mdx": "MDX",
        "mm": "Objective-C++",
        "ndjson": "NDJSON",
        "nix": "Nix",
        "patch": "Patch",
        "php": "PHP",
        "py": "Python",
        "rb": "Ruby",
        "rs": "Rust",
        "sh": "Shell",
        "sql": "SQL",
        "svelte": "Svelte",
        "swift": "Swift",
        "toml": "TOML",
        "ts": "TypeScript",
        "tsx": "React TSX",
        "txt": "Text",
        "vue": "Vue",
        "xml": "XML",
        "yaml": "YAML",
        "yml": "YAML"
    ]
}
