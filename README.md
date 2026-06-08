# Story Gauge

Catch user-stories / specs that are too big for an implementing agent (human or LLM) to finish
without running out of context — the failure mode where a story ships with **unmet acceptance
criteria** and burns a review cycle.

Five gates, any one trips ⇒ recommend SPLIT:

```
ACs ≤ 6 · files ≤ 3 · state-machine hits ≤ 1 · markers ≤ 3 · race/lifecycle prose = 0
```

Dependency-free bash (`bash` + `awk`/`grep`/`sed`). Works on any markdown story with an
`## Acceptance Criteria` section. Everything — heading levels/text, file-path regex, keyword
lists, thresholds — is configurable per repo.

## One skill, three harnesses

The whole repo **is** an [Agent Skill](https://agent-skills.org) — `SKILL.md` at the root with
`scripts/ references/ config/ templates/` beside it. That standard is shared by Claude Code, pi,
and Codex, so the same skill installs into all three (each just looks in a different dir and
follows the symlink):

| Harness | User skills dir |
|---|---|
| Claude Code | `~/.claude/skills/` |
| pi          | `~/.pi/agent/skills/` |
| Codex       | `~/.agents/skills/` |

## Install

```sh
git clone <repo> ~/projects/story-gauge
cd ~/projects/story-gauge
./install.sh                 # auto-detect: install into every harness present
./install.sh --claude --pi   # or pick harnesses explicitly
./install.sh --all --bin     # all three + put the CLIs on ~/.local/bin
```

`install.sh` symlinks the repo into each selected harness's skills dir. With no flags it installs
into whichever of `~/.claude` / `~/.pi` / `~/.agents`(or `~/.codex`) exist and skips the rest.
`--bin` also links `score-story` / `scan-backlog` into `~/.local/bin` for CI / pre-commit use.

## Use

Inside an agent, just ask ("size this story", "scan the backlog"). Direct CLI use (after
`--bin`, or via `scripts/`):

```sh
score-story path/to/story.md                  # table + verdict; exit 0=READY 1=SPLIT
score-story path/to/story.md --quiet          # exit code only (for CI / pre-commit)
score-story path/to/story.md --format json    # machine-readable result
score-story path/to/story.md --json           # same as --format json
scan-backlog path/to/stories/                 # risk dashboard across a folder (recursive)
scan-backlog path/to/stories/ --format json   # machine-readable dashboard
scan-backlog path/to/stories/ --json          # same as --format json
```

Example:

```
STORY SIZING SCORE - 6-4-red-ci-rolls-back-phase-claim.md
----------------------------------------------
  1 ACs                      10   FAIL (max 6)
  2 files (logic)             4   FAIL (max 3)
  3 state-machine hits~       3   FAIL (max 1)
  4 markers                  13   FAIL (max 3)
  5 race/lifecycle            2   FAIL (max 0)
    dev-notes lines         203   (warn >120)
----------------------------------------------
VERDICT: SPLIT   (5 gates tripped - HIGH)
```

## Configure per repo

Drop a `.story-gauge.conf` in the repo (or pass `--config FILE`). Override only the keys you
change; all keys live in [`config/default.conf`](config/default.conf). Common ones:

```sh
AC_LEVEL=3                                                   # ### Acceptance Criteria
FILE_PATH_RE='(src|lib|app)/[A-Za-z0-9_./-]+\.(py|go|rs)'   # your stack
MAX_ACS=8                                                    # your house baseline
AC_ITEM_RE='^[-*][[:space:]]'                                # bullet ACs instead of numbered
```

Config files accept whitelisted `KEY=value` settings only; they are parsed, not shell-sourced.

## Layout

```
SKILL.md                                  # skill entry (name + description + how-to)
scripts/score-story  scripts/scan-backlog # CLIs
scripts/sizer.sh                          # shared: config + section parsing + scoring
config/default.conf                       # all tunables
references/story-sizing-rubric.md         # gates, tells, split pattern
templates/overrun-log.md                  # empirical-calibration loop
install.sh                                # multi-harness installer
tests/test.sh                             # shell test harness
```

## Calibration caveat (read this)

Gates 3–5 are **keyword proxies**, not ground truth, and the thresholds are tuned to one team's
prose density. If a whole backlog flags HIGH, either the house style is marker-/AC-dense (raise
the thresholds) or stories really are over-scoped (gates are right). Use
[`templates/overrun-log.md`](templates/overrun-log.md): log real overruns, tighten thresholds
toward the smallest story that still overran. Treat the dashboard as a **ranking** first — the
all-gates outlier is the signal regardless of absolute cutoffs. And always hand-verify the
state-machine hit count (`SM~`).

## Pre-commit / CI hook

```sh
score-story path/to/changed-story.md --quiet \
  || { echo "story trips sizing gates — split or justify"; exit 1; }
```

## License

MIT. See [`LICENSE`](LICENSE).
