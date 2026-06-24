import Foundation
import XCTest

extension XCTestCase {
    func makeQuillCodeTestDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
