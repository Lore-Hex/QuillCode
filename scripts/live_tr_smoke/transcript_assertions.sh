# Transcript integrity assertions for the live TrustedRouter smoke.

assert_saved_transcripts_match_live_smoke_expectations() {
  local minimum_actionable_thread_count="${1:-3}"
  local minimum_negative_thread_count="${2:-0}"
  local threads_dir="$SMOKE_HOME/threads"

  if [[ ! -d "$threads_dir" ]]; then
    fail_smoke "live smoke did not persist any thread directory" "" ""
  fi

  local actionable_thread_count
  local negative_thread_count
  IFS=$'\t' read -r actionable_thread_count negative_thread_count < <(
    jq -s -r '
      def has_negative_action_prompt:
        [.messages[]?
          | select(.role == "user")
          | .content
          | select(test("(do not|don'\''t|dont|never).*(run|write|download)"; "i"))]
        | length > 0;
      [
        ([.[] | select(has_negative_action_prompt | not)] | length),
        ([.[] | select(has_negative_action_prompt)] | length)
      ]
      | @tsv
    ' "$threads_dir"/*.json
  )

  if [[ "$actionable_thread_count" -lt "$minimum_actionable_thread_count" ]]; then
    local message
    message="live smoke expected at least $minimum_actionable_thread_count actionable transcripts"
    fail_transcript_integrity \
      "$message, found $actionable_thread_count" \
      list
  fi

  if [[ "$negative_thread_count" -lt "$minimum_negative_thread_count" ]]; then
    local message
    message="live smoke expected at least $minimum_negative_thread_count negative-intent transcripts"
    fail_transcript_integrity \
      "$message, found $negative_thread_count" \
      list
  fi

  jq -s -e --arg passiveActionPattern "$PASSIVE_ACTION_PATTERN" '
    def has_negative_action_prompt:
      [.messages[]?
        | select(.role == "user")
        | .content
        | select(test("(do not|don'\''t|dont|never).*(run|write|download)"; "i"))]
      | length > 0;
    def queued_calls:
      [.events[]? | select(.kind == "toolQueued") | .payloadJSON | fromjson];
    def queued_arguments:
      [queued_calls[] | .argumentsJSON | fromjson];
    def bad_empty_argument_calls:
      [queued_calls[]
        | select(.name != "host.git.status" and .name != "host.git.diff")
        | select((.argumentsJSON | fromjson | length) == 0)];
    def completed_results:
      [.events[]? | select(.kind == "toolCompleted") | .payloadJSON | fromjson];
    def bad_assistant_promises:
      [.messages[]?
        | select(.role == "assistant")
        | .content
        | select(test($passiveActionPattern; "i"))];
    def actionable_transcript_ok:
      (
        (.messages | length) >= 2
        and (bad_assistant_promises | length) == 0
        and (queued_calls | length) >= 1
        and (queued_arguments | length) == (queued_calls | length)
        and all(queued_calls[]; (.name | type == "string") and (.name | length) > 0)
        and all(queued_calls[]; (.argumentsJSON | type == "string") and (.argumentsJSON | length) >= 2)
        and all(queued_arguments[]; type == "object")
        and (bad_empty_argument_calls | length) == 0
        and ([.events[]? | select(.kind == "toolFailed")] | length) == 0
        and (completed_results | length) >= 1
        and all(completed_results[]; .ok == true)
      );
    def negative_transcript_ok:
      (
        (.messages | length) >= 2
        and (queued_calls | length) == 0
        and ([.events[]? | select(.kind == "toolFailed")] | length) == 0
        and (completed_results | length) == 0
      );

    all(.[]; if has_negative_action_prompt then negative_transcript_ok else actionable_transcript_ok end)
  ' "$threads_dir"/*.json >/dev/null || {
    fail_transcript_integrity "live smoke persisted transcript integrity check failed" json
  }
}

fail_transcript_integrity() {
  local message="$1"
  local diagnostic="${2:-}"
  local threads_dir="$SMOKE_HOME/threads"

  record_scenario "fail" "$message" "" ""
  echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
  echo "$message" >&2
  case "$diagnostic" in
    list)
      find "$threads_dir" -maxdepth 1 -type f -name '*.json' -print >&2
      ;;
    json)
      jq '. | {title, messages, events}' "$threads_dir"/*.json >&2 || true
      ;;
  esac
  print_report_summary >&2
  exit 1
}
