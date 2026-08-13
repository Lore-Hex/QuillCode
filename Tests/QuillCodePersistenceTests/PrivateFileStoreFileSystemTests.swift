import XCTest
@testable import QuillCodePersistence

final class PrivateFileStoreFileSystemTests: XCTestCase {
    func testDirectoryReaderReadsEmptyAndMultiChunkFilesExactly() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private", isDirectory: true)
        let largeData = Data((0..<(130 * 1_024)).map { UInt8($0 % 251) })
        try PrivateFileStoreFileSystem.write(
            Data(),
            directory: directory,
            filename: "empty.json"
        )
        try PrivateFileStoreFileSystem.write(
            largeData,
            directory: directory,
            filename: "large.json"
        )
        let reader = try XCTUnwrap(
            PrivateFileStoreFileSystem.DirectoryReader(directory: directory)
        )

        XCTAssertEqual(
            try reader.read(filename: "empty.json", maximumBytes: 0),
            Data()
        )
        XCTAssertEqual(
            try reader.read(filename: "large.json", maximumBytes: largeData.count),
            largeData
        )
    }

    func testDirectoryReaderStaysBoundToValidatedDirectoryAfterPathReplacement() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private", isDirectory: true)
        try PrivateFileStoreFileSystem.write(
            Data("validated".utf8),
            directory: directory,
            filename: "state.json"
        )
        let reader = try XCTUnwrap(
            PrivateFileStoreFileSystem.DirectoryReader(directory: directory)
        )

        let originalDirectory = root.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: originalDirectory)
        try PrivateFileStoreFileSystem.write(
            Data("replacement".utf8),
            directory: directory,
            filename: "state.json"
        )

        let data = try XCTUnwrap(
            reader.read(filename: "state.json", maximumBytes: 64)
        )
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "validated")
    }

    func testDirectoryReaderKeepsPerEntrySymlinkAndSizeChecks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private", isDirectory: true)
        try PrivateFileStoreFileSystem.write(
            Data("12345".utf8),
            directory: directory,
            filename: "bounded.json"
        )
        let outside = root.appendingPathComponent("outside.json")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked.json"),
            withDestinationURL: outside
        )
        let reader = try XCTUnwrap(
            PrivateFileStoreFileSystem.DirectoryReader(directory: directory)
        )

        XCTAssertThrowsError(
            try reader.read(filename: "bounded.json", maximumBytes: 4)
        ) { error in
            XCTAssertEqual(
                error as? BoundedFileDataError,
                .exceedsSizeLimit(maximumBytes: 4)
            )
        }
        XCTAssertThrowsError(
            try reader.read(filename: "linked.json", maximumBytes: 64)
        ) { error in
            XCTAssertEqual(error as? BoundedFileDataError, .symbolicLink)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrivateFileStoreFileSystemTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
