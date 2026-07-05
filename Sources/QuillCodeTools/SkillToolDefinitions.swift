import QuillCodeCore

public extension ToolDefinition {
    static let skillLoad = ToolDefinition(
        name: "host.skill.load",
        description: """
        Load an installed skill into context by name. Skills are listed in the extensions pane; this \
        tool reads the skill's SKILL.md and returns a <skill_content> block with the skill's base \
        directory (absolute path), a listing of its files, and the SKILL.md body. After loading, follow \
        the instructions in the body and read any referenced skill files by their absolute path with \
        host.file.read. A user skill (in the project's .quillcode/skills) shadows a builtin skill of the \
        same name. Pass a bare skill name, e.g. `code-review` — not a path. This loads skill content; it \
        does not run any skill code.
        """,
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "name": {
              "type": "string",
              "minLength": 1,
              "description": "The bare name of the skill to load, e.g. code-review. Not a path; no slashes or .. segments."
            }
          },
          "required": ["name"]
        }
        """,
        host: .local,
        risk: .read
    )
}
