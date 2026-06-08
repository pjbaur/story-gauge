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
    MAX_ACS|MAX_FILES|MAX_SM|MAX_MARKERS|MAX_RACE|WARN_DEVNOTES_LINES) return 0 ;;
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

sizer_validate_config() {
  local key
  for key in AC_LEVEL DEVNOTES_LEVEL FILELIST_LEVEL MAX_ACS MAX_FILES MAX_SM MAX_MARKERS MAX_RACE WARN_DEVNOTES_LINES; do
    sizer_validate_number "$key" || return 2
  done
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
