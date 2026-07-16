import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import XCTest

final class AppServerRichTurnInputTests: XCTestCase {
    func testSelectedSkillSnapshotsContextAndProjectsCodexWireShape() throws {
        let fixture = try makeFixture()
        let manifest = try fixture.writeSkill(name: "review", body: "Inspect every changed file.")
        let input = try fixture.input([
            .object(["type": .string("text"), "text": .string("Review this change")]),
            .object([
                "type": .string("skill"),
                "name": .string("review"),
                "path": .string(manifest.path)
            ])
        ])
        let message = input.message(turnID: "turn-rich")

        XCTAssertEqual(message.content, "Review this change")
        XCTAssertEqual(message.inputReferences.count, 1)
        XCTAssertEqual(message.inputReferences[0].kind, .skill)
        XCTAssertEqual(message.inputReferences[0].name, "review")
        XCTAssertEqual(message.inputReferences[0].path, manifest.resolvingSymlinksInPath().path)
        XCTAssertTrue(message.inputReferences[0].context?.contains("Inspect every changed file.") == true)

        let projected = try XCTUnwrap(
            AppServerThreadProjection.userMessageItem(message).objectValue?["content"]?.arrayValue?
                .compactMap(\.objectValue)
        )
        XCTAssertEqual(projected.compactMap { $0["type"]?.stringValue }, ["text", "skill"])
        XCTAssertEqual(projected[1]["name"]?.stringValue, "review")
        XCTAssertEqual(projected[1]["path"]?.stringValue, manifest.resolvingSymlinksInPath().path)

        try "Changed after the turn.".write(to: manifest, atomically: true, encoding: .utf8)
        let prompt = try XCTUnwrap(modelUserText(for: message))
        XCTAssertTrue(prompt.contains("<skill>"))
        XCTAssertTrue(prompt.contains("Inspect every changed file."))
        XCTAssertFalse(prompt.contains("Changed after the turn."))

        let roundTrip = try JSONDecoder().decode(
            ChatMessage.self,
            from: JSONEncoder().encode(message)
        )
        XCTAssertEqual(roundTrip, message)
    }

    func testStructuredMentionIsBoundedMetadataAndNeverReadAsAFile() throws {
        let fixture = try makeFixture()
        let path = "app://calendar-connector"
        let input = try fixture.input([
            .object([
                "type": .string("mention"),
                "name": .string("Calendar"),
                "path": .string(path)
            ])
        ])
        let message = input.message(turnID: "turn-mention")

        XCTAssertEqual(message.content, "")
        XCTAssertEqual(
            message.inputReferences,
            [ChatInputReference(kind: .mention, name: "Calendar", path: path)]
        )
        XCTAssertEqual(modelUserText(for: message), "[mention:Calendar](app://calendar-connector)")
        let projected = try XCTUnwrap(
            AppServerThreadProjection.userMessageItem(message).objectValue?["content"]?
                .arrayValue?.first?.objectValue
        )
        XCTAssertEqual(projected["type"]?.stringValue, "mention")
        XCTAssertEqual(projected["name"]?.stringValue, "Calendar")
        XCTAssertEqual(projected["path"]?.stringValue, path)
    }

    func testSkillSelectionRejectsArbitraryAndDisabledPaths() throws {
        let fixture = try makeFixture()
        let manifest = try fixture.writeSkill(name: "allowed", body: "Allowed instructions.")
        let outside = fixture.workspace.appendingPathComponent("outside.md")
        try "Not a discovered skill.".write(to: outside, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try fixture.input([
            .object([
                "type": .string("skill"),
                "name": .string("outside"),
                "path": .string(outside.path)
            ])
        ]))

        var disabled = SkillConfiguration()
        disabled.setPath(manifest.path, enabled: false)
        XCTAssertThrowsError(try fixture.input([
            .object([
                "type": .string("skill"),
                "name": .string("allowed"),
                "path": .string(manifest.path)
            ])
        ], configuration: disabled))
    }

    func testDuplicateSkillPathInjectsOnlyOnce() throws {
        let fixture = try makeFixture()
        let manifest = try fixture.writeSkill(name: "once", body: "Only once.")
        let skill: CLIJSONValue = .object([
            "type": .string("skill"),
            "name": .string("once"),
            "path": .string(manifest.path)
        ])
        let mentions = (0..<ChatInputReference.maximumCountPerMessage - 1).map { index in
            CLIJSONValue.object([
                "type": .string("mention"),
                "name": .string("app-\(index)"),
                "path": .string("app://app-\(index)")
            ])
        }

        let input = try fixture.input([skill] + mentions + [skill])

        XCTAssertEqual(input.inputReferences.count, ChatInputReference.maximumCountPerMessage)
        XCTAssertEqual(modelUserText(for: input.message(turnID: "turn-once"))?.components(
            separatedBy: "<skill>"
        ).count, 2)
    }

    func testRichInputRejectsControlCharactersAndReferenceOverflow() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(try fixture.input([
            .object([
                "type": .string("mention"),
                "name": .string("bad\nname"),
                "path": .string("app://demo")
            ])
        ]))

        let references = (0...ChatInputReference.maximumCountPerMessage).map { index in
            CLIJSONValue.object([
                "type": .string("mention"),
                "name": .string("app-\(index)"),
                "path": .string("app://app-\(index)")
            ])
        }
        XCTAssertThrowsError(try fixture.input(references))
    }

    private func modelUserText(for message: ChatMessage) -> String? {
        var thread = ChatThread(title: "Rich input")
        thread.messages = [message]
        return TrustedRouterPromptBuilder().messages(
            thread: thread,
            userMessage: message.content,
            tools: []
        ).last?["content"] as? String
    }

    private func makeFixture() throws -> RichInputFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-rich-input-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RichInputFixture(root: root)
    }
}

private struct RichInputFixture {
    var root: URL
    var workspace: URL { root.appendingPathComponent("workspace", isDirectory: true) }
    var skillRoot: URL {
        workspace
            .appendingPathComponent(".agents", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    func writeSkill(name: String, body: String) throws -> URL {
        let directory = skillRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("SKILL.md")
        try """
        ---
        name: \(name)
        description: Test skill
        ---
        \(body)
        """.write(to: manifest, atomically: true, encoding: .utf8)
        return manifest
    }

    func input(
        _ items: [CLIJSONValue],
        configuration: SkillConfiguration = SkillConfiguration()
    ) throws -> AppServerTurnInput {
        try AppServerTurnInput(
            params: AppServerParams(.object(["input": .array(items)])),
            threadID: UUID(),
            attachmentStore: ImageAttachmentStore(
                directory: root.appendingPathComponent("attachments", isDirectory: true)
            ),
            richInputResolver: AppServerRichTurnInputResolver(
                cwd: workspace,
                skillResolver: SkillResolver(
                    roots: [SkillRoot(kind: .repo, url: skillRoot)],
                    configuration: configuration
                )
            )
        )
    }
}
