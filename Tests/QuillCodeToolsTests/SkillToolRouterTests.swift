import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class SkillToolRouterTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testSkillLoadDefinitionIsRegistered() {
        let names = ToolRouter.definitions.map(\.name)
        XCTAssertTrue(names.contains(ToolDefinition.skillLoad.name))
        XCTAssertEqual(Set(names).count, names.count, "tool names must stay unique")
    }

    func testSkillLoadDefinitionShape() throws {
        let definition = ToolDefinition.skillLoad
        XCTAssertEqual(definition.name, "host.skill.load")
        XCTAssertEqual(definition.host, .local)
        XCTAssertEqual(definition.risk, .read)
        XCTAssertTrue(definition.parametersJSON.contains("\"name\""))
        XCTAssertTrue(definition.parametersJSON.contains("required"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(definition.parametersJSON.utf8)))
    }

    func testRouterDispatchesSkillLoadCalls() throws {
        // Skill lives in the project's .quillcode/skills — the default user root.
        let skillsDir = tempRoot
            .appendingPathComponent(".quillcode", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try "# Demo skill\nHello from the skill.\n".write(
            to: skillsDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let router = ToolRouter(
            workspaceRoot: tempRoot,
            skill: SkillLoadToolExecutor(resolver: SkillResolver(roots: [
                SkillRoot(kind: .user, url: tempRoot
                    .appendingPathComponent(".quillcode", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true))
            ]))
        )
        let result = router.execute(ToolCall(
            name: ToolDefinition.skillLoad.name,
            argumentsJSON: #"{"name":"demo"}"#
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("<skill_content"))
        XCTAssertTrue(result.stdout.contains("Hello from the skill."))
    }

    func testRouterRejectsMissingNameArgument() {
        let router = ToolRouter(workspaceRoot: tempRoot)
        let result = router.execute(ToolCall(name: ToolDefinition.skillLoad.name, argumentsJSON: "{}"))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("name") == true, result.error ?? "")
    }

    func testDefaultResolverUsesProjectSkillsDirectory() throws {
        // The default ToolRouter wires SkillLoadToolExecutor.default(workspaceRoot:), whose user root
        // is <workspace>/.quillcode/skills. Prove a skill placed there resolves without a custom executor.
        let skillsDir = tempRoot
            .appendingPathComponent(".quillcode", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("wired", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try "# Wired\n".write(
            to: skillsDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let router = ToolRouter(workspaceRoot: tempRoot)
        let result = router.execute(ToolCall(
            name: ToolDefinition.skillLoad.name,
            argumentsJSON: #"{"name":"wired"}"#
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("source=\"user\""))
    }
}
