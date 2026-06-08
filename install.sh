#!/usr/bin/env bash
# install.sh — install Story Gauge as an Agent Skill for one or more agent harnesses,
# and (optionally) put its CLIs on PATH.
#
# The whole repo IS the skill: SKILL.md at root, with scripts/ references/ config/
# templates/ beside it. We symlink the repo into each harness's user-level skills dir
# (all three harnesses follow symlinks and read the standard SKILL.md).
#
# Per-agent flags (opt-in). With NO flags, every harness whose home dir exists is
# auto-detected and installed; missing ones are skipped with a note.
#   --claude     ~/.claude/skills/story-gauge
#   --pi         ~/.pi/agent/skills/story-gauge
#   --codex      ~/.agents/skills/story-gauge
#   --all        force all three regardless of detection
#   --bin        also link scripts/{score-story,scan-backlog} into ~/.local/bin
#   --skills-dir DIR   override the target dir for the NEXT --<agent> flag
# Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="story-gauge"
BIN_DIR="${HOME}/.local/bin"

# default user-level skills dirs per harness
CLAUDE_DIR="${HOME}/.claude/skills"
PI_DIR="${HOME}/.pi/agent/skills"
CODEX_DIR="${HOME}/.agents/skills"

want_claude=0 want_pi=0 want_codex=0 want_bin=0 explicit=0 override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --claude) want_claude=1; explicit=1; [ -n "$override" ] && { CLAUDE_DIR="$override"; override=""; } ;;
    --pi)     want_pi=1;     explicit=1; [ -n "$override" ] && { PI_DIR="$override";     override=""; } ;;
    --codex)  want_codex=1;  explicit=1; [ -n "$override" ] && { CODEX_DIR="$override";  override=""; } ;;
    --all)    want_claude=1; want_pi=1; want_codex=1; explicit=1 ;;
    --bin)    want_bin=1 ;;
    --skills-dir) shift; override="$1" ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# No agent flag given => auto-detect: install where the harness's home dir exists.
if [ "$explicit" -eq 0 ]; then
  [ -d "${HOME}/.claude" ] && want_claude=1
  [ -d "${HOME}/.pi" ]     && want_pi=1
  { [ -d "${HOME}/.agents" ] || [ -d "${HOME}/.codex" ]; } && want_codex=1
fi

link_skill() { # agent-label  skills-dir
  local label="$1" dir="$2"
  mkdir -p "$dir"
  ln -sfn "$ROOT" "$dir/$NAME"
  echo "  $label -> $dir/$NAME"
}

did=0
echo "installing skill '$NAME' (repo: $ROOT)"
[ "$want_claude" -eq 1 ] && { link_skill "claude" "$CLAUDE_DIR"; did=1; }
[ "$want_pi" -eq 1 ]     && { link_skill "pi    " "$PI_DIR";     did=1; }
[ "$want_codex" -eq 1 ]  && { link_skill "codex " "$CODEX_DIR";  did=1; }

if [ "$did" -eq 0 ]; then
  echo "  (no target harness selected/detected — pass --claude / --pi / --codex / --all)"
fi

if [ "$want_bin" -eq 1 ]; then
  if [ -d "$BIN_DIR" ]; then
    ln -sfn "$ROOT/scripts/score-story"  "$BIN_DIR/score-story"
    ln -sfn "$ROOT/scripts/scan-backlog" "$BIN_DIR/scan-backlog"
    echo "  bin   -> $BIN_DIR (score-story, scan-backlog)"
  else
    echo "  bin   -> $BIN_DIR not found; add $ROOT/scripts to PATH to call the CLIs directly."
  fi
fi

echo "done."
