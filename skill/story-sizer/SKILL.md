---
name: story-sizer
description: Score a markdown user-story / spec / ticket for oversize risk before an agent implements it, and recommend how to split it. Use when the user asks to "size a story", "is this story too big", "check story sizing", "scan the backlog for risk", "will this overrun context", or "how should I split this story". Works on any markdown story with an Acceptance Criteria section; configurable per repo.
---

# story-sizer

Catch stories too large for an implementer (human or LLM) to finish without running out of
context — the failure mode where a story ships with unmet acceptance criteria. Gates a story on
five proxies: AC count, changed-file count, distinct state machines, danger-marker density, and
race/lifecycle prose. Any one over threshold ⇒ recommend SPLIT.

## When to use

- User points at a story/spec/ticket `.md` and asks whether it's too big or ready to implement.
- User wants a risk overview across a folder of stories ("scan the backlog").
- User wants concrete split advice for an oversized story.

## How to run

Scripts are dependency-free bash. Resolve `SIZER` to this skill's repo (the dir containing
`bin/`). If installed via `install.sh`, `bin/` is on PATH and you can call the commands directly.

Score one story (exit 0 = READY, 1 = SPLIT):
```sh
score-story path/to/story.md
# CI/quiet (no table, just exit code):
score-story path/to/story.md --quiet
```

Scan a backlog directory (recursive):
```sh
scan-backlog path/to/stories/
```

Per-repo overrides (headings, file-path regex, keyword lists, thresholds): drop a
`.story-sizer.conf` in the working dir, or pass `--config FILE`. Only override the keys you change;
see `config/default.conf` for every key.

## Interpreting output

Five gates (defaults): `ACs ≤ 6 · files ≤ 3 · state-machines ≤ 1 · markers ≤ 3 · race-prose = 0`.

- **READY** — no gate tripped. Fine to implement.
- **WATCH** — exactly one tripped. Skim the structural tells in `docs/story-sizing-rubric.md`.
- **SPLIT / HIGH** — two or more tripped. Recommend slicing.

**Critical caveats to relay to the user, not hide:**
- `SM~` (state machines) is a keyword estimate — **verify by hand** before asserting it.
- The proxies measure prose, not ground truth. If a whole backlog flags HIGH, the thresholds
  likely need calibration to that team's house style — say so; don't present it as "everything is broken."
- Treat the dashboard as a **ranking**: the all-gates outlier is the real signal regardless of
  absolute cutoffs.

## Recommending a split

Slice vertically, each slice ≤ 4 ACs and ONE state concern, in this order:
1. **Prep/refactor** — isolate the dangerous lifecycle/race invariant first (the gate-5 trip).
2. **Happy path** — success-only wiring.
3. **Failure path** — retries / fix-forward / budgets.
4. **Edges** — timeouts, opt-out flags, schema additions.

Full rubric, tells, and worked example: `docs/story-sizing-rubric.md`.

## Closing the loop

When a story actually overruns in practice, append a row to the team's overrun log (template:
`templates/overrun-log.md`) and tighten the config thresholds toward the smallest story that
still overran. Empirical calibration beats guessed cutoffs.
