#!/usr/bin/env bash
# sizer.sh — shared library: config loading, markdown section extraction, scoring.
# Sourced by scripts/score-story and scripts/scan-backlog. Dependency-free (bash + awk/grep/sed).

SIZER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # scripts/
SIZER_ROOT="$(cd "$SIZER_LIB_DIR/.." && pwd)"                   # skill root (holds config/)

# Trim leading/trailing whitespace.
sizer_trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

# Strip comments that are not inside a simple quoted value.
sizer_strip_comment() {
  local line=$1 out='' c quote='' i
  for ((i=0; i<${#line}; i++)); do
    c=${line:i:1}
    if [ -n "$quote" ]; then
      out+="$c"
      [ "$c" = "$quote" ] && quote=''
    else
      if [ "$c" = "'" ] || [ "$c" = '"' ]; then
        quote="$c"; out+="$c"
      elif [ "$c" = "#" ]; then
        break
      else
        out+="$c"
      fi
    fi
  done
  printf '%s' "$out" | sizer_trim
}

sizer_config_key_allowed() {
  case "$1" in
    AC_HEADING|AC_LEVEL|DEVNOTES_HEADING|DEVNOTES_LEVEL|FILELIST_HEADING|FILELIST_LEVEL|\
    AC_ITEM_RE|FILE_PATH_RE|TEST_SIBLING_SED|SM_RE|MARKER_RE|RACE_RE|\
    MAX_ACS|MAX_FILES|MAX_SM|MAX_MARKERS|MAX_RACE|WARN_DEVNOTES_LINES|\
    LLM_PROVIDER|LLM_MODEL|LLM_TIMEOUT_SECONDS|LLM_CONFIDENCE_THRESHOLD|LLM_FAIL_POLICY|LLM_CONTEXT_MAX_CHARS) return 0 ;;
    *) return 1 ;;
  esac
}

sizer_apply_config_file() {
  local path=$1 lineno=0 raw line key val first last
  [ -f "$path" ] || { echo "config not found: $path" >&2; return 2; }
  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno+1))
    line=$(sizer_strip_comment "$raw")
    [ -z "$line" ] && continue
    [[ "$line" == *=* ]] || { echo "$path:$lineno: expected KEY=value" >&2; return 2; }
    key=$(printf '%s' "${line%%=*}" | sizer_trim)
    val=$(printf '%s' "${line#*=}" | sizer_trim)
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || { echo "$path:$lineno: invalid key: $key" >&2; return 2; }
    sizer_config_key_allowed "$key" || { echo "$path:$lineno: unsupported key: $key" >&2; return 2; }
    first=${val:0:1}; last=${val: -1}
    if { [ "$first" = "'" ] && [ "$last" = "'" ]; } || { [ "$first" = '"' ] && [ "$last" = '"' ]; }; then
      val=${val:1:${#val}-2}
    fi
    printf -v "$key" '%s' "$val"
  done < "$path"
}

sizer_validate_number() {
  local key=$1 val
  val=${!key:-}
  [[ "$val" =~ ^[0-9]+$ ]] || { echo "config $key must be a non-negative integer: $val" >&2; return 2; }
}

sizer_validate_decimal_0_1() {
  local key=$1 val
  val=${!key:-}
  [[ "$val" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] || { echo "config $key must be between 0 and 1: $val" >&2; return 2; }
}

sizer_validate_config() {
  local key
  for key in AC_LEVEL DEVNOTES_LEVEL FILELIST_LEVEL MAX_ACS MAX_FILES MAX_SM MAX_MARKERS MAX_RACE WARN_DEVNOTES_LINES LLM_TIMEOUT_SECONDS LLM_CONTEXT_MAX_CHARS; do
    sizer_validate_number "$key" || return 2
  done
  sizer_validate_decimal_0_1 LLM_CONFIDENCE_THRESHOLD || return 2
  case "$LLM_FAIL_POLICY" in advisory|high-confidence|strict) ;; *) echo "config LLM_FAIL_POLICY must be advisory, high-confidence, or strict: $LLM_FAIL_POLICY" >&2; return 2 ;; esac
}

# Load defaults, then optional override (--config / env / CWD .story-gauge.conf).
sizer_load_config() {
  sizer_apply_config_file "$SIZER_ROOT/config/default.conf" || return 2
  local override="${STORY_GAUGE_CONFIG:-}"
  if [ -z "$override" ] && [ -f "$PWD/.story-gauge.conf" ]; then
    override="$PWD/.story-gauge.conf"
  fi
  if [ -n "$override" ]; then
    sizer_apply_config_file "$override" || return 2
  fi
  [ -n "${STORY_GAUGE_LLM_PROVIDER:-}" ] && LLM_PROVIDER="$STORY_GAUGE_LLM_PROVIDER"
  [ -n "${STORY_GAUGE_LLM_MODEL:-}" ] && LLM_MODEL="$STORY_GAUGE_LLM_MODEL"
  [ -n "${STORY_GAUGE_LLM_TIMEOUT_SECONDS:-}" ] && LLM_TIMEOUT_SECONDS="$STORY_GAUGE_LLM_TIMEOUT_SECONDS"
  [ -n "${STORY_GAUGE_LLM_FAIL_POLICY:-}" ] && LLM_FAIL_POLICY="$STORY_GAUGE_LLM_FAIL_POLICY"
  sizer_validate_config
}

