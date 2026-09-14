# Handoff — read this before your first run

A self-contained copy of the Fusion Product Development workspace. An agent takes
a written brief to a verified 289-body parametric model, calibrated renders and a
dimensioned A3 drawing, driving a live Fusion 360 GUI.

Start with `README.md` for setup. This file is the short list of things that will
otherwise cost you a day.

---

## The one prerequisite that is not software

**Fusion is a GUI application and the agent drives it live.** The agent must run
on the same machine, in a logged-in desktop session, with Fusion open on a Design
document. No headless mode, no container, no remote backend. This is the most
common way a first run fails.

---

## Three failures that are not your fault, and how to recognise them

**1 · A shadow skill wins the trigger.** Covered in `README.md`. The tell is a run
that reads the brief correctly and then ignores the procedure — inventing its own
appearance names, or tuning `brightness` in single digits. Run
`hermes skills list` before you start and move anything CAD-shaped out of the way.

**2 · The model renders pure black against a correctly-lit background.** A fresh
document defaults to `sceneSettings.brightness = 1.2`; the scene needs **1700**.
A SolidColor background is painted rather than lit, so it survives at full
strength while the model receives nothing. The Design canvas has its own lighting
and looks completely normal, so this stays invisible until the Render workspace
opens. `brightness` is **lux, not a gain** — anything below 100 means the scene
was never configured.

**3 · Colours are all wrong but every body has an appearance.** The source
appearance must be `Plastic - Glossy (Black)` fetched from
`app.materialLibraries`, not from `des.appearances`. A fresh document only carries
a metal appearance, which has no `opaque_albedo` and no `opaque_emission` — copies
of it cannot hold a colour the canvas can read. Write **both** `surface_albedo`
and `opaque_albedo`; the renderer reads the first and the canvas the second.

---

## What "working" looks like

Four lines in the transcript, in this order:

```
STAGE 1 · SLAB_TOP_vN · data_file=True · PASS
Class 1 · SLAB_Housing_Upper · 1 body · vol=219.091 cm3 · PASS
STAGE 4 · 10 SLAB_* appearances · 289 bodies assigned · PASS
STAGE 6 · workspace FusionRenderEnvironment · brightness 1700.0 · cameraExposure 9.5
```

If class 1 lands on **219.091 cm³** the utilities and the units are right, and the
rest of the build follows the same pattern. If stage 4 lists ten names that are
not the ten in the spec table, stop and check for a shadow skill.

`examples/01_slab_mixer/expected.md` is the full acceptance baseline — read it
**after** a run, not before.

---

## Known open items

These are recorded, not hidden. A run that reports them is behaving correctly.

| Item | State |
|---|---|
| Class 12 `R` legend area | Has never built inside the 40.6–43.6 mm² band. Recorded as an open item; it blocks nothing downstream. |
| Panel graphics body count | 50 expected; runs have produced 50–52. The `R` counter-hole topology is the cause. |
| `create_drawing` | Exceeds the request timeout **while succeeding**. Never retry it, and never call `export_drawing_pdf` — that one hangs the MCP server. |
| Final render duration | Budgeted ~135 s; observed up to 435 s. Slow is not stuck. |
| TBD-12 … TBD-19 | Genuine open decisions, listed in `docs/SLAB_PRD_RevC.pdf` §11.2. Carrying one forward is correct; closing one by guessing is not. |

---

## Two calls that kill the MCP server

Both fail silently rather than raising, and both end the session:

- `sceneSettings.backgroundEnvironment = ...` — `[WinError 10054]`, add-in dies.
- `app.documents.add(...)` — same signature.

Neither is needed. They are listed so nobody discovers them the hard way.

---

## Where things live

```
agents/cad-engineer/SOUL.md        operating rules — also copy to ~/.hermes/SOUL.md
agents/cad-engineer/skills/        the procedure. slab-run is the entry point
examples/01_slab_mixer/prompt.md   the run prompt, and why its stage list is locked
examples/01_slab_mixer/expected.md the acceptance baseline
docs/SLAB_PRD_RevC.pdf             the human-readable brief
renders/, drawings/                the accepted baseline a run is measured against
```

The skills are the specification. The PDF says the same thing more slowly.
