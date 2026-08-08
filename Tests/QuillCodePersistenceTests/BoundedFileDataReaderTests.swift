import XCTest
@testable import QuillCodePersistence

final class BoundedFileDataReaderTests: PersistenceTestCase {
    func testMissingFileReturnsNil() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("missing.json")

        XCTAssertNil(
            try BoundedFileDataReader.readIfPresent(from: fileURL, maximumBytes: 4_096)
        )
    }

    func testReadsRegularFileWithinLimit() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("state.json")
        let expected = Data("healthy".utf8)
        try expected.write(to: fileURL)

        XCTAssertEqual(
            try BoundedFileDataReader.read(from: fileURL, maximumBytes: expected.count),
            expected
        )
    }

    func testRejectsOversizedSparseFileBeforeLoadingIt() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("state.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: 4_097)
        try handle.close()

        XCTAssertThrowsError(
            try BoundedFileDataReader.read(from: fileURL, maximumBytes: 4_096)
        ) { error in
            XCTAssertEqual(
                error as? BoundedFileDataError,
                .exceedsSizeLimit(maximumBytes: 4_096)
            )
        }
    }

    func testRejectsSymbolicLink() throws {
        let directory = try makeTempDirectory()
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("state.json")
        try Data("healthy".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(
            try BoundedFileDataReader.read(from: link, maximumBytes: 4_096)
        ) { error in
            XCTAssertEqual(error as? BoundedFileDataError, .symbolicLink)
        }
    }

    func testRejectsDanglingSymbolicLinkInsteadOfTreatingItAsMissing() throws {
        let directory = try makeTempDirectory()
        let target = directory.appendingPathComponent("missing-target.json")
        let link = directory.appendingPathComponent("state.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(
            try BoundedFileDataReader.readIfPresent(from: link, maximumBytes: 4_096)
        ) { error in
            XCTAssertEqual(error as? BoundedFileDataError, .symbolicLink)
        }
    }

    func testRejectsDirectory() throws {
        let directory = try makeTempDirectory()

        XCTAssertThrowsError(
            try BoundedFileDataReader.read(from: directory, maximumBytes: 4_096)
        ) { error in
            XCTAssertEqual(error as? BoundedFileDataError, .notRegularFile)
        }
    }
}
