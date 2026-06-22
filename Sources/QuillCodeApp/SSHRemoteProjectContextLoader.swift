import Foundation
import QuillCodeCore
import QuillCodeTools

struct SSHRemoteProjectContext: Sendable, Hashable {
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
}

enum SSHRemoteProjectContextLoadError: Error, LocalizedError, Equatable {
    case invalidConnection
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection:
            return "SSH Remote project is missing a usable host."
        case .commandFailed(let message):
            return message
        }
    }
}

enum SSHRemoteProjectContextLoader {
    static func load(
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws -> SSHRemoteProjectContext {
        let marker = "QUILLCODE_CONTEXT_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let request = executor.request(
            command: remoteProbeScript(marker: marker),
            connection: connection,
            timeoutSeconds: 30
        ) else {
            throw SSHRemoteProjectContextLoadError.invalidConnection
        }

        let result = ShellToolExecutor().run(request)
        guard result.ok else {
            let detail = result.error
                ?? [result.stderr, result.stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
                ?? "Could not refresh SSH Remote project context."
            throw SSHRemoteProjectContextLoadError.commandFailed(detail)
        }

        return parse(stdout: result.stdout, marker: marker)
    }

    private static func parse(stdout: String, marker: String) -> SSHRemoteProjectContext {
        var instructions: [ProjectInstruction] = []
        var memories: [MemoryNote] = []

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 6,
                  parts[0] == marker,
                  let path = string(fromHex: parts[2]),
                  let byteCount = Int(parts[3]),
                  let content = string(fromHex: parts[5])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  !content.isEmpty
            else {
                continue
            }

            let wasTruncated = parts[4] == "1"
            switch parts[1] {
            case "instruction":
                instructions.append(ProjectInstruction(
                    path: path,
                    title: instructionTitle(for: path),
                    content: wasTruncated
                        ? content + "\n\n[QuillCode truncated this instruction file at \(ProjectInstructionLoader.maxFileBytes) bytes.]"
                        : content,
                    byteCount: byteCount,
                    wasTruncated: wasTruncated
                ))
            case "memory":
                memories.append(MemoryNote(
                    id: "\(MemoryScope.project.rawValue):\(path)",
                    scope: .project,
                    title: memoryTitle(for: path),
                    content: wasTruncated
                        ? content + "\n\n[QuillCode truncated this memory file at \(MemoryNoteLoader.maxFileBytes) bytes.]"
                        : content,
                    relativePath: path,
                    byteCount: byteCount,
                    wasTruncated: wasTruncated
                ))
            default:
                continue
            }
        }

        return SSHRemoteProjectContext(
            instructions: instructions,
            memories: memories
        )
    }

