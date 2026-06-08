# LLM Assistance for Gates 3-5

## Goal

Add optional LLM-assisted semantic review for gates 3-5 while preserving the current deterministic
keyword gates as the default fast path.

The LLM should improve adaptability for:

- Gate 3: state-machine / control-loop complexity.
- Gate 4: hidden coupling implied by warnings, constraints, and risk-heavy prose.
- Gate 5: race, ordering, lifecycle, and temporal-coupling risk.

The deterministic scorer remains dependency-free and stable for CI. LLM output is opt-in,
schema-validated, evidence-based, and advisory by default.

## Non-Goals

- Do not replace gates 1-2 with LLM judgment.
- Do not make network or model access required for normal `score-story` or `scan-backlog`.
- Do not let free-form LLM prose directly control exit codes.
- Do not require users to send private stories to a remote model without explicit opt-in.

## Design

Keep existing behavior:

```sh
score-story path/to/story.md
scan-backlog path/to/stories/
```

Add semantic modes:

```sh
score-story path/to/story.md --llm
score-story path/to/story.md --llm --format json
scan-backlog path/to/stories/ --llm
scan-backlog path/to/stories/ --llm --format json
```

The deterministic gates still compute:

- `acs`
- `files`
- `state_machine_hits`
- `markers`
- `race`
- `gates_tripped`
- `verdict`

The LLM layer appends:

```json
{
  "semantic_gates": {
    "state_machine": {
      "status": "pass",
      "confidence": 0.83,
      "evidence": ["..."],
      "reason": "..."
    },
    "risk_markers": {
      "status": "fail",
      "confidence": 0.78,
      "evidence": ["..."],
      "reason": "..."
    },
    "race_lifecycle": {
      "status": "unknown",
      "confidence": 0.41,
      "evidence": [],
      "reason": "..."
    }
  },
  "semantic_verdict": "SPLIT",
  "semantic_gates_tripped": 1,
  "suggested_slices": ["..."]
}
```

Allowed statuses:

- `pass`: story does not appear to trip this semantic gate.
- `fail`: story appears to trip this semantic gate.
- `unknown`: insufficient evidence or ambiguous story prose.

LLM failures should degrade to deterministic output plus an explicit semantic status of unavailable.

## CLI Contract

Add options:

- `--llm`: request semantic review for gates 3-5.
- `--llm-provider <name>`: optional provider selector, default from config/env.
- `--llm-model <model>`: optional model selector, default from config/env.
- `--llm-timeout <seconds>`: hard timeout, default conservative.
- `--llm-fail-policy advisory|high-confidence|strict`: controls exit behavior.

Default fail policy:

- `advisory`: LLM findings never change exit code.

Optional policies:

- `high-confidence`: fail if semantic verdict is `SPLIT` and any semantic gate has `fail`
  with confidence above configured threshold.
- `strict`: fail on any semantic `fail`; unavailable LLM remains advisory unless explicitly
  configured otherwise.

## Config

Extend config whitelist in `scripts/sizer.sh` and defaults in `config/default.conf`:

```sh
LLM_PROVIDER=''
LLM_MODEL=''
LLM_TIMEOUT_SECONDS=30
LLM_CONFIDENCE_THRESHOLD=0.75
LLM_FAIL_POLICY='advisory'
LLM_CONTEXT_MAX_CHARS=24000
```

Environment overrides should also be supported:

- `STORY_GAUGE_LLM_PROVIDER`
- `STORY_GAUGE_LLM_MODEL`
- `STORY_GAUGE_LLM_TIMEOUT_SECONDS`
- `STORY_GAUGE_LLM_FAIL_POLICY`

Keep provider credentials outside config files. Use provider-native environment variables.

## Implementation Steps

