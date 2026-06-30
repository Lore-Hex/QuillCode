import XCTest

final class ParityLiveSmokeScriptGateTests: QuillCodeParityTestCase {
    func testLiveTrustedRouterSmokeManifestRecordsSecretFreeRuntimeEvidence() throws {
        let script = try Self.liveTrustedRouterSmokeText()

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
        XCTAssertTrue(script.contains("shell-action-now"))
        XCTAssertTrue(script.contains("quillcode_live_now_smoke"))
        XCTAssertTrue(script.contains("shell-action-polite-bare"))
        XCTAssertTrue(script.contains("quillcode_live_polite_smoke"))
        XCTAssertTrue(script.contains("git-status-polite"))
        XCTAssertTrue(script.contains("git-branch-list"))
        XCTAssertTrue(script.contains("List git branches in this repo."))
        XCTAssertTrue(script.contains("quillcode-smoke-branch"))
        XCTAssertTrue(script.contains("host.git.branch.list"))
        XCTAssertTrue(script.contains("workspace-list-natural"))
        XCTAssertTrue(script.contains("workspace-pwd-natural"))
        XCTAssertTrue(script.contains("workspace-read-natural"))
        XCTAssertTrue(script.contains("What is in live-smoke.txt?"))
        XCTAssertTrue(script.contains("negative-shell-action"))
        XCTAssertTrue(script.contains("negative-file-write"))
        XCTAssertTrue(script.contains("negative-download"))
        XCTAssertTrue(script.contains("quillcode_live_forbidden_shell"))
        XCTAssertTrue(script.contains("forbidden-live.txt"))
        XCTAssertTrue(script.contains("downloads/forbidden-live.html"))
        XCTAssertTrue(script.contains("validate_no_workspace_file"))
        XCTAssertTrue(script.contains("assert_workspace_file_absent"))
        XCTAssertTrue(script.contains("PASSIVE_ACTION_PATTERN="))
        XCTAssertTrue(script.contains("I will"))
        XCTAssertTrue(script.contains("execute|inspect|list|show|review|read|fetch|save"))
        XCTAssertTrue(script.contains("--arg passiveActionPattern \"$PASSIVE_ACTION_PATTERN\""))
        XCTAssertTrue(script.contains("test($passiveActionPattern; \"i\")"))
        XCTAssertTrue(script.contains("assert_saved_transcripts_match_live_smoke_expectations 18 3"))
        XCTAssertTrue(script.contains("negative_transcript_ok"))
        XCTAssertTrue(script.contains("(queued_calls | length) == 0"))
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

    func testRealWorldSmokeRequiresDeterministicPlaywrightEvidenceWhenPlaywrightIsRequired() throws {
        let script = try Self.scriptText(named: "real-world-smoke.sh")

        XCTAssertTrue(script.contains("assert_deterministic_real_world_evidence"))
        XCTAssertTrue(script.contains("validate-playwright-real-world-manifest.py"))
        XCTAssertTrue(script.contains("playwright-real-world-actions-manifest.json"))
        XCTAssertTrue(script.contains("deterministic-smoke-manifest.json"))
        XCTAssertTrue(script.contains("\"realWorldActions\""))
        XCTAssertTrue(script.contains("DETERMINISTIC_STATUS=\"validating-real-world-evidence\""))
        XCTAssertTrue(script.contains("deterministic real-world evidence validation failed"))
        XCTAssertTrue(script.contains("steps should be an object"))
        XCTAssertTrue(script.contains("steps.playwright should be an object"))
        XCTAssertTrue(script.contains("steps.playwright.realWorldActions should be an object"))
        XCTAssertTrue(script.contains("scenarioCount should be at least 12"))
        XCTAssertTrue(script.contains("promptCount should be at least 22"))
        XCTAssertTrue(script.contains("regressionGuardCount should be at least 36"))
    }

    func testDeterministicSmokeCoversExplicitNegativeActionIntent() throws {
        let script = try Self.scriptText(named: "smoke.sh")

        XCTAssertTrue(script.contains("CLI_NEGATIVE_ACTION_STATUS=\"not-run\""))
        XCTAssertTrue(script.contains("\"cliNegativeActions\""))
        XCTAssertTrue(script.contains("Do not run whoami."))
        XCTAssertTrue(script.contains("Do not write"))
        XCTAssertTrue(script.contains("forbidden.txt"))
        XCTAssertTrue(script.contains("Don't download https://example.com"))
        XCTAssertTrue(script.contains("downloads/forbidden.html"))
        XCTAssertTrue(script.contains("PASSIVE_ACTION_PATTERN="))
        XCTAssertTrue(script.contains("I will"))
        XCTAssertTrue(script.contains("execute|inspect|list|show|review|read|fetch|save"))
        XCTAssertTrue(script.contains("grep -Eqi \"$PASSIVE_ACTION_PATTERN\""))
        XCTAssertTrue(script.contains("forbidden.txt despite explicit negative intent"))
        XCTAssertTrue(script.contains("forbidden.html despite explicit negative intent"))
    }

    func testDeterministicSmokeCoversNaturalGitReadPrompts() throws {
        let script = try Self.scriptText(named: "smoke.sh")

        XCTAssertTrue(script.contains("CLI_GIT_READ_STATUS=\"not-run\""))
        XCTAssertTrue(script.contains("\"cliGitRead\""))
        XCTAssertTrue(script.contains("prepare_git_workspace()"))
        XCTAssertTrue(script.contains("tracked.txt"))
        XCTAssertTrue(script.contains("Please check git status."))
        XCTAssertTrue(script.contains("what changed?"))
        XCTAssertTrue(script.contains("Git status:"))
        XCTAssertTrue(script.contains("Git diff:"))
        XCTAssertTrue(script.contains("+after"))
    }

    func testDeterministicSmokeCoversNaturalFileReadPrompts() throws {
        let script = try Self.scriptText(named: "smoke.sh")

        XCTAssertTrue(script.contains("CLI_FILE_READ_STATUS=\"not-run\""))
        XCTAssertTrue(script.contains("\"cliFileRead\""))
        XCTAssertTrue(script.contains("QuillCode smoke README"))
        XCTAssertTrue(script.contains("What is in README.md?"))
        XCTAssertTrue(script.contains("Contents of `README.md`"))
    }

    func testPlaywrightRealWorldManifestValidatorGuardsReleaseEvidence() throws {
        let script = try Self.scriptText(named: "smoke.sh")
        let validator = try Self.scriptText(named: "validate-playwright-real-world-manifest.py")

        XCTAssertTrue(script.contains("validate-playwright-real-world-manifest.py"))
        XCTAssertTrue(validator.contains("REQUIRED_SCENARIOS"))
        XCTAssertTrue(validator.contains("MIN_PROMPT_COUNT = 22"))
        XCTAssertTrue(validator.contains("MIN_REGRESSION_GUARD_COUNT = 36"))
        XCTAssertTrue(validator.contains("runs natural shell requests immediately with nonempty arguments"))
        XCTAssertTrue(validator.contains("lists workspace entries with the structured file list tool"))
        XCTAssertTrue(validator.contains("writes requested file content immediately without a confirmation loop"))
        XCTAssertTrue(validator.contains("reads requested file contents immediately with the structured file tool"))
        XCTAssertTrue(validator.contains("searches workspace text with the structured file search tool"))
        XCTAssertTrue(validator.contains("answers device diagnostic prompts with concrete shell actions"))
        XCTAssertTrue(validator.contains("downloads requested domains with a bounded concrete shell action"))
        XCTAssertTrue(validator.contains("answers natural git read requests with structured git tools"))
        XCTAssertTrue(validator.contains("dispatches slash git read shortcuts as real workspace actions"))
        XCTAssertTrue(validator.contains("starter cards launch real workspace actions immediately"))
        XCTAssertTrue(validator.contains("respects explicit negative action prompts without tool cards or side effects"))
        XCTAssertTrue(validator.contains("recovers transient runtime failures with the same actionable turn"))
        XCTAssertTrue(validator.contains("Please check git status."))
        XCTAssertTrue(validator.contains("what changed?"))
        XCTAssertTrue(validator.contains("/git-status"))
        XCTAssertTrue(validator.contains("/diff"))
        XCTAssertTrue(validator.contains("What is in README.md?"))
        XCTAssertTrue(validator.contains("Can you list the files here?"))
        XCTAssertTrue(validator.contains("Where is AgentRunner defined?"))
        XCTAssertTrue(validator.contains("Review changes starter card"))
        XCTAssertTrue(validator.contains("trigger network failure"))
        XCTAssertTrue(validator.contains("Retry runtime issue"))
        XCTAssertTrue(validator.contains("shell arguments are never {}"))
        XCTAssertTrue(validator.contains("assistant does not answer with passive promises"))
        XCTAssertTrue(validator.contains("file list uses host.file.list instead of shell ls fallback"))
        XCTAssertTrue(validator.contains("file read uses host.file.read instead of shell cat fallback"))
        XCTAssertTrue(validator.contains("file search uses host.file.search instead of shell grep fallback"))
        XCTAssertTrue(validator.contains("safety review does not block clear user intent"))
        XCTAssertTrue(validator.contains("git status uses host.git.status instead of shell fallback"))
        XCTAssertTrue(validator.contains("slash git status dispatches host.git.status"))
        XCTAssertTrue(validator.contains("slash diff dispatches host.git.diff"))
        XCTAssertTrue(validator.contains("starter card creates a user turn without draft-only limbo"))
        XCTAssertTrue(validator.contains("runtime issue retry clears the transient failure"))
        XCTAssertTrue(validator.contains("retry dispatches a concrete nonempty shell action"))
    }

    func testRealWorldSmokeWorkflowRunsReleaseCandidateWrapperWithArtifacts() throws {
        let workflow = try Self.workflowText(named: "real-world-smoke.yml")

        XCTAssertTrue(workflow.contains("name: Real World Smoke"))
        XCTAssertTrue(workflow.contains("workflow_dispatch:"))
        XCTAssertTrue(workflow.contains("require_live:"))
        XCTAssertTrue(workflow.contains("default: true"))
        XCTAssertTrue(workflow.contains("schedule:"))
        XCTAssertTrue(workflow.contains("QUILLCODE_API_KEY: ${{ secrets.QUILLCODE_LIVE_API_KEY }}"))
        XCTAssertTrue(workflow.contains("QUILLCODE_LIVE_MODEL: ${{ inputs.model || 'deepseekv4flash' }}"))
        XCTAssertTrue(workflow.contains("QUILLCODE_REQUIRE_LIVE_SMOKE: ${{ inputs.require_live && '1' || '0' }}"))
        XCTAssertTrue(workflow.contains("QUILLCODE_REAL_WORLD_REQUIRE_PLAYWRIGHT: \"1\""))
        XCTAssertTrue(workflow.contains("QUILLCODE_REAL_WORLD_SMOKE_ARTIFACT_DIR:"))
        XCTAssertTrue(workflow.contains("npm ci"))
        XCTAssertTrue(workflow.contains("npx playwright install chromium"))
        XCTAssertTrue(workflow.contains("./scripts/real-world-smoke.sh"))
        XCTAssertTrue(workflow.contains("actions/upload-artifact@v4"))
        XCTAssertTrue(workflow.contains("retention-days: 30"))
        XCTAssertFalse(
            workflow.contains("live-tr-smoke.sh"),
            "Release-candidate workflow should run the real-world wrapper, not bypass deterministic smoke."
        )
    }
}
