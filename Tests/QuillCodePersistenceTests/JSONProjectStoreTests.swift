import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class JSONProjectStoreTests: PersistenceTestCase {
    func testProjectStoreRoundTripsSortedByLastOpened() throws {
        let store = try makeProjectStore()
        let older = ProjectRef(
            name: "Older",
            path: "/tmp/older",
            lastOpenedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ProjectRef(
            name: "Newer",
            path: "/tmp/newer",
            lastOpenedAt: Date(timeIntervalSince1970: 2)
        )

        try store.save([older, newer])

        XCTAssertEqual(try store.load().map(\.name), ["Newer", "Older"])
    }

    func testProjectStoreRoundTripsSSHProjectConnection() throws {
        let store = try makeProjectStore()
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)

        try store.save([project])
        let loaded = try XCTUnwrap(store.load().first)

        XCTAssertEqual(loaded.connection, connection)
        XCTAssertEqual(loaded.displayPath, "ssh://quill@feather.local:2222/srv/quill")
        XCTAssertTrue(loaded.isRemote)
    }

    func testProjectStoreRoundTripsInstructionDiagnosticResolutions() throws {
        let store = try makeProjectStore()
        let resolutionDate = Date(timeIntervalSince1970: 1_775_000_000)
        let fixedDate = Date(timeIntervalSince1970: 1_775_000_060)
        var project = ProjectRef(name: "QuillCode", path: "/tmp/quillcode")
        XCTAssertTrue(project.dismissInstructionDiagnostic(id: "instruction-semantic-conflict-tests", at: resolutionDate))
        XCTAssertTrue(project.resolveInstructionDiagnostic(id: "instruction-nested-override-sources", at: fixedDate))

        try store.save([project])
        let loaded = try XCTUnwrap(store.load().first)

        XCTAssertEqual(loaded.instructionDiagnosticResolutions.count, 2)
        XCTAssertEqual(loaded.dismissedInstructionDiagnosticIDs, ["instruction-semantic-conflict-tests"])
        XCTAssertEqual(loaded.resolvedInstructionDiagnosticIDs, ["instruction-nested-override-sources"])
        try assertDiagnostic(
            in: loaded,
            disposition: .dismissed,
            id: "instruction-semantic-conflict-tests",
            updatedAt: resolutionDate
        )
        try assertDiagnostic(
            in: loaded,
            disposition: .resolved,
            id: "instruction-nested-override-sources",
            updatedAt: fixedDate
        )
    }

    func testProjectStoreDecodesLegacyProjectAsLocalConnection() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("projects.json")
        try """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "path": "/tmp/legacy",
            "instructions": [],
            "localActions": [],
            "extensionManifests": [],
            "memories": [],
            "lastOpenedAt": "1970-01-01T00:00:01Z"
          }
        ]
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(JSONProjectStore(fileURL: fileURL).load().first)

        XCTAssertEqual(loaded.connection, .local(path: "/tmp/legacy"))
        XCTAssertFalse(loaded.isRemote)
        XCTAssertEqual(loaded.displayPath, "/tmp/legacy")
    }
}

private extension JSONProjectStoreTests {
    func makeProjectStore() throws -> JSONProjectStore {
        try JSONProjectStore(fileURL: makeTempDirectory().appendingPathComponent("projects.json"))
    }

    func assertDiagnostic(
        in project: ProjectRef,
        disposition: ProjectInstructionDiagnosticDisposition,
        id: String,
        updatedAt: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let resolution = try XCTUnwrap(
            project.instructionDiagnosticResolutions.first { $0.disposition == disposition },
            file: file,
            line: line
        )
        XCTAssertEqual(resolution.diagnosticID, id, file: file, line: line)
        XCTAssertEqual(resolution.updatedAt, updatedAt, file: file, line: line)
    }
}