# Build a string of N '#' chars.
sizer_hashes() { local n=$1 s=''; while [ "$n" -gt 0 ]; do s="#$s"; n=$((n-1)); done; printf '%s' "$s"; }

# ERE matching any heading at level 1..N  (e.g. N=2 -> '^(#[[:space:]]+|##[[:space:]]+)').
sizer_break_re() {
  local lvl=$1 i re='^('
  for ((i=1; i<=lvl; i++)); do
    re+="$(sizer_hashes "$i")[[:space:]]+"
    [ "$i" -lt "$lvl" ] && re+='|'
  done
  re+=')'
  printf '%s' "$re"
}

# section FILE HEADING [LEVEL=2] -> body lines from the heading to the next
# heading at the same-or-shallower level (deeper subsections are kept).
sizer_section() {
  local f=$1 h=$2 lvl=${3:-2}
  local start brk
  start="^$(sizer_hashes "$lvl")[[:space:]]+${h}"
  brk="$(sizer_break_re "$lvl")"
  awk -v s="$start" -v b="$brk" '
    $0 ~ s { g=1; next }
    g && $0 ~ b { g=0 }
    g { print }
  ' "$f"
}

# Has a section heading at the configured exact heading level.
sizer_has_section() {
  local f=$1 h=$2 lvl=${3:-2} start
  start="^$(sizer_hashes "$lvl")[[:space:]]+${h}"
  awk -v s="$start" '$0 ~ s { found=1; exit } END { exit(found ? 0 : 1) }' "$f"
}

# Count distinct changed-file paths from stdin (collapsing test siblings).
sizer_count_files() {
  grep -oE "$FILE_PATH_RE" \
    | sed -E "$TEST_SIBLING_SED" \
    | sort -u | wc -l | tr -d ' ' || true
}

# Is FILE a story? (has the AC heading)
sizer_is_story() { sizer_has_section "$1" "$AC_HEADING" "$AC_LEVEL"; }

# score_file FILE -> sets globals: ACS FILES SM SM_TERMS MARK RACE DEVLINES TRIP
sizer_score_file() {
  local f=$1
  sizer_is_story "$f" || return 2
  ACS=$(sizer_section "$f" "$AC_HEADING" "$AC_LEVEL" | grep -cE "$AC_ITEM_RE" || true)

  local fl; fl=$(sizer_section "$f" "$FILELIST_HEADING" "$FILELIST_LEVEL")
  FILES=$(printf '%s\n' "$fl" | sizer_count_files)
  [ "${FILES:-0}" -eq 0 ] && FILES=$(sizer_count_files < "$f")

  local sm_matches
  sm_matches=$(grep -ioE "$SM_RE" "$f" || true)
  SM=$(printf '%s\n' "$sm_matches" | sed '/^$/d' | wc -l | tr -d ' ' || true)
  # shellcheck disable=SC2034 # consumed by sourced CLI scripts
  SM_TERMS=$(printf '%s\n' "$sm_matches" | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u || true)

  # markers + race prose scoped to Dev Notes + ACs (skips References boilerplate;
  # lifecycle invariants frequently live in ACs, so include them).
  local scope
  scope=$( { sizer_section "$f" "$DEVNOTES_HEADING" "$DEVNOTES_LEVEL"; sizer_section "$f" "$AC_HEADING" "$AC_LEVEL"; } )
  MARK=$(printf '%s\n' "$scope" | grep -oiE "$MARKER_RE" | wc -l | tr -d ' ' || true)
  RACE=$(printf '%s\n' "$scope" | grep -oiE "$RACE_RE" | wc -l | tr -d ' ' || true)

  # shellcheck disable=SC2034 # consumed by sourced CLI scripts
  DEVLINES=$(sizer_section "$f" "$DEVNOTES_HEADING" "$DEVNOTES_LEVEL" | wc -l | tr -d ' ' || true)

  TRIP=0
  [ "${ACS:-0}"  -gt "$MAX_ACS" ]     && TRIP=$((TRIP+1))
  [ "${FILES:-0}" -gt "$MAX_FILES" ]  && TRIP=$((TRIP+1))
  [ "${SM:-0}"   -gt "$MAX_SM" ]      && TRIP=$((TRIP+1))
  [ "${MARK:-0}" -gt "$MAX_MARKERS" ] && TRIP=$((TRIP+1))
  [ "${RACE:-0}" -gt "$MAX_RACE" ]    && TRIP=$((TRIP+1))
  return 0
}

sizer_json_string() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

sizer_json_array_lines() {
  local first=1 line
  printf '['
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    sizer_json_string "$line"
  done
  printf ']'
}

# Map trip count -> risk word.
sizer_risk() { case "$1" in 0) echo OK;; 1) echo SPLIT;; *) echo HIGH;; esac; }

