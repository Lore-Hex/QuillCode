import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import XCTest

final class CLIRuntimeFactoryTests: XCTestCase {
    func testInvocationPolicyMapsOnlyDangerFullAccessToUnrestrictedHostTools() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-policy-\(UUID().uuidString)", isDirectory: true)
        let paths = QuillCodePaths(home: workspace.appendingPathComponent("home"))
        try paths.ensure()
        defer { try? FileManager.default.removeItem(at: workspace) }

        func configuration(_ sandbox: CLISandboxMode) -> CLIRuntimeConfiguration {
            CLIRuntimeConfiguration(
                request: CLIRunRequest(
                    style: .exec,
                    prompt: "inspect",
                    live: false,
                    cwd: workspace,
                    sandbox: sandbox
                ),
                appConfig: AppConfig(),
                paths: paths,
                imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory),
                environment: [:]
            )
        }

        XCTAssertEqual(
            configuration(.readOnly).applyingInvocationPolicy(to: AgentRunner()).hostToolAccessScope,
            .workspaceOnly
        )
        XCTAssertEqual(
            configuration(.workspaceWrite).applyingInvocationPolicy(to: AgentRunner()).hostToolAccessScope,
            .workspaceOnly
        )
        XCTAssertEqual(
            configuration(.dangerFullAccess).applyingInvocationPolicy(to: AgentRunner()).hostToolAccessScope,
            .unrestricted
        )
    }

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

    func testMakeConfiguresCompactionForDeterministicRuns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-compaction-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let paths = QuillCodePaths(home: home)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try paths.ensure()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = try CLIRuntimeFactory.make(CLIRuntimeConfiguration(
            request: CLIRunRequest(
                style: .exec,
                prompt: "compact",
                live: false,
                cwd: workspace,
                home: home
            ),
            appConfig: AppConfig(),
            paths: paths,
            imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory),
            environment: [:]
        ))

        XCTAssertNotNil(runner.compaction)
    }
}
