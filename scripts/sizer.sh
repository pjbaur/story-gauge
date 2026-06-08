#!/usr/bin/env bash
# sizer.sh — shared library: config loading, markdown section extraction, scoring.
# Sourced by scripts/score-story and scripts/scan-backlog. Dependency-free (bash + awk/grep/sed).

SIZER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # scripts/
SIZER_ROOT="$(cd "$SIZER_LIB_DIR/.." && pwd)"                   # skill root (holds config/)

# Load defaults, then optional override (--config / env / CWD .story-sizer.conf).
sizer_load_config() {
  # shellcheck disable=SC1091
  source "$SIZER_ROOT/config/default.conf"
  local override="${STORY_SIZER_CONFIG:-}"
  if [ -z "$override" ] && [ -f "$PWD/.story-sizer.conf" ]; then
    override="$PWD/.story-sizer.conf"
  fi
  if [ -n "$override" ] && [ -f "$override" ]; then
    # shellcheck disable=SC1090
    source "$override"
  fi
}

# Build a string of N '#' chars.
sizer_hashes() { local n=$1 s=''; while [ "$n" -gt 0 ]; do s="#$s"; n=$((n-1)); done; printf '%s' "$s"; }

# ERE matching any heading at level 1..N  (e.g. N=2 -> '^(# |## )').
sizer_break_re() {
  local lvl=$1 i re='^('
  for ((i=1; i<=lvl; i++)); do
    re+="$(sizer_hashes "$i") "
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
  start="^$(sizer_hashes "$lvl") ${h}"
  brk="$(sizer_break_re "$lvl")"
  awk -v s="$start" -v b="$brk" '
    $0 ~ s { g=1; next }
    g && $0 ~ b { g=0 }
    g { print }
  ' "$f"
}

# Count distinct changed-file paths from stdin (collapsing test siblings).
sizer_count_files() {
  grep -oE "$FILE_PATH_RE" \
    | sed -E "$TEST_SIBLING_SED" \
    | sort -u | wc -l | tr -d ' ' || true
}

# Is FILE a story? (has the AC heading)
sizer_is_story() { grep -qE "^#+ ${AC_HEADING}" "$1"; }

# score_file FILE -> sets globals: ACS FILES SM MARK RACE DEVLINES TRIP
sizer_score_file() {
  local f=$1
  ACS=$(sizer_section "$f" "$AC_HEADING" 2 | grep -cE "$AC_ITEM_RE" || true)

  local fl; fl=$(sizer_section "$f" "$FILELIST_HEADING" "$FILELIST_LEVEL")
  FILES=$(printf '%s\n' "$fl" | sizer_count_files)
  [ "${FILES:-0}" -eq 0 ] && FILES=$(sizer_count_files < "$f")

  SM=$(grep -ioE "$SM_RE" "$f" | tr 'A-Z' 'a-z' | sort -u | wc -l | tr -d ' ' || true)

  # markers + race prose scoped to Dev Notes + ACs (skips References boilerplate;
  # lifecycle invariants frequently live in ACs, so include them).
  local scope
  scope=$( { sizer_section "$f" "$DEVNOTES_HEADING" 2; sizer_section "$f" "$AC_HEADING" 2; } )
  MARK=$(printf '%s\n' "$scope" | grep -oiE "$MARKER_RE" | wc -l | tr -d ' ' || true)
  RACE=$(printf '%s\n' "$scope" | grep -oiE "$RACE_RE" | wc -l | tr -d ' ' || true)

  DEVLINES=$(sizer_section "$f" "$DEVNOTES_HEADING" 2 | wc -l | tr -d ' ' || true)

  TRIP=0
  [ "${ACS:-0}"  -gt "$MAX_ACS" ]     && TRIP=$((TRIP+1))
  [ "${FILES:-0}" -gt "$MAX_FILES" ]  && TRIP=$((TRIP+1))
  [ "${SM:-0}"   -gt "$MAX_SM" ]      && TRIP=$((TRIP+1))
  [ "${MARK:-0}" -gt "$MAX_MARKERS" ] && TRIP=$((TRIP+1))
  [ "${RACE:-0}" -gt "$MAX_RACE" ]    && TRIP=$((TRIP+1))
  return 0
}

# Map trip count -> risk word.
sizer_risk() { case "$1" in 0) echo OK;; 1) echo WATCH;; *) echo HIGH;; esac; }
