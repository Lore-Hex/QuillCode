# Assertion helpers for live TrustedRouter smoke scenarios.

assert_useful_output() {
  local output_file="$1"
  local stderr_file="$2"
  local expected="$3"

  assert_no_action_regression "$output_file" "$stderr_file"
  if ! grep -Fq "$expected" "$output_file"; then
    fail_smoke "live smoke output did not contain expected text: $expected" "$output_file" "$stderr_file"
  fi
}

assert_no_action_regression() {
  local output_file="$1"
  local stderr_file="$2"

  assert_nonempty_output "$output_file" "$stderr_file"
  if grep -qi "No shell command was specified" "$output_file"; then
    fail_smoke "live smoke regressed into an empty shell command" "$output_file" "$stderr_file"
  fi
  if grep -Eiq "$PASSIVE_ACTION_PATTERN" "$output_file"; then
    fail_smoke "live smoke returned a passive promise instead of executing" "$output_file" "$stderr_file"
  fi
}

assert_nonempty_output() {
  local output_file="$1"
  local stderr_file="$2"

  if [[ ! -s "$output_file" ]]; then
    fail_smoke "live smoke returned no stdout" "$output_file" "$stderr_file"
  fi
}

workspace_file_path() {
  printf '%s/%s\n' "$SMOKE_WORKSPACE" "$1"
}

assert_workspace_file_contains_exactly() {
  local relative_path="$1"
  local expected_content="$2"
  local file_path

  file_path="$(workspace_file_path "$relative_path")"

  if [[ ! -f "$file_path" ]]; then
    fail_workspace_assertion "live smoke did not create expected workspace file: $relative_path" 2
  fi

  local actual_content
  actual_content="$(tr -d '\r' < "$file_path")"
  actual_content="${actual_content%$'\n'}"
  if [[ "$actual_content" != "$expected_content" ]]; then
    fail_workspace_content_mismatch "$relative_path" "$expected_content" "$actual_content"
  fi
}

fail_workspace_content_mismatch() {
  local relative_path="$1"
  local expected_content="$2"
  local actual_content="$3"
  local message="live smoke file content mismatch for $relative_path"

  record_scenario "fail" "$message" "$CURRENT_STDOUT" "$CURRENT_STDERR"
  echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
  echo "$message" >&2
  printf 'expected: %s\nactual: %s\n' "$expected_content" "$actual_content" >&2
  print_report_summary >&2
  exit 1
}

assert_workspace_file_nonempty() {
  local relative_path="$1"
  local file_path

  file_path="$(workspace_file_path "$relative_path")"

  if [[ ! -s "$file_path" ]]; then
    fail_workspace_assertion "live smoke expected a non-empty workspace file: $relative_path" 3
  fi
}

assert_workspace_file_absent() {
  local relative_path="$1"
  local file_path

  file_path="$(workspace_file_path "$relative_path")"

  if [[ -e "$file_path" ]]; then
    fail_workspace_assertion \
      "live smoke created forbidden workspace file despite explicit negative intent: $relative_path" \
      3
  fi
}

assert_output_matches() {
  local output_file="$1"
  local stderr_file="$2"
  local pattern="$3"
  local description="$4"

  assert_no_action_regression "$output_file" "$stderr_file"
  if ! grep -Eiq "$pattern" "$output_file"; then
    fail_smoke "live smoke output did not match expected $description" "$output_file" "$stderr_file"
  fi
}

validate_expected_outputs() {
  local output_file="$1"
  local stderr_file="$2"
  shift 2

  local expected
  for expected in "$@"; do
    assert_useful_output "$output_file" "$stderr_file" "$expected"
  done
}

validate_exact_workspace_file() {
  assert_no_action_regression "$1" "$2"
  assert_workspace_file_contains_exactly "$3" "$4"
}

validate_nonempty_workspace_file() {
  assert_output_matches "$1" "$2" "$3" "$4"
  assert_workspace_file_nonempty "$5"
}

validate_no_workspace_file() {
  local output_file="$1"
  local stderr_file="$2"
  local relative_path="$3"
  local forbidden="$4"

  assert_nonempty_output "$output_file" "$stderr_file"
  if grep -Fq "$forbidden" "$output_file"; then
    fail_smoke \
      "live smoke output contained forbidden text despite explicit negative intent: $forbidden" \
      "$output_file" \
      "$stderr_file"
  fi
  assert_workspace_file_absent "$relative_path"
}

validate_nonempty_noop_output() {
  local output_file="$1"
  local stderr_file="$2"

  assert_nonempty_output "$output_file" "$stderr_file"
}
