# Story Overrun Log

Record every story that overran the implementer's context — forced a restart/`/clear`, shipped
with unmet ACs, or produced a review full of *acceptance gaps* (not just bugs). Goal: tighten the
sizing gates empirically toward the **smallest story that still overran**, instead of guessing.

## Metrics log

| story | ACs | files | state machines | markers | dev-notes lines | outcome |
|-------|-----|-------|----------------|---------|-----------------|---------|
| _example_ | 10 | 4 | 2 | 13 | 203 | overran; shipped unmet ACs → re-work |

> Populate rows fast: `score-story <story.md>` or `scan-backlog <dir>`. `state machines` starts
> from the `SM~` keyword hit count; verify by hand before calibrating.

## Retro prompts (run when adding a row)

1. **Which single gate would have caught this earliest?** (If none → add/adjust a gate.)
2. **What was the true unit of complexity?** (state machine? lifecycle invariant? N-way integration?)
3. **What was the minimal prep story** that would have de-risked the rest?
4. **Did any gate fire falsely** on a story that actually shipped clean? (loosen it.)
5. **Tighten:** is there a smaller overrun than the current threshold? Lower the gate toward it.

## Current calibrated thresholds

Mirror of `config/default.conf` — update both together when a retro moves a number.

- ACs ≤ 6 · files ≤ 3 · state-machine hits ≤ 1 · markers ≤ 3 · race/lifecycle prose = 0
- dev-notes > 120 lines = soft warn

_Last calibration: <date> (<reason>)._
