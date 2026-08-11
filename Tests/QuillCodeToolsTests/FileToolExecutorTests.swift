import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class FileToolExecutorTests: XCTestCase {
    func testFileReadExtractsTextFromASCIIPDFInsteadOfDumpingObjectStreams() throws {
        let root = try makeTempDirectory()
        let pdfURL = root.appendingPathComponent("renewal.pdf")
        let data = makeASCIIPDF(text: "Renewal date 2027-12-31")
        XCTAssertFalse(FileReadRenderer.isProbablyBinary(data))
        try data.write(to: pdfURL)

        let result = FileToolExecutor(workspaceRoot: root).read(path: "renewal.pdf")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("Renewal date 2027-12-31"), result.stdout)
        XCTAssertTrue(result.stdout.contains("## Page 1"), result.stdout)
        XCTAssertFalse(result.stdout.contains("%PDF-1.4"), result.stdout)
        XCTAssertFalse(result.stdout.contains("endobj"), result.stdout)
    }

    func testFileReadExtractsWordAndPowerPointText() throws {
        let root = try makeTempDirectory()
        let wordURL = root.appendingPathComponent("brief.docx")
        let slidesURL = root.appendingPathComponent("deck.pptx")
        try makeArchive(
            at: wordURL,
            entries: [
                "word/document.xml": """
                <w:document xmlns:w="word"><w:body><w:p><w:r><w:t>Board update</w:t></w:r></w:p><w:p><w:r><w:t>Runway is 18 months</w:t></w:r></w:p></w:body></w:document>
                """
            ]
        )
        try makeArchive(
            at: slidesURL,
            entries: [
                "ppt/slides/slide2.xml": """
                <p:sld xmlns:p="presentation" xmlns:a="drawing"><a:t>Second milestone</a:t></p:sld>
                """,
                "ppt/slides/slide10.xml": """
                <p:sld xmlns:p="presentation" xmlns:a="drawing"><a:t>Tenth milestone</a:t></p:sld>
                """
            ]
        )
        let files = FileToolExecutor(workspaceRoot: root)

        let word = files.read(path: "brief.docx")
        let slides = files.read(path: "deck.pptx")

        XCTAssertTrue(word.ok, word.error ?? "")
        XCTAssertTrue(word.stdout.contains("Board update"))
        XCTAssertTrue(word.stdout.contains("Runway is 18 months"))
        XCTAssertTrue(slides.ok, slides.error ?? "")
        XCTAssertTrue(slides.stdout.contains("Second milestone"))
        XCTAssertTrue(slides.stdout.contains("Tenth milestone"))
        XCTAssertLessThan(
            try XCTUnwrap(slides.stdout.range(of: "Second milestone")?.lowerBound),
            try XCTUnwrap(slides.stdout.range(of: "Tenth milestone")?.lowerBound)
        )
    }

    func testFileReadExtractsSpreadsheetSharedAndInlineStrings() throws {
        let root = try makeTempDirectory()
        let workbookURL = root.appendingPathComponent("metrics.xlsx")
        try makeArchive(
            at: workbookURL,
            entries: [
                "xl/workbook.xml": """
                <workbook xmlns="spreadsheet"><sheets><sheet name="Metrics &amp; Forecast" sheetId="1"/></sheets></workbook>
                """,
                "xl/sharedStrings.xml": """
                <sst xmlns="spreadsheet"><si><t>Company</t></si><si><t>LedgerLoop</t></si></sst>
                """,
                "xl/worksheets/sheet1.xml": """
                <worksheet xmlns="spreadsheet"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><t>ARR</t></is></c></row><row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>1250000</v></c><c r="C2"><f>SUM(B2:B2)</f></c></row></sheetData></worksheet>
                """
            ]
        )

        let result = FileToolExecutor(workspaceRoot: root).read(path: "metrics.xlsx")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("## Metrics & Forecast"))
        XCTAssertTrue(result.stdout.contains("A1=Company"))
        XCTAssertTrue(result.stdout.contains("B1=ARR"))
        XCTAssertTrue(result.stdout.contains("A2=LedgerLoop"))
        XCTAssertTrue(result.stdout.contains("B2=1250000"))
        XCTAssertTrue(result.stdout.contains("C2=[formula=SUM(B2:B2)]"))
    }

    func testFileReadManyReadsCollectionInOneBoundedResultWithArtifacts() throws {
        let root = try makeTempDirectory()
        try "Alpha renewal 2027-10-01\n".write(
            to: root.appendingPathComponent("alpha.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "Beta renewal 2027-11-02\n".write(
            to: root.appendingPathComponent("beta.txt"),
            atomically: true,
            encoding: .utf8
        )
        let files = FileToolExecutor(workspaceRoot: root)

        let result = files.readMany(
            paths: ["alpha.txt", "beta.txt"],
            perFileLimit: 20,
            maxOutputCharacters: 10_000
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("## File 1: alpha.txt"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Alpha renewal 2027-10-01"), result.stdout)
        XCTAssertTrue(result.stdout.contains("## File 2: beta.txt"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Beta renewal 2027-11-02"), result.stdout)
        XCTAssertEqual(Set(result.artifacts), Set([
            root.appendingPathComponent("alpha.txt").path,
            root.appendingPathComponent("beta.txt").path,
        ]))
        XCTAssertLessThanOrEqual(result.stdout.count, 10_000)
    }

    func testFileReadManyRejectsDuplicateAndOversizedCollections() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertFalse(files.readMany(paths: ["same.txt", "same.txt"]).ok)
        XCTAssertFalse(files.readMany(paths: (1...51).map { "file-\($0).txt" }).ok)
    }

    func testFileReadManySharesCharacterBudgetAcrossEverySource() throws {
        let root = try makeTempDirectory()
        try String(repeating: "alpha 123456789012345\n", count: 400).write(
            to: root.appendingPathComponent("alpha.txt"),
            atomically: true,
            encoding: .utf8
        )
        try String(repeating: "beta 123456789012345\n", count: 400).write(
            to: root.appendingPathComponent("beta.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = FileToolExecutor(workspaceRoot: root).readMany(
            paths: ["alpha.txt", "beta.txt"],
            maxOutputCharacters: 10_000
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertLessThanOrEqual(result.stdout.count, 10_000)
        XCTAssertTrue(result.stdout.contains("## File 1: alpha.txt"), result.stdout)
        XCTAssertTrue(result.stdout.contains("## File 2: beta.txt"), result.stdout)
        XCTAssertEqual(result.stdout.components(separatedBy: "[truncated for collection]").count - 1, 2)
        XCTAssertEqual(result.artifacts.count, 2)
    }

    func testToolRouterExposesAndRoutesFileReadMany() throws {
        let root = try makeTempDirectory()
        try "first\n".write(
            to: root.appendingPathComponent("first.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "second\n".write(
            to: root.appendingPathComponent("second.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.fileReadMany.name))
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.fileReadMany.name,
            argumentsJSON: ToolArguments.json(["paths": ["first.txt", "second.txt"]])
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("1\tfirst"), result.stdout)
        XCTAssertTrue(result.stdout.contains("1\tsecond"), result.stdout)
    }

    func testToolRouterExposesAndRoutesFileSearch() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct RouterNeedle {}\n").ok)

        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.fileList.name))
        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.fileSearch.name))
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.fileSearch.name,
            argumentsJSON: ToolArguments.json(["query": "RouterNeedle"])
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileSearchToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.matches.map(\.path), ["Sources/App.swift"])
    }

    func testFileWriteStaysInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)

        let result = files.write(path: "nested/hello.txt", content: "hello world\n")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(files.read(path: "nested/hello.txt").stdout, "1\thello world")
        XCTAssertFalse(files.write(path: "../escape.txt", content: "no").ok)
    }

    func testFileWriteRejectsRaggedCSVWithoutReplacingExistingFile() throws {
        let root = try makeTempDirectory()
        let target = root.appendingPathComponent("report.csv")
        let original = "id,summary,owner\n1,Renewal review,Priya\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        let files = FileToolExecutor(workspaceRoot: root)

        let result = files.write(
            path: "report.csv",
            content: "id,summary,owner\n1,Fees paid in prior 12 months,except indemnity,Priya\n"
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("row 2 has 4 columns; the header has 3") == true, result.error ?? "")
        XCTAssertTrue(result.error?.contains("Quote fields containing commas") == true, result.error ?? "")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
    }

    func testFileWriteAcceptsStandardCSVQuoting() throws {
        let root = try makeTempDirectory()
        let content = """
        id,summary,owner
        1,"Fees paid, except ""IP indemnity"".
        Confirmed from lease.",Priya

        """
        let files = FileToolExecutor(workspaceRoot: root)

        let result = files.write(path: "report.csv", content: content)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("report.csv"), encoding: .utf8),
            content
        )
    }

    func testUnrestrictedFileToolsUseAndReportExternalAbsolutePaths() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        let existing = outside.appendingPathComponent("outside.txt")
        try "external needle\n".write(to: existing, atomically: true, encoding: .utf8)
        let files = FileToolExecutor(workspaceRoot: root, accessScope: .unrestricted)

        let read = files.read(path: existing.path)
        XCTAssertTrue(read.ok, read.error ?? "")
        XCTAssertEqual(read.stdout, "1\texternal needle")
        XCTAssertEqual(read.artifacts, [existing.path])

        let created = outside.appendingPathComponent("created.txt")
        let write = files.write(path: created.path, content: "created outside\n")
        XCTAssertTrue(write.ok, write.error ?? "")
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "created outside\n")

        let list = files.list(path: outside.path)
        XCTAssertTrue(list.ok, list.error ?? "")
        let listOutput = try JSONHelpers.decode(FileListToolOutput.self, from: list.stdout)
        XCTAssertEqual(listOutput.path, outside.path)
        XCTAssertEqual(Set(listOutput.entries.map(\.path)), Set([existing.path, created.path]))
        XCTAssertEqual(Set(list.artifacts), Set([existing.path, created.path]))

        let search = files.search(query: "needle", path: outside.path)
        XCTAssertTrue(search.ok, search.error ?? "")
        let searchOutput = try JSONHelpers.decode(FileSearchToolOutput.self, from: search.stdout)
        XCTAssertEqual(searchOutput.matches.map(\.path), [existing.path])
        XCTAssertEqual(search.artifacts, [existing.path])
    }

    func testUnrestrictedDefinitionsTellModelAbsolutePathsAreAllowed() throws {
        let adapted = HostToolAccessScope.unrestricted.adapting(ToolRouter.definitions)
        let fileRead = try XCTUnwrap(adapted.first { $0.name == ToolDefinition.fileRead.name })
        let fileReadMany = try XCTUnwrap(adapted.first { $0.name == ToolDefinition.fileReadMany.name })
        let shellRun = try XCTUnwrap(adapted.first { $0.name == ToolDefinition.shellRun.name })
        let chartRender = try XCTUnwrap(adapted.first { $0.name == ToolDefinition.chartRender.name })

        XCTAssertTrue(fileRead.description.contains("host filesystem"))
        XCTAssertTrue(fileRead.parametersJSON.contains("absolute and escaping paths are allowed"))
        XCTAssertTrue(fileReadMany.description.contains("Host filesystem paths"))
        XCTAssertTrue(fileReadMany.parametersJSON.contains("absolute and escaping paths are allowed"))
        XCTAssertTrue(shellRun.description.contains("absolute or escaping cwd values are allowed"))
        XCTAssertTrue(shellRun.parametersJSON.contains("absolute and escaping paths are allowed"))
        XCTAssertTrue(chartRender.description.contains("host filesystem"))
        XCTAssertTrue(
            chartRender.parametersJSON.contains("absolute and escaping paths are allowed"),
            chartRender.parametersJSON
        )
    }

    func testFileReadDefinitionAdvertisesRichDocumentExtraction() {
        let description = ToolDefinition.fileRead.description

        for fileType in ["PDF", "DOCX", "PPTX", "XLSX", "XLS"] {
            XCTAssertTrue(description.contains(fileType), "Missing \(fileType) from file-read guidance")
        }
        XCTAssertTrue(description.contains("without installing converters"))
        XCTAssertTrue(description.contains("without") && description.contains("shell commands"))
    }

    func testToolRouterAllowsEmptyFileWriteContent() throws {
        let root = try makeTempDirectory()
        try "old content\n".write(
            to: root.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        // Overwriting an existing file requires the session to have read it first.
        XCTAssertTrue(ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "rules.md"])
        )).ok)
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "content": "",
                "path": "rules.md"
            ])
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("rules.md"), encoding: .utf8), "")
    }

    func testFileToolsRejectSymlinkEscapeOutsideWorkspace() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()  // a sibling dir, outside the workspace
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        // The agent could create such a symlink with `ln -s` via the shell, then try to read/write
        // through it — standardizedFileURL would not catch it, but the symlink-resolved check must.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertFalse(files.write(path: "escape/evil.txt", content: "pwned").ok, "write through a symlink escaping the workspace must be rejected")
        XCTAssertFalse(files.read(path: "escape/secret.txt").ok, "read through a symlink escaping the workspace must be rejected")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.appendingPathComponent("evil.txt").path),
            "the rejected write must not have created a file outside the workspace"
        )
    }

    func testFileToolsAllowSymlinkPointingInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let realDir = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        // A symlink that stays inside the workspace is legitimate and must keep working.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: realDir
        )
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertTrue(files.write(path: "link/ok.txt", content: "fine\n").ok)
        XCTAssertEqual(files.read(path: "real/ok.txt").stdout, "1\tfine")
    }

    func testFileToolsRejectMidPathAndNestedSymlinkEscapes() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let fm = FileManager.default

        // Mid-path symlink: the symlink is not the first component (`link/sub/...`).
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        // Nested chain: a -> b -> outside.
        try fm.createSymbolicLink(at: root.appendingPathComponent("b"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("a"), withDestinationURL: root.appendingPathComponent("b"))

        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertFalse(files.write(path: "link/sub/evil.txt", content: "x").ok, "mid-path symlink escape must be rejected")
        XCTAssertFalse(files.write(path: "a/evil.txt", content: "x").ok, "nested symlink-chain escape must be rejected")
        // The escapes wrote nothing outside.
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("sub/evil.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("evil.txt").path))
    }

    func testFileListAndSearchRejectSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let files = FileToolExecutor(workspaceRoot: root)

        // list and search go through the same resolve() gate, so the escape is rejected there too.
        XCTAssertFalse(files.list(path: "escape").ok, "listing a symlink dir escaping the workspace must be rejected")
        XCTAssertFalse(files.search(query: "secret", path: "escape").ok, "searching through a symlink escape must be rejected")
    }

    func testFileListReturnsBoundedWorkspaceRelativeEntries() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: "README.md", content: "# Smoke\n").ok)
        XCTAssertTrue(files.write(path: ".hidden", content: "secret-ish\n").ok)

        let result = files.list(maxEntries: 2)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileListToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.path, ".")
        XCTAssertFalse(output.includedHidden)
        XCTAssertEqual(output.totalEntries, 2)
        XCTAssertEqual(output.entries.map(\.path), ["Sources", "README.md"])
        XCTAssertEqual(output.entries.map(\.kind), ["directory", "file"])
        XCTAssertTrue(output.entries.first?.bytes == nil)
        XCTAssertEqual(output.entries.last?.bytes, 8)
        XCTAssertFalse(output.truncated)
        XCTAssertEqual(result.artifacts.count, 2)
    }

    func testFileListCanIncludeHiddenAndCapEntries() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: ".env.example", content: "API_KEY=\n").ok)
        XCTAssertTrue(files.write(path: "visible.txt", content: "hello\n").ok)

        let result = files.list(includeHidden: true, maxEntries: 1)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileListToolOutput.self, from: result.stdout)
        XCTAssertTrue(output.includedHidden)
        XCTAssertEqual(output.totalEntries, 2)
        XCTAssertEqual(output.entries.count, 1)
        XCTAssertTrue(output.truncated)
    }

    func testFileListRejectsFilesOutsideWorkspaceAndMissingDirectories() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "README.md", content: "# Smoke\n").ok)

        XCTAssertFalse(files.list(path: "README.md").ok)
        XCTAssertFalse(files.list(path: "../outside").ok)
        XCTAssertFalse(files.list(path: "Missing").ok)
    }

    func testFileSearchReturnsBoundedWorkspaceRelativeMatches() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "let target = \"needle\"\nlet other = 1\n").ok)
        XCTAssertTrue(files.write(path: "Tests/AppTests.swift", content: "XCTAssertEqual(target, \"needle\")\n").ok)
        XCTAssertTrue(files.write(path: "node_modules/ignored.js", content: "needle\n").ok)

        let result = files.search(query: "needle", maxResults: 10)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileSearchToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.query, "needle")
        XCTAssertEqual(output.path, ".")
        XCTAssertEqual(output.scannedFiles, 2)
        XCTAssertEqual(Set(output.matches.map(\.path)), ["Sources/App.swift", "Tests/AppTests.swift"])
        XCTAssertEqual(Set(output.matches.map(\.line)), [1])
        XCTAssertEqual(result.artifacts.count, 2)
    }

    func testFileSearchCanScopeToDirectoryAndCapResults() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/One.swift", content: "needle\nneedle again\n").ok)
        XCTAssertTrue(files.write(path: "Tests/Two.swift", content: "needle\n").ok)

        let result = files.search(query: "needle", path: "Sources", maxResults: 1)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileSearchToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.path, "Sources")
        XCTAssertEqual(output.matches.count, 1)
        XCTAssertEqual(output.matches.first?.path, "Sources/One.swift")
        XCTAssertTrue(output.truncated)
    }

    func testFileSearchRejectsOutsideWorkspaceAndMissingQuery() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertFalse(files.search(query: "needle", path: "../outside").ok)
        XCTAssertFalse(files.search(query: "   ").ok)
    }

    private func makeArchive(at archiveURL: URL, entries: [String: String]) throws {
        let source = try makeTempDirectory()
        for (path, contents) in entries {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archiveURL.path, "."]
        process.currentDirectoryURL = source
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func makeASCIIPDF(text: String) -> Data {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let stream = "BT /F1 12 Tf 72 720 Td (\(escaped)) Tj ET\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets = [Int]()
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}
