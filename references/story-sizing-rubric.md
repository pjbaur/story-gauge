# Story Sizing Rubric

Screen every story/spec for oversize **before** it goes to an implementing agent (human or LLM).
The failure mode this prevents: a story so large the implementer cannot hold its whole invariant
set in working context long enough to satisfy every acceptance criterion — it ships with unmet
ACs and burns a review cycle.

> Big = blast radius + coupling, **not** line count.

---

## Hard gates — any ONE trips → SPLIT

| # | Gate | Default | How it's counted |
|---|------|---------|------------------|
| 1 | Acceptance criteria | **≤ 6** | numbered items under the AC heading |
| 2 | Files with logic changes | **≤ 3** | distinct paths in the File List (test siblings collapsed) |
| 3 | State-machine / control-loop hits | **≤ 1** | keyword proxy — *verify by hand* |
| 4 | `CRITICAL` / `Do NOT` / `IMPORTANT`… markers | **≤ 3** | marker hits in Dev Notes + ACs |
| 5 | Race / ordering / lifecycle invariant prose | **0** | microtask/EPIPE/"stay alive"/"deferred until"… |

All thresholds are config (`config/default.conf` or a per-project `.story-gauge.conf`).

---

## Optional semantic review

Use `--llm` only when user opts in to sending story text to a configured provider. It reviews gates
3-5, not gates 1-2. Deterministic counts still run first and remain default CI posture.

Semantic statuses:

- `pass` — story does not appear to trip this semantic gate.
- `fail` — story appears to trip this semantic gate and includes exact story evidence.
- `unknown` — evidence is insufficient, ambiguous, invalid, or unavailable.

LLM output is schema-validated before display. `fail` without exact copied evidence becomes
`unknown`; provider errors, missing credentials, timeouts, and invalid JSON become
`semantic_status=unavailable`. Default fail policy is `advisory`, so semantic findings do not alter
exit code unless `high-confidence` or `strict` is selected.

In backlog scans, semantic review runs only for stories with gate 3-5 deterministic signal; low-signal
stories are marked skipped.

---

## Structural tells (judgment, beyond counts)

- **Marker density** = hidden coupling the author felt but couldn't remove.
- **Prose explaining a race** = temporal coupling that detonates an agent's context.
- **Two state machines sharing mutable state** (e.g. two retry loops sharing one budget) = multiplicative, not additive.
- **Repeated control-loop terms** may be one repeated concern or several loops; verify `SM~` by hand.
- **"Wire N prior stories together"** = highest-risk integration story. Wire ONE consumer per story.
- **"Reconciliation" section** (two overlapping mechanisms) = design debt being resolved mid-build.
- **Long "Do NOT touch" list** = story sits in a tightly coupled blast radius → refactor-first.

## Post-hoc proof it WAS too big

Review finds *acceptance gaps* (ACs unmet), not just bugs → ran out of context before finishing.
Log it in `overrun-log.md`.

---

## Split pattern (vertical slices)

When a gate trips, slice vertically — each slice ≤ 4 ACs and ONE state concern:

1. **Prep / refactor** — isolate the dangerous invariant FIRST (gate-5 trip). No new feature.
2. **Happy path** — success-only wiring.
3. **Failure path** — retries, fix-forward, budgets.
4. **Edges / options** — timeouts, opt-out flags, schema additions.

### Illustrative split — a 10-AC integration story → 4 stories
| Slice | ACs | State concern |
|-------|-----|---------------|
| Prep: isolate a lifecycle signal into a seam | 1 | lifecycle |
| Happy: success-only gate wiring | 3 | the new gate |
| Failure: fix-forward + shared retry budget | 3 | retry loop |
| Edges: timeout + opt-out flag + schema field | 3 | schema/flags |

---

## Calibration (important)

The scorer's gate-3/4/5 inputs are **keyword proxies**, not ground truth, and the absolute
thresholds are tuned to one team's prose density. If your scan flags most stories HIGH, that
means one of two things — and the `overrun-log.md` loop is how you tell them apart:

1. your house style is genuinely marker-/AC-dense → raise the thresholds to your clean-ship baseline; **or**
2. stories really are systematically over-scoped → the gates are right; split more.

Treat the dashboard as a **ranking** first: the all-gates outlier is the signal regardless of
absolute cutoffs. Move numbers from real overruns, not guesses.