1. Add semantic review helper.

   Create `scripts/llm-review-gates`. It should:

   - Accept story path plus deterministic JSON from `score-story`.
   - Build a compact prompt focused only on gates 3-5.
   - Ask for strict JSON only.
   - Validate required keys and allowed enum values.
   - Clamp confidence to `0.0..1.0`.
   - Require every `fail` to include evidence copied from story text.
   - Return unavailable JSON on provider error, timeout, invalid JSON, or missing credentials.

2. Add provider abstraction.

   Start with one provider path, but isolate the call behind a function:

   - `llm_call_openai` or equivalent.
   - Input: prompt JSON.
   - Output: raw model JSON.

   This keeps later support for local models or other APIs small.

3. Update `score-story`.

   - Parse `--llm` and related options.
   - In table mode, print deterministic table first, then `SEMANTIC REVIEW` block.
   - In JSON mode, merge semantic object into deterministic JSON.
   - Keep current exit behavior unless `LLM_FAIL_POLICY` says otherwise.

4. Update `scan-backlog`.

   - Parse `--llm`.
   - Run deterministic scan first.
   - Run semantic review only for likely-interesting stories:
     - stories already tripping gates 3-5, or
     - stories near thresholds, or
     - all stories if `--llm-all` is later added.
   - Add semantic columns in table output:
     - `SM*`
     - `MARK*`
     - `RACE*`
     - `SEM`
   - Include semantic objects in JSON output.

5. Add tests.

   Use stubbed provider output; do not call network in tests.

   Cases:

   - Existing deterministic tests still pass without LLM env.
   - `--llm` with unavailable provider returns deterministic verdict and semantic unavailable.
   - Valid LLM JSON is merged into `--format json`.
   - Invalid LLM JSON degrades cleanly.
   - `fail` without evidence becomes `unknown` or unavailable.
   - `high-confidence` policy changes exit code only when threshold is met.

6. Update docs.

   Update:

   - `README.md`
   - `SKILL.md`
   - `references/story-sizing-rubric.md`

   Document:

   - deterministic gates remain default.
   - LLM mode is advisory by default.
   - privacy and credential behavior.
   - sample table and JSON output.
   - recommended CI posture.

## Prompt Shape

System intent:

```text
You classify story sizing risk for gates 3-5 only. Use only provided story text.
Return strict JSON. Do not invent evidence. If evidence is ambiguous, use unknown.
```

User payload:

```json
{
  "deterministic_score": {
    "state_machine_hits": 2,
    "markers": 4,
    "race": 0
  },
  "gate_definitions": {
    "state_machine": "Stateful workflow, control loop, retries, phases, transitions, reducers, watchers, orchestration, or fix-forward behavior.",
    "risk_markers": "Dense warnings, must-not constraints, hidden coupling, invariants, or fragile implementation constraints.",
    "race_lifecycle": "Temporal ordering, lifecycle, shutdown, process/signal behavior, async races, happens-before requirements, out-of-order handling, or connection lifetime."
  },
  "story_text": "..."
}
```

## Risk Controls

- Default remains deterministic and dependency-free.
- LLM mode must never shell-source user config.
- LLM output must be parsed and validated before display.
- Evidence should be short and bounded.
- Story text sent to provider should be size-limited.
- Network/model failure should not break deterministic scoring.
- CI fail behavior must require explicit fail policy.

## Milestones

1. Semantic helper with stubbed tests.
2. `score-story --llm` table and JSON support.
3. LLM config and fail-policy support.
4. `scan-backlog --llm` support.
5. Docs and examples.

## Acceptance Criteria

1. Existing CLI behavior and tests are unchanged without `--llm`.
2. `score-story --llm --format json` emits deterministic fields plus validated semantic fields.
3. LLM unavailable/invalid output never crashes scoring.
4. Semantic `fail` findings include story evidence or are downgraded.
5. Default LLM mode is advisory and does not alter exit code.
6. Optional high-confidence policy can alter exit code predictably.
7. Tests cover deterministic mode, semantic success, semantic failure, invalid model output, and fail-policy behavior.
