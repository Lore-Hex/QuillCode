import XCTest

final class ParitySmokeScriptGateTests: QuillCodeParityTestCase {
    func testLiveTrustedRouterSmokeManifestRecordsSecretFreeRuntimeEvidence() throws {
        let script = try Self.scriptText(named: "live-tr-smoke.sh")

        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"missing\""))
        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"env:QUILLCODE_API_KEY\""))
        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"env:TRUSTEDROUTER_API_KEY\""))
        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"key-file\""))
        XCTAssertTrue(script.contains("elif [[ -s \"$KEY_FILE\" ]]"))
        XCTAssertTrue(script.contains("--arg rawModel \"$RAW_MODEL\""))
        XCTAssertTrue(script.contains("--arg keySource \"$API_KEY_SOURCE\""))
        XCTAssertTrue(script.contains("transport: \"TrustedRouter\""))
        XCTAssertTrue(script.contains("rawModel: $rawModel"))
        XCTAssertTrue(script.contains("normalizedModel: $model"))
        XCTAssertTrue(script.contains("keySource: $keySource"))
        XCTAssertTrue(script.contains("secretFree: true"))
        XCTAssertFalse(
            script.contains("--arg apiKey \"$API_KEY\""),
            "Live smoke manifests must not pass the raw API key into jq."
        )
    }

    func testRealWorldSmokeManifestCarriesLiveRuntimeConfiguration() throws {
        let script = try Self.scriptText(named: "real-world-smoke.sh")

        XCTAssertTrue(script.contains("LIVE_KEY_SOURCE=\"missing\""))
        XCTAssertTrue(script.contains("LIVE_MODEL=\"${QUILLCODE_LIVE_MODEL:-deepseekv4flash}\""))
        XCTAssertTrue(script.contains("LIVE_BASE_URL=\"${QUILLCODE_LIVE_BASE_URL:-https://api.trustedrouter.com/v1}\""))
        XCTAssertTrue(script.contains("live_key_source()"))
        XCTAssertTrue(script.contains("printf 'env:QUILLCODE_API_KEY'"))
        XCTAssertTrue(script.contains("printf 'env:TRUSTEDROUTER_API_KEY'"))
        XCTAssertTrue(script.contains("printf 'key-file'"))
        XCTAssertTrue(script.contains("\"configured\": {"))
        XCTAssertTrue(script.contains("\"transport\": \"TrustedRouter\""))
        XCTAssertTrue(script.contains("\"rawModel\": live_model"))
        XCTAssertTrue(script.contains("\"baseURL\": live_base_url"))
        XCTAssertTrue(script.contains("\"keySource\": live_key_source"))
        XCTAssertTrue(script.contains("\"secretFree\": True"))
        XCTAssertTrue(script.contains("LIVE_KEY_SOURCE=\"$(live_key_source)\""))
        XCTAssertFalse(
            script.contains("QUILLCODE_API_KEY\"") && script.contains("\"apiKey\""),
            "The real-world wrapper should record key source metadata, never raw key material."
        )
    }

    private static func scriptText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }
}
