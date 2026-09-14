## What changed

## Why

## Verification

- [ ] `python3 scripts/setup/sync_shared_skills.py` reports **0 updated**
- [ ] `python3 scripts/setup/verify_layout.py` exits **0**
- [ ] If a skill changed: edited `skills/_shared/`, not an agent copy

## If this asserts new Fusion API behaviour

- [ ] Observed in a live session (not inferred from docs)
- [ ] Measured value included, not an estimate
- [ ] Before/after volume, face count or bbox recorded

## If this touches the pipeline gates

- [ ] Rationale stated — the failure mode is silent (render and drawing
      disagreeing with the model without anyone noticing)
