# story-sizer

Catch user-stories / specs that are too big for an implementing agent (human or LLM) to finish
without running out of context — the failure mode where a story ships with **unmet acceptance
criteria** and burns a review cycle.

Five gates, any one trips ⇒ recommend SPLIT:

```
ACs ≤ 6 · files ≤ 3 · state-machines ≤ 1 · markers ≤ 3 · race/lifecycle prose = 0
```

Dependency-free bash (`bash` + `awk`/`grep`/`sed`). Works on any markdown story with an
`## Acceptance Criteria` section. Everything — headings, file-path regex, keyword lists,
thresholds — is configurable per repo.

## Install

```sh
git clone <repo> ~/projects/story-sizer
cd ~/projects/story-sizer
./install.sh          # symlinks the Claude Code skill + bin commands
```

`install.sh` links `skill/story-sizer` into `~/.claude/skills/` (so the **story-sizer** skill
becomes available to Claude Code) and `score-story` / `scan-backlog` into `~/.local/bin`.

## Use

```sh
score-story path/to/story.md            # table + verdict; exit 0=READY 1=SPLIT
score-story path/to/story.md --quiet    # exit code only (for CI / pre-commit)
scan-backlog path/to/stories/           # risk dashboard across a folder (recursive)
```

Example:

```
STORY SIZING SCORE — 6-4-red-ci-rolls-back-phase-claim.md
----------------------------------------------
  1 ACs                      10   FAIL (max 6)
  2 files (logic)             4   FAIL (max 3)
  3 state machines~           3   FAIL (max 1)
  4 markers                  13   FAIL (max 3)
  5 race/lifecycle            2   FAIL (max 0)
    dev-notes lines         203   (warn >120)
----------------------------------------------
VERDICT: SPLIT  (5 gates tripped — risk HIGH)
```

## Configure per repo

Drop a `.story-sizer.conf` in the repo (or pass `--config FILE`). Override only the keys you
change; all keys live in [`config/default.conf`](config/default.conf). Common ones:

```sh
FILE_PATH_RE='(src|lib|app)/[A-Za-z0-9_./-]+\.(py|go|rs)'   # your stack
MAX_ACS=8                                                    # your house baseline
AC_ITEM_RE='^[-*][[:space:]]'                                # bullet ACs instead of numbered
```

## Layout

```
bin/score-story      bin/scan-backlog     # CLIs
lib/sizer.sh                              # shared: config + section parsing + scoring
config/default.conf                       # all tunables
docs/story-sizing-rubric.md               # gates, tells, split pattern
templates/overrun-log.md                  # empirical-calibration loop
skill/story-sizer/SKILL.md                # Claude Code skill entry
install.sh
```

## Calibration caveat (read this)

Gates 3–5 are **keyword proxies**, not ground truth, and the thresholds are tuned to one team's
prose density. If a whole backlog flags HIGH, either the house style is marker-/AC-dense (raise
the thresholds) or stories really are over-scoped (gates are right). Use
[`templates/overrun-log.md`](templates/overrun-log.md): log real overruns, tighten thresholds
toward the smallest story that still overran. Treat the dashboard as a **ranking** first — the
all-gates outlier is the signal regardless of absolute cutoffs. And always hand-verify the
state-machine count (`SM~`).

## Pre-commit / CI hook

```sh
score-story path/to/changed-story.md --quiet \
  || { echo "story trips sizing gates — split or justify"; exit 1; }
```
