import XCTest
@testable import QuillCodePersistence

final class ConfigDocumentTests: PersistenceTestCase {
    func testDocumentRoundTripsNestedJSONCompatibleTOML() throws {
        let file = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        model = "trustedrouter/fast"

        [desktop.workspace]
        collapsed = true
        width = 320
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = ConfigDocumentStore(fileURL: file)
        var document = try store.load()
        XCTAssertEqual(
            document.value(at: try ConfigKeyPath("desktop.workspace.width")),
            .integer(320)
        )

        document.apply(ConfigDocumentEdit(
            keyPath: try ConfigKeyPath("desktop.workspace.width"),
            value: .integer(360),
            mergeStrategy: .replace
        ))
        try store.save(document)

        XCTAssertEqual(
            try store.load().value(at: ConfigKeyPath("desktop.workspace.width")),
            .integer(360)
        )
    }

    func testQuotedKeyPathSegmentsMatchCodexSemantics() throws {
        let path = try ConfigKeyPath(#"plugins."sample.catalog".enabled"#)
        XCTAssertEqual(path.segments, ["plugins", "sample.catalog", "enabled"])
        XCTAssertThrowsError(try ConfigKeyPath("plugins..enabled"))
        XCTAssertThrowsError(try ConfigKeyPath(#"plugins."unterminated"#))
    }

    func testReplaceBuildsParentsAndReplacesScalarParent() throws {
        var document = ConfigDocument(values: ["desktop": .string("legacy")])

        XCTAssertTrue(document.apply(ConfigDocumentEdit(
            keyPath: try ConfigKeyPath("desktop.workspace.width"),
            value: .integer(320),
            mergeStrategy: .replace
        )))

        XCTAssertEqual(
            document.value(at: try ConfigKeyPath("desktop.workspace.width")),
            .integer(320)
        )
    }

    func testUpsertRecursivelyMergesTablesAndReplacesArrays() throws {
        var document = ConfigDocument(values: [
            "desktop": .object([
                "workspace": .object([
                    "collapsed": .bool(false),
                    "width": .integer(280),
                    "tabs": .array([.string("one")])
                ])
            ])
        ])

        document.apply(ConfigDocumentEdit(
            keyPath: try ConfigKeyPath("desktop.workspace"),
            value: .object([
                "collapsed": .bool(true),
                "tabs": .array([.string("two")])
            ]),
            mergeStrategy: .upsert
        ))

        XCTAssertEqual(
            document.value(at: try ConfigKeyPath("desktop.workspace")),
            .object([
                "collapsed": .bool(true),
                "width": .integer(280),
                "tabs": .array([.string("two")])
            ])
        )
    }

    func testDeleteMissingPathDoesNotCreateParents() throws {
        var document = ConfigDocument()
        XCTAssertFalse(document.apply(ConfigDocumentEdit(
            keyPath: try ConfigKeyPath("missing.child"),
            value: nil,
            mergeStrategy: .replace
        )))
        XCTAssertEqual(document, ConfigDocument())
    }

    func testLegacyRepeatedListKeysMigrateToValidArrays() throws {
        let file = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        favorite_model = "z-ai/glm-5.2"
        favorite_model = "moonshotai/kimi-k2.6"
        """.write(to: file, atomically: true, encoding: .utf8)

        let values = try ConfigDocumentStore(fileURL: file).load().values

        XCTAssertEqual(values["favorite_model"], .array([
            .string("z-ai/glm-5.2"),
            .string("moonshotai/kimi-k2.6")
        ]))
    }

    func testAllTOMLTemporalTypesSurviveStructuredRoundTrip() throws {
        let file = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        release_at = 1979-05-27T07:32:00-08:00
        local_build_at = 1979-05-27T07:32:00.123
        release_day = 1979-05-27
        maintenance_time = 07:32:00.123
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = ConfigDocumentStore(fileURL: file)
        let original = try store.load()

        XCTAssertEqual(
            original.values["release_at"]?.temporalStringValue,
            "1979-05-27T15:32:00.000Z"
        )
        XCTAssertEqual(
            original.values["local_build_at"]?.temporalStringValue,
            "1979-05-27T07:32:00.123"
        )
        XCTAssertEqual(original.values["release_day"]?.temporalStringValue, "1979-05-27")
        XCTAssertEqual(original.values["maintenance_time"]?.temporalStringValue, "07:32:00.123")

        try store.save(original)

        XCTAssertEqual(try store.load(), original)
        let encoded = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(encoded.contains("local_build_at = 1979-05-27T07:32:00.123"))
        XCTAssertTrue(encoded.contains("release_day = 1979-05-27"))
        XCTAssertTrue(encoded.contains("maintenance_time = 07:32:00.123"))
    }

    func testSpecialFloatsSurviveRoundTripAndNaNHasStableDocumentEquality() throws {
        let file = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        positive = inf
        negative = -inf
        undefined = nan
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = ConfigDocumentStore(fileURL: file)
        let original = try store.load()

        XCTAssertEqual(original.values["positive"]?.nonFiniteNumberStringValue, "inf")
        XCTAssertEqual(original.values["negative"]?.nonFiniteNumberStringValue, "-inf")
        XCTAssertEqual(original.values["undefined"]?.nonFiniteNumberStringValue, "nan")
        XCTAssertEqual(original, original)

        try store.save(original)

        XCTAssertEqual(try store.load(), original)
        let encoded = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(encoded.contains("positive = inf"))
        XCTAssertTrue(encoded.contains("negative = -inf"))
        XCTAssertTrue(encoded.contains("undefined = nan"))
    }
}
