import XCTest

extension QuillCodeParityTestCase {
    func makeTemporarySwiftFile(_ source: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-click-target-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("Fixture.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
