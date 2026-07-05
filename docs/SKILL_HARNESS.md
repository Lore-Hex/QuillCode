# Skill Harness

QuillCode treats skills as on-demand capability packages, not text that lives in every base prompt.

## Prompt Budget Rule

The base system prompt may name the skill mechanism and the decision rule for when to load skills. It should not embed
full model-advisor tables, browser recipes, video workflows, benchmark notes, or long vendor-specific instructions.

Normal flow:

1. Index skill names, descriptions, source URLs, and project/global availability.
2. Show matching skills in slash commands, Extensions, search, and command surfaces.
3. When the user invokes a skill, or the agent sees a clearly relevant task, call `host.skill.load`.
4. Load only the selected skill's `SKILL.md` first.
5. Read additional referenced files only when the skill asks for them and the current task needs them.

That keeps common turns short while still making deep workflows available.

## How To Explain Skills In The UI

Use this wording in compact UI surfaces:

> Skills are on-demand playbooks. QuillCode indexes their names and descriptions, then loads the skill instructions only
> when the task needs them.

Use this wording in longer help/settings copy:

> Skills can add browser automation, video production, code review, model selection, release workflows, and project-local
> knowledge without bloating every prompt. The agent sees a small registry entry by default. It loads `SKILL.md` with
> `host.skill.load` only when the user invokes `/skill name` or the task clearly matches the skill.

## Installed Skill Shape

A skill should live in a directory with a bounded `SKILL.md` entry point:

```text
.quillcode/skills/browser-use/SKILL.md
.quillcode/skills/browser-use/references/...
```

`SKILL.md` should contain:

- short name and trigger description
- required binaries, environment variables, or setup notes
- smallest safe invocation example
- routing rules for any larger reference files
- cleanup rules for resources that may keep billing or background processes alive

Heavy examples, workflow templates, and domain-specific recipes should stay in referenced files or folders.

## Project Manifest Shape

Project-local skill manifests are already supported through `.quillcode/skills/*.json`. A remote catalog entry should be
small and installable through an audited shell tool card:

```json
{
  "id": "browser-use",
  "kind": "skill",
  "name": "Browser Use",
  "summary": "CDP browser automation, scraping, testing, screenshots, and site/app work.",
  "sourceURL": "https://github.com/browser-use/browser-use/tree/main/skills",
  "relativePath": ".quillcode/skills/browser-use",
  "installCommand": "mkdir -p .quillcode/skills && git clone --depth 1 https://github.com/browser-use/browser-use .quillcode/skills/browser-use-repo && cp -R .quillcode/skills/browser-use-repo/skills/browser-use .quillcode/skills/browser-use",
  "updateCommand": "git -C .quillcode/skills/browser-use-repo pull --ff-only && rm -rf .quillcode/skills/browser-use && cp -R .quillcode/skills/browser-use-repo/skills/browser-use .quillcode/skills/browser-use"
}
```

Future signed marketplace entries should keep the same core fields while replacing raw shell install commands with a
verified package installer.

## Useful External Packs

- [`Lore-Hex/BurstyRouter`](https://github.com/Lore-Hex/BurstyRouter): good fit for a local-first LLM routing skill.
  The default catalog entry is intentionally tiny: it advertises a local server plus TrustedRouter burst-overflow path
  without loading routing instructions into every prompt. Once the repo publishes a `SKILL.md` package, wire its install
  command so `host.skill.load` can load the full playbook on demand.
- [`browser-use/browser-use` skills](https://github.com/browser-use/browser-use/tree/main/skills): good fit for a
  browser automation skill pack. Its `browser-use` skill is a compact entry point for CDP control, and it keeps optional
  domain/interaction skills out of the default path until needed.
- [`digitalsamba/claude-code-video-toolkit`](https://github.com/digitalsamba/claude-code-video-toolkit): good fit for a
  video-production skill pack. The repo exposes `skills/openclaw-video-toolkit/SKILL.md`, with detailed long-running
  workflow rules that should be loaded only when the user is actually making video.

## Prompt Contract

The base prompt should say only:

```text
Use installed skills for specialized tasks. Prefer loading the relevant skill over relying on memory when the task
matches a skill's description. Keep unrelated skill content out of the prompt.
```

Specialized prompts may add a one-line pointer such as "TrustedRouter model advice is skill-backed" but should not copy
the full advisor or workflow into every request.
