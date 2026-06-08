#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/story-gauge-tests.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0

fail() {
  echo "FAIL: $*" >&2
  echo "--- stdout ---" >&2
  [ -f "${OUT:-}" ] && sed -n '1,120p' "$OUT" >&2
  echo "--- stderr ---" >&2
  [ -f "${ERR:-}" ] && sed -n '1,120p' "$ERR" >&2
  exit 1
}

run() {
  OUT="$TMP/out"
  ERR="$TMP/err"
  STATUS=0
  "$@" >"$OUT" 2>"$ERR" || STATUS=$?
}

assert_status() {
  local expected=$1
  [ "$STATUS" -eq "$expected" ] || fail "expected status $expected, got $STATUS"
  PASS=$((PASS+1))
}

assert_grep() {
  local pattern=$1 file=$2
  grep -qE "$pattern" "$file" || fail "missing pattern: $pattern"
  PASS=$((PASS+1))
}

assert_not_exists() {
  local path=$1
  [ ! -e "$path" ] || fail "unexpected path exists: $path"
  PASS=$((PASS+1))
}

write_story() {
  local path=$1 level=$2 ac_count=$3 extra=${4:-}
  {
    printf '# Demo\n\n'
    printf '%s Acceptance Criteria\n' "$level"
    local i
    for ((i=1; i<=ac_count; i++)); do
      printf '%s. criterion %s\n' "$i" "$i"
    done
    if [ -n "$extra" ]; then
      printf '\n%s\n' "$extra"
    fi
  } > "$path"
}

write_story "$TMP/ready.md" "##" 2
run "$ROOT/scripts/score-story" "$TMP/ready.md" --quiet
assert_status 0

run "$ROOT/scripts/score-story" "$ROOT/README.md" --quiet
assert_status 2
assert_grep 'missing required section: ## Acceptance Criteria' "$ERR"

write_story "$TMP/split.md" "##" 7
run "$ROOT/scripts/score-story" "$TMP/split.md"
assert_status 1
assert_grep 'VERDICT: SPLIT[[:space:]]+\(1 gate tripped\)' "$OUT"

write_story "$TMP/h3.md" "###" 7
run "$ROOT/scripts/score-story" "$TMP/h3.md" --quiet
assert_status 2

printf 'AC_LEVEL=3\n' > "$TMP/h3.conf"
run "$ROOT/scripts/score-story" "$TMP/h3.md" --config "$TMP/h3.conf"
assert_status 1
assert_grep '1 ACs[[:space:]]+7[[:space:]]+FAIL' "$OUT"

run "$ROOT/scripts/score-story" "$TMP/ready.md" --config
assert_status 2
assert_grep 'usage: score-story' "$ERR"

# shellcheck disable=SC2016
printf 'MAX_ACS=$(touch %s)\n' "$TMP/pwned" > "$TMP/malicious.conf"
run "$ROOT/scripts/score-story" "$TMP/ready.md" --config "$TMP/malicious.conf"
assert_status 2
assert_not_exists "$TMP/pwned"

write_story "$TMP/retry.md" "##" 1 $'## Dev Notes\nretry loop one\nretry loop two'
run "$ROOT/scripts/score-story" "$TMP/retry.md"
assert_status 1
assert_grep 'state-machine hits~[[:space:]]+2[[:space:]]+FAIL' "$OUT"

mkdir "$TMP/backlog"
cp "$TMP/ready.md" "$TMP/backlog/ready.md"
cp "$TMP/split.md" "$TMP/backlog/split.md"
run "$ROOT/scripts/scan-backlog" "$TMP/backlog" --format json
assert_status 0
assert_grep '"totals":\{"ok":1,"split":1,"high":0\}' "$OUT"
assert_grep '"risk":"SPLIT"' "$OUT"

run "$ROOT/scripts/score-story" "$TMP/ready.md" --llm --format json
assert_status 0
assert_grep '"semantic_status":"unavailable"' "$OUT"
assert_grep '"verdict":"READY"' "$OUT"

stub_valid='{"semantic_gates":{"state_machine":{"status":"fail","confidence":0.8,"evidence":["criterion 1"],"reason":"stateful concern"},"risk_markers":{"status":"pass","confidence":0.6,"evidence":[],"reason":"no dense warnings"},"race_lifecycle":{"status":"unknown","confidence":0.4,"evidence":[],"reason":"ambiguous"}},"suggested_slices":["split stateful concern"]}'
run env STORY_GAUGE_LLM_PROVIDER=stub STORY_GAUGE_LLM_STUB_RESPONSE="$stub_valid" "$ROOT/scripts/score-story" "$TMP/ready.md" --llm --format json
assert_status 0
assert_grep '"semantic_status":"available"' "$OUT"
assert_grep '"semantic_verdict":"SPLIT"' "$OUT"
assert_grep '"semantic_gates_tripped":1' "$OUT"

run env STORY_GAUGE_LLM_PROVIDER=stub STORY_GAUGE_LLM_STUB_RESPONSE="$stub_valid" "$ROOT/scripts/score-story" "$TMP/ready.md" --llm --llm-fail-policy high-confidence --quiet
assert_status 1

run env STORY_GAUGE_LLM_PROVIDER=stub STORY_GAUGE_LLM_STUB_RESPONSE='not-json' "$ROOT/scripts/score-story" "$TMP/ready.md" --llm --format json
assert_status 0
assert_grep '"semantic_status":"unavailable"' "$OUT"
assert_grep 'invalid JSON' "$OUT"

stub_no_evidence='{"semantic_gates":{"state_machine":{"status":"fail","confidence":0.9,"evidence":["not copied from story"],"reason":"bad evidence"},"risk_markers":{"status":"pass","confidence":0.6,"evidence":[],"reason":"no dense warnings"},"race_lifecycle":{"status":"pass","confidence":0.6,"evidence":[],"reason":"no lifecycle prose"}}}'
run env STORY_GAUGE_LLM_PROVIDER=stub STORY_GAUGE_LLM_STUB_RESPONSE="$stub_no_evidence" "$ROOT/scripts/score-story" "$TMP/ready.md" --llm --format json
assert_status 0
assert_grep 'fail omitted exact story evidence' "$OUT"
assert_grep '"semantic_verdict":"UNKNOWN"' "$OUT"

cp "$TMP/retry.md" "$TMP/backlog/retry.md"
run env STORY_GAUGE_LLM_PROVIDER=stub STORY_GAUGE_LLM_STUB_RESPONSE="$stub_valid" "$ROOT/scripts/scan-backlog" "$TMP/backlog" --llm --format json
assert_status 0
assert_grep '"semantic_status":"available"' "$OUT"
assert_grep '"semantic_status":"skipped"' "$OUT"

echo "ok - $PASS assertions"
