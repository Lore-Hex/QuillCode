public extension ToolDefinition {
    static let codeReviewSubmit = ToolDefinition(
        name: "host.review.submit",
        description: "Submit the complete prioritized review exactly once, including when there are no findings.",
        parametersJSON: #"""
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "summary": {
              "type": "string",
              "description": "Concise overall review assessment."
            },
            "findings": {
              "type": "array",
              "maxItems": 100,
              "items": {
                "type": "object",
                "additionalProperties": false,
                "properties": {
                  "priority": { "type": "string", "enum": ["P0", "P1", "P2", "P3"] },
                  "title": { "type": "string" },
                  "body": { "type": "string" },
                  "path": {
                    "type": "string",
                    "description": "Workspace-relative file path."
                  },
                  "line": { "type": "integer", "minimum": 1 },
                  "endLine": { "type": "integer", "minimum": 1 }
                },
                "required": ["priority", "title", "body", "path"]
              }
            }
          },
          "required": ["summary", "findings"]
        }
        """#,
        risk: .read
    )
}
