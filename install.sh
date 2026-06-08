#!/usr/bin/env bash
# install.sh — make story-sizer usable as a Claude Code skill and on PATH.
#   - symlinks skill/story-sizer -> ~/.claude/skills/story-sizer
#   - symlinks bin/* -> ~/.local/bin (if that dir is on PATH)
# Idempotent. Usage: ./install.sh [--skills-dir DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"
BIN_DIR="${HOME}/.local/bin"

while [ $# -gt 0 ]; do
  case "$1" in
    --skills-dir) shift; SKILLS_DIR="$1" ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# The skill needs bin/lib/config/docs/templates alongside SKILL.md. Symlink the whole
# project as the skill dir's backing, exposing SKILL.md at the skill root.
mkdir -p "$SKILLS_DIR"
ln -sfn "$ROOT/skill/story-sizer" "$SKILLS_DIR/story-sizer"
# Make project assets reachable from inside the skill dir.
ln -sfn "$ROOT/bin"        "$ROOT/skill/story-sizer/bin"
ln -sfn "$ROOT/lib"        "$ROOT/skill/story-sizer/lib"
ln -sfn "$ROOT/config"     "$ROOT/skill/story-sizer/config"
ln -sfn "$ROOT/docs"       "$ROOT/skill/story-sizer/docs"
ln -sfn "$ROOT/templates"  "$ROOT/skill/story-sizer/templates"
echo "skill installed -> $SKILLS_DIR/story-sizer"

if [ -d "$BIN_DIR" ]; then
  ln -sfn "$ROOT/bin/score-story" "$BIN_DIR/score-story"
  ln -sfn "$ROOT/bin/scan-backlog" "$BIN_DIR/scan-backlog"
  echo "commands linked -> $BIN_DIR (score-story, scan-backlog)"
else
  echo "note: $BIN_DIR not found; add $ROOT/bin to PATH to call the commands directly."
fi
echo "done."
