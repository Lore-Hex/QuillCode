import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class LSPToolRouterTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-lsp-router-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        workspace = workspace.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    private func registry(available: Bool) -> LSPServerRegistry {
        LSPServerRegistry(
            configs: LSPServerRegistry.defaults,
            commandLocator: StubCommandLocator(resolvedPath: available ? "/usr/bin/sourcekit-lsp" : nil)
        )
    }

    private func coordinator(server: StubLanguageServer, available: Bool = true, formatOnSave: Bool = false) -> LSPCoordinator {
        let launcher = StubLSPServerLauncher { server }
        let sessions = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: available), launcher: launcher)
        return LSPCoordinator(workspaceRoot: workspace, sessions: sessions, formatOnSave: formatOnSave, diagnosticsWait: 0.4)
    }

    func testDefinitionsIncludeLSPNavTools() {
        let names = ToolRouter.definitions.map(\.name)
        XCTAssertTrue(names.contains("host.lsp.definition"))
        XCTAssertTrue(names.contains("host.lsp.references"))
        XCTAssertTrue(names.contains("host.lsp.hover"))
        XCTAssertTrue(names.contains("host.lsp.document_symbol"))
        XCTAssertTrue(names.contains("host.lsp.workspace_symbol"))
    }

    func testLSPToolSchemasAreValidJSONObjects() throws {
        let definitions = ToolRouter.definitions.filter { $0.name.hasPrefix("host.lsp.") }
        XCTAssertEqual(definitions.count, 5)

        for definition in definitions {
            let data = try XCTUnwrap(definition.parametersJSON.data(using: .utf8))
            XCTAssertTrue(
                try JSONSerialization.jsonObject(with: data) is [String: Any],
                "\(definition.name) parametersJSON should be a JSON object schema."
            )
        }
    }

    func testFileWriteWithoutLSPBehavesUnchanged() {
        // No coordinator injected -> existing write behavior, no diagnostics text.
        let router = ToolRouter(workspaceRoot: workspace, editGuard: FileEditSessionGuard())
        let call = ToolCall(name: "host.file.write", argumentsJSON: ToolArguments.json([
            "path": "A.swift", "content": "let x = 1\n"
        ]))
        let result = router.execute(call)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.hasPrefix("Wrote "))
        XCTAssertFalse(result.stdout.contains("LSP diagnostics"))
    }

    func testFileWriteAppendsDiagnostics() throws {
        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": [:]]
        let uri = LSPURI.from(path: workspace.appendingPathComponent("A.swift").path)
        server.diagnosticsOnSave[uri] = [[
            "range": ["start": ["line": 2, "character": 0], "end": ["line": 2, "character": 3]],
            "severity": 1,
            "message": "type 'Foo' has no member 'bar'"
        ]]
        let router = ToolRouter(
            workspaceRoot: workspace,
            editGuard: FileEditSessionGuard(),
            lsp: coordinator(server: server)
        )
        let call = ToolCall(name: "host.file.write", argumentsJSON: ToolArguments.json([
            "path": "A.swift", "content": "struct Foo {}\nlet f = Foo()\nf.bar()\n"
        ]))
        let result = router.execute(call)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("Wrote "), result.stdout)
        XCTAssertTrue(result.stdout.contains("LSP diagnostics"), result.stdout)
        XCTAssertTrue(result.stdout.contains("A.swift:3: error: type 'Foo' has no member 'bar'"), result.stdout)
    }

    func testFileWriteMissingServerStillSucceeds() throws {
        let server = StubLanguageServer()
        let router = ToolRouter(
            workspaceRoot: workspace,
            editGuard: FileEditSessionGuard(),
            lsp: coordinator(server: server, available: false)
        )
        let call = ToolCall(name: "host.file.write", argumentsJSON: ToolArguments.json([
            "path": "A.swift", "content": "let x = 1\n"
        ]))
        let result = router.execute(call)
        XCTAssertTrue(result.ok, "a missing language server must never fail the write")
        XCTAssertTrue(result.stdout.contains("Wrote "))
        // The one-time "not available" notice is appended, but the write result is still ok.
        XCTAssertTrue(result.stdout.contains("not available"))
    }

    func testNavToolWithoutCoordinatorReportsUnavailable() {
        let router = ToolRouter(workspaceRoot: workspace, editGuard: FileEditSessionGuard())
        let call = ToolCall(name: "host.lsp.definition", argumentsJSON: ToolArguments.json([
            "path": "A.swift", "line": "1", "character": "0"
        ]))
        let result = router.execute(call)
        XCTAssertFalse(result.ok)
        XCTAssertTrue((result.error ?? "").contains("not available"))
    }

    func testNavDefinitionReturnsLocations() throws {
        _ = try Data("struct Foo {}\n".utf8).write(to: workspace.appendingPathComponent("A.swift"))
        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": [:]]
        server.resultsByMethod["textDocument/definition"] = [[
            "uri": LSPURI.from(path: workspace.appendingPathComponent("A.swift").path),
            "range": ["start": ["line": 0, "character": 7], "end": ["line": 0, "character": 10]]
        ]]
        let router = ToolRouter(
            workspaceRoot: workspace,
            editGuard: FileEditSessionGuard(),
            lsp: coordinator(server: server)
        )
        let call = ToolCall(name: "host.lsp.definition", argumentsJSON: ToolArguments.json([
            "path": "A.swift", "line": "1", "character": "8"
        ]))
        let result = router.execute(call)
        XCTAssertTrue(result.ok, result.error ?? "")
        // Relative path + 1-based line/column.
        XCTAssertTrue(result.stdout.contains("A.swift:1:8"), result.stdout)
    }

    func testNavHoverReturnsText() throws {
        _ = try Data("let x = 1\n".utf8).write(to: workspace.appendingPathComponent("A.swift"))
        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": [:]]
        server.resultsByMethod["textDocument/hover"] = ["contents": ["kind": "plaintext", "value": "let x: Int"]]
        let router = ToolRouter(
            workspaceRoot: workspace,
            editGuard: FileEditSessionGuard(),
            lsp: coordinator(server: server)
        )
        let call = ToolCall(name: "host.lsp.hover", argumentsJSON: ToolArguments.json([
            "path": "A.swift", "line": "1", "character": "4"
        ]))
        let result = router.execute(call)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("let x: Int"), result.stdout)
    }

    func testNavPathBoundaryEnforced() {
        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": [:]]
        let router = ToolRouter(
            workspaceRoot: workspace,
            editGuard: FileEditSessionGuard(),
            lsp: coordinator(server: server)
        )
        let call = ToolCall(name: "host.lsp.definition", argumentsJSON: ToolArguments.json([
            "path": "../../etc/passwd", "line": "1", "character": "0"
        ]))
        let result = router.execute(call)
        XCTAssertFalse(result.ok, "a path escaping the workspace must be rejected")
    }

    func testApplyPatchAppendsDiagnostics() throws {
        // Seed a git repo so apply_patch's `git apply` works.
        let git = { (args: [String]) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            process.currentDirectoryURL = self.workspace
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
        git(["init"])
        git(["config", "user.email", "t@t.co"])
        git(["config", "user.name", "t"])
        let target = workspace.appendingPathComponent("A.swift")
        try Data("let x = 1\n".utf8).write(to: target)
        git(["add", "."])
        git(["commit", "-m", "init"])

        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": [:]]
        server.diagnosticsOnSave[LSPURI.from(path: target.path)] = [[
            "range": ["start": ["line": 1, "character": 0], "end": ["line": 1, "character": 3]],
            "severity": 1,
            "message": "cannot find 'zzz' in scope"
        ]]
        let router = ToolRouter(
            workspaceRoot: workspace,
            editGuard: FileEditSessionGuard(),
            lsp: coordinator(server: server)
        )
        // The edit guard requires the file be read in this session before it can be patched.
        _ = router.execute(ToolCall(name: "host.file.read", argumentsJSON: ToolArguments.json(["path": "A.swift"])))
        let patch = """
        diff --git a/A.swift b/A.swift
        index 0000000..1111111 100644
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1,2 @@
         let x = 1
        +zzz
        """
        let call = ToolCall(name: "host.apply_patch", argumentsJSON: ToolArguments.json(["patch": patch]))
        let result = router.execute(call)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("LSP diagnostics"), result.stdout)
        XCTAssertTrue(result.stdout.contains("cannot find 'zzz'"), result.stdout)
    }
}
