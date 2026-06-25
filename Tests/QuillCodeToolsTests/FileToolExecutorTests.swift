import XCTest
@testable import QuillCodeTools

final class FileToolExecutorTests: XCTestCase {
    func testFileWriteStaysInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)

        let result = files.write(path: "nested/hello.txt", content: "hello world\n")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(files.read(path: "nested/hello.txt").stdout, "hello world\n")
        XCTAssertFalse(files.write(path: "../escape.txt", content: "no").ok)
    }
}
