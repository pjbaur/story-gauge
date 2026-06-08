# Story Gauge

Catch user-stories / specs that are too big for an implementing agent (human or LLM) to finish
without running out of context — the failure mode where a story ships with **unmet acceptance
criteria** and burns a review cycle.

Five gates, any one trips ⇒ recommend SPLIT:

```
ACs ≤ 6 · files ≤ 3 · state-machine hits ≤ 1 · markers ≤ 3 · race/lifecycle prose = 0
```

## Gates

| # | Gate | Default | Counts | Why it trips |
|---|------|---------|--------|--------------|
| 1 | Acceptance criteria | `MAX_ACS=6` | Top-level AC list items under the configured Acceptance Criteria heading. | Too many independent outcomes for one implementation pass; missed ACs are the common overrun symptom. |
| 2 | Files with logic changes | `MAX_FILES=3` | Distinct paths in the configured File List section, with sibling tests collapsed into their source file. | Broad blast radius raises coordination cost and makes review harder to complete against every touched behavior. |
| 3 | State-machine / control-loop hits | `MAX_SM=1` | Keyword hits such as retry loop, poll loop, state machine, gate loop, fix-forward, saga, reducer. | Multiple state concerns multiply edge cases; verify `SM~` by hand because repeated prose can inflate the count. |
| 4 | Risk markers | `MAX_MARKERS=3` | `CRITICAL`, `Do NOT`, `READ FIRST`, `IMPORTANT`, `WARNING`, `MUST NOT` in Dev Notes and ACs. | Marker density usually means hidden coupling or constraints the story could not isolate. |
| 5 | Race / ordering / lifecycle prose | `MAX_RACE=0` | Terms such as microtask, EPIPE, race condition, deadlock, deferred until, stay alive, happens-before, out-of-order. | Temporal coupling is high-context work; split out prep/refactor or one lifecycle concern before feature wiring. |

All gate inputs are configurable. Gates 3-5 are keyword proxies, so treat them as triage signals:
inspect the story before overriding the verdict. When a gate trips, split vertically so each slice
ships one user-visible outcome or one isolated invariant.

## Optional LLM semantic review

Deterministic scoring remains default. Add `--llm` to request semantic review for gates 3-5:

```sh
score-story path/to/story.md --llm
score-story path/to/story.md --llm --format json
scan-backlog path/to/stories/ --llm
scan-backlog path/to/stories/ --llm --format json
```

LLM mode is opt-in because story text may leave your machine. Provider credentials are never read
from config files; use provider-native environment variables such as `OPENAI_API_KEY`. If provider
settings, credentials, network, timeout, or JSON validation fail, Story Gauge keeps deterministic
output and marks semantic review unavailable.

LLM options:

- `--llm`: request semantic review for gates 3-5.
- `--llm-provider <name>`: provider selector. Current runtime provider: `openai`. Tests also use
  internal `stub`.
- `--llm-model <model>`: model selector.
- `--llm-timeout <seconds>`: provider call timeout.
- `--llm-fail-policy advisory|high-confidence|strict`: semantic exit-code policy.

Semantic gate statuses:

- `pass`: story does not appear to trip this semantic gate.
- `fail`: story appears to trip this semantic gate and includes exact story evidence.
- `unknown`: evidence is insufficient, ambiguous, invalid, or unavailable.

Configure defaults with whitelisted config keys or environment overrides:

```sh
LLM_PROVIDER='openai'
LLM_MODEL='your-model'
LLM_TIMEOUT_SECONDS=30
LLM_CONFIDENCE_THRESHOLD=0.75
LLM_FAIL_POLICY='advisory'
LLM_CONTEXT_MAX_CHARS=24000

STORY_GAUGE_LLM_PROVIDER=openai
STORY_GAUGE_LLM_MODEL=your-model
STORY_GAUGE_LLM_TIMEOUT_SECONDS=30
STORY_GAUGE_LLM_FAIL_POLICY=advisory
```

`LLM_CONTEXT_MAX_CHARS` size-limits story text sent to the provider.

Fail policies:

- `advisory` (default): semantic findings never change exit code.
- `high-confidence`: exit non-zero when any semantic gate fails at or above
  `LLM_CONFIDENCE_THRESHOLD`.
- `strict`: exit non-zero on any semantic fail. Unavailable LLM stays advisory.

Table output prints deterministic verdict first, then a semantic block:

```
SEMANTIC REVIEW
  status: available   policy: advisory
  state-machine    fail    0.83   story contains multiple retry and phase transitions
  risk markers     pass    0.64   warning density is low
  race/lifecycle   unknown 0.41   ordering evidence is ambiguous
  verdict: SPLIT   semantic gates tripped: 1
```

JSON output merges semantic fields into deterministic fields:

```json
{
  "verdict": "READY",
  "semantic_status": "available",
  "semantic_verdict": "SPLIT",
  "semantic_gates_tripped": 1,
  "semantic_gates": {
    "state_machine": {
      "status": "fail",
      "confidence": 0.83,
      "evidence": ["retry loop"],
      "reason": "multiple stateful control concerns"
    }
  }
}
```

Backlog table output adds semantic columns for likely-interesting stories:

```
story                                   ACs files  SM~  mark  race  risk   SM* MARK* RACE*  SEM
---------------------------------------------------------------------------------------------------------
6-4-red-ci-rolls-back-phase-claim        10     4    3    13     2  HIGH*    F     F     F  SPLIT
---------------------------------------------------------------------------------------------------------
SM~ = keyword hit count. SM*/MARK*/RACE*: P pass, F fail, U unknown.
```

Recommended CI posture: keep deterministic `score-story --quiet` as blocking gate. Use
`--llm --llm-fail-policy advisory --format json` for review hints, or move to
`high-confidence` only after local calibration.

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
score-story path/to/story.md --llm            # opt-in semantic review for gates 3-5
scan-backlog path/to/stories/                 # risk dashboard across a folder (recursive)
scan-backlog path/to/stories/ --format json   # machine-readable dashboard
scan-backlog path/to/stories/ --json          # same as --format json
scan-backlog path/to/stories/ --llm           # semantic columns for likely-interesting stories
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
