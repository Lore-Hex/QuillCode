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
        guard kind == .file,
              !artifact.isImagePreview,
              artifact.documentPreview?.kind != .appshot,
              artifact.documentPreview?.extensionLabel.lowercased() != "env",
              artifact.tablePreview == nil,
              let fileURL = localArtifactFileURL(for: value),
              isTextPreviewCandidate(fileURL)
        else { return nil }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues.isRegularFile == true else { return nil }

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
            return TextPreviewPayload(
                text: text,
                typeLabel: typeLabel(for: fileURL),
                lineCountLabel: lineCountLabel(for: text, wasTruncated: wasTruncated),
                byteSizeLabel: resourceValues.fileSize.flatMap(ToolArtifactByteSizeFormatter.label),
                wasTruncated: wasTruncated
            )
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
    }

    private static let byteLimit = 6 * 1024
    private static let lineLimit = 80
    private static let filenames: Set<String> = [
        ".gitignore",
        ".npmrc",
        "build.gradle",
        "build.gradle.kts",
        "cargo.lock",
        "cargo.toml",
        "composer.json",
        "composer.lock",
        "dockerfile",
        "eslint.config.js",
        "eslint.config.mjs",
        "eslint.config.ts",
        "gemfile",
        "go.mod",
        "go.sum",
        "license",
        "makefile",
        "next.config.js",
        "next.config.mjs",
        "next.config.ts",
        "package-lock.json",
        "package.json",
        "podfile",
        "poetry.lock",
        "pyproject.toml",
        "readme",
        "requirements.txt",
        "settings.gradle",
        "settings.gradle.kts",
        "tailwind.config.js",
        "tailwind.config.ts",
        "tsconfig.json",
        "vite.config.js",
        "vite.config.mjs",
        "vite.config.ts"
    ]
    private static let filenameLabels: [String: String] = [
        ".gitignore": "Git ignore",
        ".npmrc": "npm config",
        "build.gradle": "Gradle",
        "build.gradle.kts": "Gradle Kotlin",
        "cargo.lock": "Cargo lockfile",
        "cargo.toml": "Cargo manifest",
        "composer.json": "Composer package",
        "composer.lock": "Composer lockfile",
        "dockerfile": "Dockerfile",
        "eslint.config.js": "ESLint config",
        "eslint.config.mjs": "ESLint config",
        "eslint.config.ts": "ESLint config",
        "gemfile": "Gemfile",
        "go.mod": "Go module",
        "go.sum": "Go checksum",
        "license": "License",
        "makefile": "Makefile",
        "next.config.js": "Next.js config",
        "next.config.mjs": "Next.js config",
        "next.config.ts": "Next.js config",
        "package-lock.json": "npm lockfile",
        "package.json": "npm package",
        "podfile": "Podfile",
        "poetry.lock": "Poetry lockfile",
        "pyproject.toml": "Python project",
        "readme": "README",
        "requirements.txt": "Python requirements",
        "settings.gradle": "Gradle settings",
        "settings.gradle.kts": "Gradle Kotlin settings",
        "tailwind.config.js": "Tailwind config",
        "tailwind.config.ts": "Tailwind config",
        "tsconfig.json": "TypeScript config",
        "vite.config.js": "Vite config",
        "vite.config.mjs": "Vite config",
        "vite.config.ts": "Vite config"
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