    private static func remoteProbeScript(marker: String) -> String {
        """
        qc_marker=\(shellSingleQuoted(marker))
        qc_ins_count=0
        qc_ins_total=0
        qc_mem_count=0
        qc_mem_total=0

        qc_hex_text() {
          printf '%s' "$1" | od -An -tx1 -v | tr -d ' \\n'
        }

        qc_hex_file() {
          head -c "$2" "$1" | od -An -tx1 -v | tr -d ' \\n'
        }

        qc_file_size() {
          wc -c < "$1" 2>/dev/null | tr -d '[:space:]'
        }

        qc_emit_instruction() {
          qc_rel="$1"
          qc_file="./$qc_rel"
          [ "$qc_ins_count" -lt \(ProjectInstructionLoader.maxInstructionFiles) ] || return 0
          [ "$qc_ins_total" -lt \(ProjectInstructionLoader.maxTotalBytes) ] || return 0
          [ -f "$qc_file" ] || return 0
          [ ! -L "$qc_file" ] || return 0
          qc_size="$(qc_file_size "$qc_file")"
          case "$qc_size" in ''|*[!0-9]*) return 0 ;; esac
          qc_remaining=$((\(ProjectInstructionLoader.maxTotalBytes) - qc_ins_total))
          [ "$qc_remaining" -gt 0 ] || return 0
          qc_limit=\(ProjectInstructionLoader.maxFileBytes)
          [ "$qc_remaining" -lt "$qc_limit" ] && qc_limit="$qc_remaining"
          qc_truncated=0
          qc_read="$qc_size"
          if [ "$qc_size" -gt "$qc_limit" ]; then
            qc_truncated=1
            qc_read="$qc_limit"
          fi
          printf '%s\\tinstruction\\t%s\\t%s\\t%s\\t' "$qc_marker" "$(qc_hex_text "$qc_rel")" "$qc_read" "$qc_truncated"
          qc_hex_file "$qc_file" "$qc_limit"
          printf '\\n'
          qc_ins_count=$((qc_ins_count + 1))
          qc_ins_total=$((qc_ins_total + qc_read))
        }

        qc_emit_memory() {
          qc_rel="$1"
          qc_file="./$qc_rel"
          [ "$qc_mem_count" -lt \(MemoryNoteLoader.maxNotes) ] || return 0
          [ "$qc_mem_total" -lt \(MemoryNoteLoader.maxTotalBytes) ] || return 0
          [ -f "$qc_file" ] || return 0
          [ ! -L "$qc_file" ] || return 0
          case "$qc_rel" in
            *.md|*.txt|*.json) ;;
            *) return 0 ;;
          esac
          qc_size="$(qc_file_size "$qc_file")"
          case "$qc_size" in ''|*[!0-9]*) return 0 ;; esac
          qc_remaining=$((\(MemoryNoteLoader.maxTotalBytes) - qc_mem_total))
          [ "$qc_remaining" -gt 0 ] || return 0
          qc_limit=\(MemoryNoteLoader.maxFileBytes)
          [ "$qc_remaining" -lt "$qc_limit" ] && qc_limit="$qc_remaining"
          qc_truncated=0
          qc_read="$qc_size"
          if [ "$qc_size" -gt "$qc_limit" ]; then
            qc_truncated=1
            qc_read="$qc_limit"
          fi
          printf '%s\\tmemory\\t%s\\t%s\\t%s\\t' "$qc_marker" "$(qc_hex_text "$qc_rel")" "$qc_read" "$qc_truncated"
          qc_hex_file "$qc_file" "$qc_limit"
          printf '\\n'
          qc_mem_count=$((qc_mem_count + 1))
          qc_mem_total=$((qc_mem_total + qc_read))
        }

        qc_should_skip_dir() {
          qc_old_ifs="$IFS"
          IFS='/'
          for qc_part in $1; do
            case "$qc_part" in
              .build|.git|.hg|.svn|.quillcode|DerivedData|node_modules|Package.resolved|.*)
                IFS="$qc_old_ifs"
                return 0
                ;;
            esac
          done
          IFS="$qc_old_ifs"
          return 1
        }

        qc_emit_instruction 'AGENTS.md'
        qc_emit_instruction '.quillcode/rules.md'
        qc_emit_instruction '.quillcode/instructions.md'

        qc_scanned_dirs=0
        find . -type d 2>/dev/null | awk '{ print gsub("/", "/") "\t" $0 }' | sort -n -k1,1 -k2,2 | cut -f2- | while IFS= read -r qc_dir; do
          [ "$qc_scanned_dirs" -lt \(ProjectInstructionLoader.maxScannedDirectories) ] || break
          qc_rel="${qc_dir#./}"
          [ "$qc_rel" != "." ] || continue
          qc_should_skip_dir "$qc_rel" && continue
          qc_scanned_dirs=$((qc_scanned_dirs + 1))
          qc_emit_instruction "$qc_rel/AGENTS.md"
          qc_emit_instruction "$qc_rel/.quillcode/rules.md"
          qc_emit_instruction "$qc_rel/.quillcode/instructions.md"
        done

        for qc_memory in .quillcode/memories/*.json .quillcode/memories/*.md .quillcode/memories/*.txt; do
          [ -e "$qc_memory" ] || continue
          qc_emit_memory "${qc_memory#./}"
        done
        """
    }

    private static func instructionTitle(for relativePath: String) -> String {
        switch relativePath {
        case "AGENTS.md":
            return "Project AGENTS.md"
        case ".quillcode/rules.md":
            return "QuillCode rules"
        case ".quillcode/instructions.md":
            return "QuillCode instructions"
        default:
            return relativePath
        }
    }

    private static func memoryTitle(for relativePath: String) -> String {
        let baseName = URL(fileURLWithPath: relativePath)
            .deletingPathExtension()
            .lastPathComponent
        let words = baseName
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard !words.isEmpty else { return baseName }
        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func string(fromHex hex: String) -> String? {
        guard let data = data(fromHex: hex) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func data(fromHex hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
