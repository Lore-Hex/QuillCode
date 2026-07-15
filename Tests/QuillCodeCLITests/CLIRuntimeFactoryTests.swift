import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import XCTest

final class CLIRuntimeFactoryTests: XCTestCase {
    func testMakeDoesNotAdvertiseOrLoadConfiguredDisabledSkills() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-runtime-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let skillDirectory = workspace.appendingPathComponent(
            ".agents/skills/review",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        ---
        name: review
        description: Review code for correctness defects.
        ---
        """.write(
            to: skillDirectory.appendingPathComponent(SkillResolver.manifestFileName),
            atomically: true,
            encoding: .utf8
        )
        let paths = QuillCodePaths(home: home)
        try paths.ensure()

        let runner = try CLIRuntimeFactory.make(CLIRuntimeConfiguration(
            request: CLIRunRequest(
                style: .exec,
                prompt: "Use review",
                live: false,
                cwd: workspace,
                home: home,
                ignoresPermissionRules: true
            ),
            appConfig: AppConfig(
                skillConfiguration: SkillConfiguration(disabledNames: ["review"])
            ),
            paths: paths,
            imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory),
            environment: [:]
        ))

        let resolver = try XCTUnwrap(runner.skillResolver)
        XCTAssertFalse(resolver.availableSkillNames().contains("review"))
        XCTAssertThrowsError(try resolver.resolve(name: "review"))
    }
}