sizer_verdict() {
  if [ "$1" -eq 0 ]; then
    echo READY
  else
    echo SPLIT
  fi
}

sizer_score_json_object() {
  local file=$1 name=${2:-} risk=${3:-} verdict
  verdict=$(sizer_verdict "$TRIP")
  printf '{'
  printf '"file":'; sizer_json_string "$file"; printf ','
  if [ -n "$name" ]; then
    printf '"name":'; sizer_json_string "$name"; printf ','
  fi
  printf '"acs":%s,' "$ACS"
  printf '"files":%s,' "$FILES"
  printf '"state_machine_hits":%s,' "$SM"
  printf '"state_machine_terms":'; printf '%s\n' "$SM_TERMS" | sizer_json_array_lines; printf ','
  printf '"markers":%s,' "$MARK"
  printf '"race":%s,' "$RACE"
  printf '"dev_notes_lines":%s,' "$DEVLINES"
  printf '"gates_tripped":%s,' "$TRIP"
  if [ -n "$risk" ]; then
    printf '"risk":'; sizer_json_string "$risk"; printf ','
  fi
  printf '"verdict":'; sizer_json_string "$verdict"
  printf '}'
}

sizer_json_merge_objects() {
  local left=$1 right=$2
  left=${left#\{}
  left=${left%\}}
  right=${right#\{}
  right=${right%\}}
  if [ -z "$left" ]; then
    printf '{%s}' "$right"
  elif [ -z "$right" ]; then
    printf '{%s}' "$left"
  else
    printf '{%s,%s}' "$left" "$right"
  fi
}

sizer_semantic_unavailable_json() {
  local reason=$1
  python3 - "$reason" <<'PY'
import json
import sys

reason = sys.argv[1]
gate = {"status": "unknown", "confidence": 0.0, "evidence": [], "reason": reason}
print(json.dumps({
    "semantic_status": "unavailable",
    "semantic_gates": {
        "state_machine": gate,
        "risk_markers": gate,
        "race_lifecycle": gate,
    },
    "semantic_verdict": "UNAVAILABLE",
    "semantic_gates_tripped": 0,
    "suggested_slices": [],
}, separators=(",", ":")))
PY
}

sizer_semantic_skipped_json() {
  local reason=${1:-"semantic review skipped for low deterministic gate 3-5 signal"}
  python3 - "$reason" <<'PY'
import json
import sys

reason = sys.argv[1]
gate = {"status": "unknown", "confidence": 0.0, "evidence": [], "reason": reason}
print(json.dumps({
    "semantic_status": "skipped",
    "semantic_gates": {
        "state_machine": gate,
        "risk_markers": gate,
        "race_lifecycle": gate,
    },
    "semantic_verdict": "SKIPPED",
    "semantic_gates_tripped": 0,
    "suggested_slices": [],
}, separators=(",", ":")))
PY
}

sizer_semantic_should_fail() {
  local json=$1 policy=$2 threshold=$3
  python3 - "$json" "$policy" "$threshold" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
policy = sys.argv[2]
threshold = float(sys.argv[3])
if policy == "advisory":
    sys.exit(1)
gates = data.get("semantic_gates") or {}
for gate in gates.values():
    if not isinstance(gate, dict) or gate.get("status") != "fail":
        continue
    conf = float(gate.get("confidence") or 0)
    if policy == "strict" or conf >= threshold:
        sys.exit(0)
sys.exit(1)
PY
}

sizer_print_semantic_table() {
  local json=$1 policy=$2
  python3 - "$json" "$policy" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
policy = sys.argv[2]
labels = {
    "state_machine": "state-machine",
    "risk_markers": "risk markers",
    "race_lifecycle": "race/lifecycle",
}
print("----------------------------------------------")
print("SEMANTIC REVIEW")
print(f"  status: {data.get('semantic_status', 'available')}   policy: {policy}")
for key in ("state_machine", "risk_markers", "race_lifecycle"):
    gate = (data.get("semantic_gates") or {}).get(key) or {}
    status = gate.get("status", "unknown")
    confidence = float(gate.get("confidence") or 0)
    reason = str(gate.get("reason") or "")
    print(f"  {labels[key]:16s} {status:7s} {confidence:.2f}   {reason[:96]}")
print(f"  verdict: {data.get('semantic_verdict', 'UNKNOWN')}   semantic gates tripped: {data.get('semantic_gates_tripped', 0)}")
PY
}

sizer_semantic_codes() {
  local json=$1
  python3 - "$json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
def code(key):
    status = ((data.get("semantic_gates") or {}).get(key) or {}).get("status")
    return {"pass": "P", "fail": "F", "unknown": "U"}.get(status, "-")
print(code("state_machine"), code("risk_markers"), code("race_lifecycle"), data.get("semantic_verdict", "-"))
PY
}

sizer_llm_should_review() {
  [ "${SM:-0}" -gt 0 ] || [ "${MARK:-0}" -gt 0 ] || [ "${RACE:-0}" -gt 0 ]
}
