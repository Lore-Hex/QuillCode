import Foundation
import QuillCodeCore

/// Routes and executes the `host.lsp.*` navigation family against an `LSPCoordinator`. Returns
/// concise, model-readable `ToolResult`s. When no coordinator/server is available every method
/// returns a clear "not available" result rather than an error, so the tool degrades like the rest
/// of the LSP surface.
public struct LSPToolCallDispatcher: Sendable {
    private let workspaceRoot: URL
    private let coordinator: LSPCoordinator?
    private let pathResolver: FileWorkspacePathResolver

    public init(workspaceRoot: URL, coordinator: LSPCoordinator?) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.coordinator = coordinator
        self.pathResolver = FileWorkspacePathResolver(workspaceRoot: workspaceRoot)
    }

    public static let definitions: [ToolDefinition] = [
        .lspDefinition,
        .lspReferences,
        .lspHover,
        .lspDocumentSymbol,
        .lspWorkspaceSymbol
    ]

    public static func handles(_ toolName: String) -> Bool {
        definitions.contains { $0.name == toolName }
    }

    public func execute(name: String, arguments: ToolArguments) throws -> ToolResult {
        guard let coordinator else {
            return ToolResult(ok: false, error: "LSP navigation is not available in this workspace.")
        }
        switch name {
        case ToolDefinition.lspDefinition.name:
            return try location(name: name, arguments: arguments, coordinator: coordinator) { client, path, line, character in
                try client.definition(path: path, line: line, character: character)
            }
        case ToolDefinition.lspReferences.name:
            let includeDeclaration = arguments.bool("includeDeclaration") ?? true
            return try location(name: name, arguments: arguments, coordinator: coordinator) { client, path, line, character in
                try client.references(path: path, line: line, character: character, includeDeclaration: includeDeclaration)
            }
        case ToolDefinition.lspHover.name:
            return try hover(arguments: arguments, coordinator: coordinator)
        case ToolDefinition.lspDocumentSymbol.name:
            return try documentSymbol(arguments: arguments, coordinator: coordinator)
        case ToolDefinition.lspWorkspaceSymbol.name:
            return try workspaceSymbol(arguments: arguments, coordinator: coordinator)
        default:
            return ToolResult(ok: false, error: "Unknown tool: \(name)")
        }
    }

    // MARK: Handlers

    private func location(
        name: String,
        arguments: ToolArguments,
        coordinator: LSPCoordinator,
        query: (LSPClient, String, Int, Int) throws -> [LSPLocation]
    ) throws -> ToolResult {
        let (path, url) = try resolvedPath(arguments)
        let line = try oneBasedLine(arguments)
        let character = arguments.int("character") ?? 0
        guard let nav = coordinator.navigationClient(forPath: url.path) else {
            return unavailable(forPath: path)
        }
        do {
            let locations = try query(nav.client, url.path, line - 1, character)
            return ToolResult(ok: true, stdout: renderLocations(locations))
        } catch {
            return errorResult(error)
        }
    }

    private func hover(arguments: ToolArguments, coordinator: LSPCoordinator) throws -> ToolResult {
        let (path, url) = try resolvedPath(arguments)
        let line = try oneBasedLine(arguments)
        let character = arguments.int("character") ?? 0
        guard let nav = coordinator.navigationClient(forPath: url.path) else {
            return unavailable(forPath: path)
        }
        do {
            let text = try nav.client.hover(path: url.path, line: line - 1, character: character)
            return ToolResult(ok: true, stdout: text ?? "No hover information at this position.\n")
        } catch {
            return errorResult(error)
        }
    }

    private func documentSymbol(arguments: ToolArguments, coordinator: LSPCoordinator) throws -> ToolResult {
        let (path, url) = try resolvedPath(arguments)
        guard let nav = coordinator.navigationClient(forPath: url.path) else {
            return unavailable(forPath: path)
        }
        do {
            let symbols = try nav.client.documentSymbols(path: url.path)
            return ToolResult(ok: true, stdout: renderSymbols(symbols))
        } catch {
            return errorResult(error)
        }
    }

    private func workspaceSymbol(arguments: ToolArguments, coordinator: LSPCoordinator) throws -> ToolResult {
        let query = try arguments.requiredString("query")
        // Any supported file gives us a client; use a representative extension to route.
        guard let nav = coordinator.navigationClient(forPath: representativeWorkspaceFile()?.path ?? "") else {
            return ToolResult(ok: false, error: "LSP workspace symbol search is not available (no language server running).")
        }
        do {
            let symbols = try nav.client.workspaceSymbols(query: query)
            return ToolResult(ok: true, stdout: renderSymbols(symbols))
        } catch {
            return errorResult(error)
        }
    }

    // MARK: Rendering

    private func renderLocations(_ locations: [LSPLocation]) -> String {
        guard !locations.isEmpty else { return "No locations found.\n" }
        let lines = locations.prefix(50).map { location -> String in
            let path = displayPath(forURI: location.uri)
            let line = location.range.start.line + 1
            let column = location.range.start.character + 1
            return "\(path):\(line):\(column)"
        }
        var output = lines.joined(separator: "\n") + "\n"
        if locations.count > 50 {
            output += "(+\(locations.count - 50) more)\n"
        }
        return output
    }

    private func renderSymbols(_ symbols: [LSPSymbol]) -> String {
        guard !symbols.isEmpty else { return "No symbols found.\n" }
        let lines = symbols.prefix(100).map { symbol -> String in
            let path = displayPath(forURI: symbol.location.uri)
            let line = symbol.location.range.start.line + 1
            let container = symbol.containerName.map { "\($0)." } ?? ""
            return "\(symbol.kindLabel) \(container)\(symbol.name) — \(path):\(line)"
        }
        var output = lines.joined(separator: "\n") + "\n"
        if symbols.count > 100 {
            output += "(+\(symbols.count - 100) more)\n"
        }
        return output
    }

    // MARK: Helpers

    /// A workspace-relative path for a `file://` URI inside the workspace, else the absolute path
    /// (locations may point at SDK files outside the project).
    private func displayPath(forURI uri: String) -> String {
        guard let path = LSPURI.path(from: uri) else { return uri }
        return LSPDiagnosticsRelativePath.of(path, workspaceRoot: workspaceRoot)
    }

    private func resolvedPath(_ arguments: ToolArguments) throws -> (relative: String, url: URL) {
        let path = try arguments.requiredString("path")
        let url = try pathResolver.resolve(path) // enforces the workspace boundary
        return (path, url)
    }

    private func oneBasedLine(_ arguments: ToolArguments) throws -> Int {
        let line = try arguments.requiredInt("line")
        guard line >= 1 else {
            throw ToolArgumentError.missingInteger("line (must be 1-based)")
        }
        return line
    }

    private func unavailable(forPath path: String) -> ToolResult {
        ToolResult(ok: false, error: "No language server is available for \(path).")
    }

    private func errorResult(_ error: Error) -> ToolResult {
        ToolResult(ok: false, error: "LSP request failed: \(String(describing: error))")
    }

    /// A representative existing file for workspace-wide requests that are not tied to a path. Picks
    /// the first Swift file found so `workspace/symbol` routes to sourcekit-lsp.
    private func representativeWorkspaceFile() -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension.lowercased() == "swift" { return item }
        }
        return nil
    }
}
