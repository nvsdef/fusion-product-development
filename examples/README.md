# Examples

Worked runs. Each directory carries the prompt that starts it, the values a
correct run produces, and any reference material it needs.

| Example | What it exercises | Duration |
|---|---|---|
| `01_slab_mixer` | The whole loop — cold build of 289 bodies, CMF, calibrated render, A3 drawing, report | ~45 min cold, ~10 min warm |

## Running one

1. Fusion open, on a **Design** document.
2. `python3 scripts/setup/verify_layout.py` — pure arithmetic, no Fusion, must
   exit 0. Catches a clearance violation in 30 ms rather than after a
   twenty-minute build.
3. Start the agent and paste `prompt.md`.
4. Compare against `expected.md` when it finishes.

## What `expected.md` is for

It is the acceptance baseline, not a narrative. Every figure in it was measured
during the verified run of 11 September 2026, and each is stated with the check
that produces it. Read it **after** a run.

If a number in your run disagrees with `expected.md`, check the model before you
check the table — but if the model is right and the table is wrong, fix the
table and say which measurement replaced it. A baseline nobody corrects stops
being a baseline.

## Authority

```
/skill slab-run          the procedure
/skill slab-product-spec the dimensions
expected.md              the acceptance values
docs/SLAB_PRD_RevC.pdf   the human record
```

The skills govern. The PDF says the same thing more slowly, and an agent that
builds from it instead of from the skill is doing it the hard way.
