import Foundation
import QuillCodeCore

enum BundledExtensionMarketplace {
    static let manifests: [ProjectExtensionManifest] = [
        skill(
            id: "llm-advisor",
            name: "LLM Advisor",
            summary: "On-demand model selection, budget, limit, and TrustedRouter spend advice without bloating every prompt.",
            sourceURL: "https://github.com/Lore-Hex/LLM-advisor",
            repositoryPath: "Lore-Hex/LLM-advisor",
            sourceSkillPath: ".",
            installSkillName: "llm-advisor",
            copyCommand: "cp -R .quillcode/skill-repos/llm-advisor/SKILL.md .quillcode/skill-repos/llm-advisor/references .quillcode/skill-repos/llm-advisor/agents .quillcode/skills/llm-advisor/"
        ),
        skill(
            id: "browser-use",
            name: "Browser Use",
            summary: "On-demand browser automation skills for web research, CDP control, QA flows, and form-heavy tasks.",
            sourceURL: "https://github.com/browser-use/browser-use/tree/main/skills",
            repositoryPath: "browser-use/browser-use",
            sourceSkillPath: "skills/browser-use",
            installSkillName: "browser-use"
        ),
        skill(
            id: "openclaw-video-toolkit",
            name: "OpenClaw Video Toolkit",
            summary: "Video and media production workflow guidance from the Claude Code video toolkit.",
            sourceURL: "https://github.com/digitalsamba/claude-code-video-toolkit/tree/main/skills/openclaw-video-toolkit",
            repositoryPath: "digitalsamba/claude-code-video-toolkit",
            sourceSkillPath: "skills/openclaw-video-toolkit",
            installSkillName: "openclaw-video-toolkit"
        ),
        skill(
            id: "burstyrouter",
            name: "BurstyRouter",
            summary: "Local-first LLM routing to a local server with burst overflow to TrustedRouter Cloud.",
            sourceURL: "https://github.com/Lore-Hex/BurstyRouter",
            repositoryPath: "Lore-Hex/BurstyRouter",
            sourceSkillPath: "skills/bursty-setup",
            installSkillName: "burstyrouter"
        ),
        marketingSkillPack()
    ]

    private static func marketingSkillPack() -> ProjectExtensionManifest {
        let id = "marketing-skills"
        let name = "Marketing Skills"
        let summary = "79 on-demand marketing playbooks and 170 prompt templates for research, positioning, copy, launch, growth, and SEO work."
        let sourceURL = "https://github.com/Lore-Hex/marketing-skills"
        let repoDirectory = ".quillcode/skill-repos/\(id)"
        let skillDirectory = ".quillcode/skills/\(id)"
        let manifestPath = ".quillcode/skills/\(id).json"
        let refreshRepositoryCommand = "if [ -d \(repoDirectory)/.git ]; then git -C \(repoDirectory) pull --ff-only; else rm -rf \(repoDirectory) && git clone --depth 1 https://github.com/Lore-Hex/marketing-skills.git \(repoDirectory); fi"
        let copyCommand = marketingSkillPackCopyCommand(
            repoDirectory: repoDirectory,
            skillDirectory: skillDirectory
        )
        let updateCommand = "git -C \(repoDirectory) pull --ff-only && \(copyCommand)"
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

    static func marketingSkillPackCopyCommand(
        repoDirectory: String,
        skillDirectory: String
    ) -> String {
        let umbrellaSkill = """
        ---
        name: marketing-skills
        description: Coordinates the installed marketing playbook collection for cross-discipline work and exposes its prompt library as references without loading the whole collection into every turn.
        ---
        # Marketing Skills

        Use the most specific installed marketing skill for the requested deliverable. Load this umbrella skill when the work spans multiple marketing disciplines or when prompt templates would help.

        ## Workflow

        1. Ground the work in the supplied audience, product, channel, evidence, and constraints. Mark missing facts as assumptions or placeholders.
        2. Prefer a specific sibling skill such as `market-research`, `competitive-analysis`, `landing-page-copy`, `pricing-page`, or `product-hunt` when one clearly matches.
        3. Read only the relevant file under `references/prompts/` when a reusable prompt pattern is useful. Do not load all prompt files.
        4. Adapt templates to the current project. Never invent customer proof, market data, rankings, quotes, or performance claims.
        5. Deliver the requested artifact and include source-grounded decisions, open questions, and concrete next steps.
        """
        let writeUmbrella = "printf '%s\\n' \(shellSingleQuoted(umbrellaSkill)) > \(skillDirectory)/SKILL.md"
        let copySkills = "for source in \(repoDirectory)/skills/*.md; do skill_name=\"${source##*/}\"; skill_name=\"${skill_name%.md}\"; mkdir -p \(skillDirectory)/catalog/\"$skill_name\"; cp \"$source\" \(skillDirectory)/catalog/\"$skill_name\"/SKILL.md; done"

        return [
            "rm -rf \(skillDirectory)",
            "mkdir -p \(skillDirectory)/catalog \(skillDirectory)/references/prompts",
            copySkills,
            "cp \(repoDirectory)/prompts/*.md \(skillDirectory)/references/prompts/",
            writeUmbrella
        ].joined(separator: " && ")
    }

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
