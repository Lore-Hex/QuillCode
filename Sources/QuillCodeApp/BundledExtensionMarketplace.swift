import Foundation
import QuillCodeCore

enum BundledExtensionMarketplace {
    static let manifests: [ProjectExtensionManifest] = [
        skill(
            id: "llm-advisor",
            name: "LLM Advisor",
            summary: "Choose cost-aware TrustedRouter models without loading the full playbook into every prompt.",
            sourceURL: "https://github.com/Lore-Hex/LLM-advisor",
            repositoryPath: "Lore-Hex/LLM-advisor",
            sourceSkillPath: ".",
            installSkillName: "llm-advisor",
            copyCommand: "cp -R .quillcode/skill-repos/llm-advisor/SKILL.md .quillcode/skill-repos/llm-advisor/references .quillcode/skill-repos/llm-advisor/agents .quillcode/skills/llm-advisor/"
        ),
        skill(
            id: "browser-use",
            name: "Browser Use",
            summary: "On-demand browser automation playbooks for CDP-driven web tasks and QA flows.",
            sourceURL: "https://github.com/browser-use/browser-use/tree/main/skills",
            repositoryPath: "browser-use/browser-use",
            sourceSkillPath: "skills/browser-use",
            installSkillName: "browser-use"
        ),
        skill(
            id: "openclaw-video-toolkit",
            name: "OpenClaw Video Toolkit",
            summary: "Video-production workflow guidance from the Claude Code video toolkit.",
            sourceURL: "https://github.com/digitalsamba/claude-code-video-toolkit/tree/main/skills/openclaw-video-toolkit",
            repositoryPath: "digitalsamba/claude-code-video-toolkit",
            sourceSkillPath: "skills/openclaw-video-toolkit",
            installSkillName: "openclaw-video-toolkit"
        ),
        skill(
            id: "burstyrouter",
            name: "BurstyRouter",
            summary: "Route LLM calls local-first to a local server, then burst overflow to TrustedRouter Cloud.",
            sourceURL: "https://github.com/Lore-Hex/BurstyRouter",
            repositoryPath: "Lore-Hex/BurstyRouter",
            sourceSkillPath: "skills/bursty-setup",
            installSkillName: "burstyrouter"
        )
    ]

    static func availableManifests(
        excluding claimedManifests: [ProjectExtensionManifest]
    ) -> [ProjectExtensionManifest] {
        let claimedIDs = Set(claimedManifests.map(\.id))
        return Self.manifests.filter { !claimedIDs.contains($0.id) }
    }

    private static func skill(
        id: String,
        name: String,
        summary: String,
        sourceURL: String,
        repositoryPath: String,
        sourceSkillPath: String,
        installSkillName: String,
        copyCommand customCopyCommand: String? = nil
    ) -> ProjectExtensionManifest {
        let repoDirectory = ".quillcode/skill-repos/\(id)"
        let skillDirectory = ".quillcode/skills/\(installSkillName)"
        let manifestPath = ".quillcode/skills/\(installSkillName).json"
        let gitURL = "https://github.com/\(repositoryPath).git"
        let refreshRepositoryCommand = "if [ -d \(repoDirectory)/.git ]; then git -C \(repoDirectory) pull --ff-only; else rm -rf \(repoDirectory) && git clone --depth 1 \(gitURL) \(repoDirectory); fi"
        let copyCommand = customCopyCommand ?? "cp -R \(repoDirectory)/\(sourceSkillPath)/. \(skillDirectory)/"
        let updateCommand = "git -C \(repoDirectory) pull --ff-only && rm -rf \(skillDirectory) && mkdir -p \(skillDirectory) && \(copyCommand)"
        let manifestJSON = installedSkillManifestJSON(
            id: id,
            name: name,
            summary: summary,
            sourceURL: sourceURL,
            updateCommand: updateCommand
        )
        let installCommand = [
            "mkdir -p .quillcode/skills .quillcode/skill-repos",
            refreshRepositoryCommand,
            "rm -rf \(skillDirectory)",
            "mkdir -p \(skillDirectory)",
            copyCommand,
            "printf '%s\\n' \(shellSingleQuoted(manifestJSON)) > \(manifestPath)"
        ].joined(separator: " && ")

        return ProjectExtensionManifest(
            id: "skill:\(id)",
            kind: .skill,
            name: name,
            summary: summary,
            sourceURL: sourceURL,
            relativePath: ".quillcode/marketplace/\(id).json",
            installCommand: installCommand,
            installTimeoutSeconds: 300
        )
    }

    private struct InstalledSkillManifestPayload: Encodable {
        var id: String
        var kind = "skill"
        var name: String
        var summary: String
        var source: String
        var updateCommand: String
    }

    private static func installedSkillManifestJSON(
        id: String,
        name: String,
        summary: String,
        sourceURL: String,
        updateCommand: String
    ) -> String {
        let payload = InstalledSkillManifestPayload(
            id: id,
            name: name,
            summary: summary,
            source: sourceURL,
            updateCommand: updateCommand
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    private static func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
