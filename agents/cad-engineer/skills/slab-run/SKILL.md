---
name: "slab-run"
description: "Run the SLAB product pipeline end to end from one prompt - save, gate, cold-build 289 bodies, apply CMF, calibrate exposure, render hero and plan finals, composite, compose the GA sheet, then open the native drawing last. Use for any request to build, rebuild, render, draw or report on SLAB, or to build a portable 6-channel production mixer, a USB-C audio interface, or a mixer from a product design brief and concept mockups in Fusion 360."
---

# SLAB — end-to-end run procedure

Portable 6-channel production mixer / USB-C audio interface. This file is the
**procedure**: what to do, in what order, with the code that works and the
measurement that proves each step landed.

**Precedence.** This file outranks `slab-product-spec` on method and order;
`slab-product-spec` is the dimensional reference. Both outrank
`docs/SLAB_PRD_RevC.pdf`, which is the human record.

**Verified end to end on** Fusion build 2705.1.11
(`a40f190f24413dd1bb4f1434f056c1379a3b5224`), 11 September 2026. Cold build to
delivered drawing: ~45 min.

---

## The run, in order

```
0  preflight            1  save to cloud       2  gate
3  cold build (12 classes)                     4  CMF
5  viewport check       6  exposure (1 pass)    7  two finals
8  composite + measure  9  views -> sheet -> drawing (LAST)
10 report
```

Steps 1–8 are reversible. Step 9 ends the session's ability to touch the model.

**Report after every class. This is mandatory.** One `execute_code` call per
build class, and when it returns, state one line:

```
Class 5 · SLAB_Knob_Small · 20 bodies · bbox [...] · vol ... cm3 · expected ... · PASS
```

Measured against expected, every class, all twelve. These twelve lines are the
record that the run was verified rather than merely executed - without them the
trace is an undifferentiated wall of `execute_code` calls and nobody can tell a
checked build from a lucky one.

### Do not call `ask` before stage 10

Your harness provides an `ask` / ask-user built-in. It is **not** in
`cad-agent.yaml`'s tool list, because that list only filters the Fusion MCP
tools - the built-in is always available, so nothing but this rule stops you
using it.

**Do not call it between stage 1 and stage 10.** Not to confirm a plan, not to
report progress, not to check in mid-build, not because the run is long. Reaching
a natural checkpoint is not a reason to hand control back; "pausing here, I'm
mid-build" is the failure, not good manners. Two runs have ended this way - one
after class 2, one after class 10 - both healthy, both with every checksum
passing, both abandoned with the model waiting on a reply nobody owed it.

Progress is reported by **printing**, not by asking. Print the class line, print
the checklist, keep going in the same turn.

`ask` is correct in exactly **one** place: after stage 10, when the run is
delivered. **A HALT is not an `ask`** - report the measured numbers, write
`BUILD_STATE.json`, and stop. Asking after a HALT leaves the session waiting
indefinitely on an operator who may not be watching.

### When the run ends

The run ends at **stage 10**, when the report is written. Before that it ends for
exactly two reasons, both of them measurements you take yourself: a **missed
checksum** after two rebuilds, or a **HALT condition** from
`fusion-scratch-build` §1. Report the numbers and stop.

That is the complete list. Work stage to stage until one of those three things is
true.

**Reporting is not pausing.** State the numbers and continue straight to the next
class in the same turn. Do not wait for a reply, do not ask whether to continue,
and do not ask for approval between classes or between stages - nothing in this
run needs it. The only reason to stop is a missed checksum or a HALT condition:
report the numbers and halt.

**Every stage ends in a printed line.** Not an `assert` buried in a code block -
a line in the transcript with the measured values in it. This is the difference
between the stages that work and the stages that do not:

| Stage | Ends in a printed number | Outcome across four runs |
|---|---|---|
| 3 build | yes - bbox + volume per class | correct **4 / 4** |
| 4 CMF | no | invented names and colours **4 / 4** |
| 6 exposure | no | never set; black renders |
| 6 workspace | no | never switched |

The rules for all four were present and correct the whole time. The ones that got
followed were the ones that had to show their work. So: `STAGE n · <measured
values> · PASS`, every stage, before moving to the next.

**Keep a visible checklist.** If your harness has a task or todo tool, create the
twelve classes as tasks before stage 3 and close each one as it passes. If it
does not, print the checklist yourself - post it once before stage 3, then
re-print it after every class with the state markers updated:

```
[x] 1 Housing_Upper      1 body    PASS
[x] 2 Housing_Base       5 bodies  PASS
[>] 3 Panel_Control      building
[ ] 4 Keypad
...
[ ] 12 Panel_Graphics
```

Twelve lines, re-posted twelve times. It looks repetitive and that is the point:
it is the only thing that makes a long autonomous run legible while it is still
running, and it is what lets a reader see progress without reading every
`execute_code` payload.

Also checkpoint `BUILD_STATE.json` after each class - `completed_classes`,
`bodies`, `next_stage` - so a crash costs one class rather than the run.

Announce each stage as you enter it.

The operator supplies exactly one thing: **the document name.** Everything else -
output paths, resolutions, the order of stages - is in these files. Renders go to
`~/fusion-renders` per `fusion-photoreal-render`, never into the project folder.

### Retry budget - three strikes, then move on

The harness blocks any tool after ~5 identical failures. That budget is shared
with the work, so a loop spends it on nothing and leaves you unable to call the
tool when it matters.

- **Same call, same arguments: three attempts maximum.** Then change the
  approach or record the failure and continue.
- **Sleep between attempts.** A probe fired immediately after a failure usually
  fails for the same reason and just spends budget.
- **A blocked tool is not a failed operation.** `repeated_exact_failure_block`
  means the harness stopped you asking; it says nothing about whether the thing
  worked. Find out by measuring the model, not by asking again.
- **Never retry a stage that already passed its checksum.** Re-running a built
  class duplicates bodies; that is how one run produced four identical housings.

### Stage 9 failing does not fail the run

`create_drawing` is the last Fusion action, the only one-way door, and the only
stage whose failure costs nothing: the model, CMF, renders and composed A3 sheet
all exist before it. If the native drawing does not land, **record it as an open
item and go on to stage 10.** Write the report, deliver the sheet as the 2D
output, and finish. A run that reaches stage 9 and then abandons the report has
thrown away the deliverables over the least valuable artefact in the pipeline.

Stage 10 needs no Fusion access, so it completes either way.

### A value you did not write is not a value you know

Every failure in this pipeline that survived all the checksums was a **setting
that was never written**, sitting at a document default nobody looked at:

| Setting | Default | Needed | What the default produced |
|---|---|---|---|
| `sceneSettings.brightness` | **1.2** | **1700** | a pure black hero, twice - CMF was perfect underneath |
| body appearance | library material | `SLAB_*` | every body coloured, every colour wrong, LEDs unable to glow |
| `start_render(view=...)` | `'iso'` | `'current'` | two quality-95 finals of the wrong camera |

None of these raise. None move a body count, a volume or a bounding box. Every
geometry checksum passes while the deliverable is wrong.

**So: for any setting a stage depends on, write it explicitly and assert it back
in the same call - even when you believe it already holds.** A spec that states a
value is telling you to *write* that value, not describing what you will find.
"Start at brightness 1700" means set it to 1700 and check.

```python
ss.brightness = 1700.0
assert ss.brightness >= 1200, f"brightness {ss.brightness} - below the 1200-22000 band"
```

The rule generalises: **the checksum for a setting is reading it back.** Geometry
is proved by volume and bbox; configuration is proved by re-reading the property.
A stage that changed no measurable geometry still needs its own proof.

### Which file to read, and when

**This file is the entry point.** It covers the whole run; the others are
stage references. Pull each one in at its stage rather than all five up front -
they are long, and the context you spend early is context you need at stage 9.

| Before stage | Read | For |
|---|---|---|
| 3 | `fusion-scratch-build` | cold-build discipline and the HALT rule |
| 3 | `slab-product-spec` §1-3 | API utilities, derivation rules, the 12 classes |
| 4 | `slab-product-spec` §5 | the CMF table - roughness, f0, emission |
| 6 | `fusion-photoreal-render` | exposure, camera, render polling |
| 9 | `fusion-2d-drawings` | the drawing call, and the one that must never run |

Paths are `agents/cad-engineer/skills/<name>/SKILL.md`. If a stage's file has not
been read, read it before starting that stage - not after something fails.

---

## 0 · Preflight

1. **`get_design_type`.** If it errors with `'Drawing' object has no attribute
   'designType'`, a Drawing document is active. **Try to recover before giving
   up** - a Drawing is a separate document, so the Design document is usually
   still open beside it:

   ```python
   for d in app.documents:
       if d is not app.activeDocument:
           d.activate(); break
   ```
   Then re-check `app.activeProduct`. If it reads `adsk::fusion::Design`, you
   have recovered; continue.

   **Do not call `app.documents.add(...)` to make a fresh Design document.** It
   is a fatal write: `[WinError 10054]`, the add-in dies, and the session is over.

   Only if activation fails does this need a human clicking the Design tab. Say
   so and stop - this is preflight, so nothing has been built and nothing is
   lost.
2. **`ping`.** Silence means a modal dialog **or** a long-running command. Wait
   and poll - sleep ~45 s, probe **once**, three probes maximum. If it is still
   silent after three, report that Fusion is unreachable and stop; that is an
   environment failure, not a build failure. Do not retry whatever triggered it.
3. **You are on the same machine as Fusion.** This drives a live GUI; a remote
   backend cannot reach it.
4. **Derive the document name; do not ask for one.** If the prompt names a
   document, use it exactly. Otherwise take the next free `SLAB_TOP_vN`:

   ```python
   import re
   names = {f.name for f in proj.rootFolder.dataFiles}
   used  = [int(m.group(1)) for n in names
            for m in [re.fullmatch(r'SLAB_TOP_v(\d+)', n)] if m]
   DOC_NAME = f"SLAB_TOP_v{max(used, default=0) + 1}"
   ```

   **Never reuse a name and never fall back to bare `SLAB_TOP`.** Saving onto an
   existing document makes the gate pass against the old model, and the run
   skips the build entirely while reporting success. Print the chosen name in
   the `STAGE 1` line so it is on the record.

---

## 1 · Save to the cloud

Before the first feature. It names the root component (which takes the filename
and cannot be renamed through the API) and it is the precondition for the
drawing.

```python
hub  = app.data.activeHub          # app.data.activeProject raises on a fresh doc
prjs = hub.dataProjects
proj = next((prjs.item(i) for i in range(prjs.count)
             if prjs.item(i).name == 'Default Project'), prjs.item(0))
app.activeDocument.saveAs(DOC_NAME, proj.rootFolder,
                          'SLAB - portable 6-channel production mixer', 'RevC')
# DOC_NAME is the one value the operator supplies in the prompt. Never hardcode
# 'SLAB_TOP': saving over an existing document makes the gate pass against the
# old model, and the run silently skips the build.
```

Verify `app.activeDocument.name` **and** `design.rootComponent.name`.

---

## 2 · Gate before building

| Gate result | Do |
|---|---|
| All pass | **Skip the build.** Go to step 5. Saves ~35 min. Report the gate result in place of the twelve class lines, and say which path you took |
| `NO_ACTIVE_DESIGN`, or root with 0 bodies | **Skip the gate script entirely** - it checks a model that does not exist. Report `STAGE 2 · empty document · cold build` and go to step 3 |
| Some fail | Repair **only the failing class**. Keep the document |

The gate script is at the end of this file.

---

## 3 · Cold build — one feature class per `execute_code` call

The API works in **centimetres**; every figure below is mm. Divide by 10.

Set `sk.isComputeDeferred = True` before adding curves and `False` after, for any
sketch over ~5 curves. **Name every sketch as you create it.** Save after each
class and confirm the checksum before starting the next.

| # | Class | Bodies | Checksum |
|---|---|---|---|
| 1 | `SLAB_Housing_Upper` extrude + shell | 1 | **219.091 cm³** |
| 2 | …recess, 4 notches, 6 strips | 1 | **149.056 cm³** after recess |
| 3 | `SLAB_Housing_Base` shell + 4 feet + 2 ports | 5 | **209.947 cm³**; ports remove **190.0 mm³** |
| 4 | `SLAB_Panel_Control` | 1 | **56.970 cm³**, 6 faces, Y −46.000…+165.000 |
| 5 | `SLAB_Knob_Small` extrude + fillet | 20 | 4 faces each; radii below |
| 6 | `SLAB_Knob_Large` extrude + fillet | 3 | 4 faces each |
| 7 | `SLAB_Keypad` | 10 | 10 faces each, Z 44.2→46.6 |
| 8 | `SLAB_Panel_Ticks` | 173 | 173 profiles → 173 bodies |
| 9 | `SLAB_Knob_Pointers` | 23 | Z 60.23–61.15 / 58.73–59.65 |
| 10 | `SLAB_Power_Switch` | 2 | toggle bbox below |
| 11 | `SLAB_LED_Indicators` | 1 | 5 profiles merge to 1 |
| 12 | `SLAB_Panel_Graphics` | 50 | table 1023 mm², grid 75.8 mm² each |

**289 bodies, 12 components including root.** Those two are the checksums.
Timeline count and mass are not, and **face counts are build-path dependent**.

### Envelope

Housing **195 (X) × 340 (Y) × 46 (Z)**, corner radius 10.0, wall 2.5, split line
Z 23.0, feet Z 0–3.5. Origin centred in plan, Z 0 at ground. **+Y is the long
axis, away from the operator.** Overall bbox finishes at
**197.040 × 340.040 × 61.210**.

### Housing upper

Rounded rect on a plane at Z 23.0, extrude **+23.0**, shell **2.5** removing the
**bottom** face (select by geometry: planar, `abs(normal.z) > 0.99`,
`origin.z == 2.3`). Then cut from the top face downward — it survives the shell,
so there is no ordering problem:

- **Panel recess** 137 × 213 centred **(0, +59.5)**, 2.4 deep from Z 46 to a
  floor at 43.6, sharp corners.
- **Four edge notches**, 1.2 deep, plan width **21 on X**, overhanging the ±97.5
  outline so the silhouette steps inward. Heights differ by design: TL 14.3 @
  (−90.2, 143.8), TR 9.5 @ (91.0, 139.5), ML 22.9 @ (−90.2, 40.3), MR 12.4 @
  (91.0, 66.5). Removes **1241.0-1241.4 mm³** - three runs measured 1241.0, 1241.0, 1241.4. Anything in that band passes.
- **Six strip cuts** 29 × 1.0 × **0.5 deep** at X ±83, Y 112.8 / 57.4 / 12.6.
  Removes **87.0 mm³**.

### Housing base

Same rounded rect at Z **3.5**, extrude **+19.5**, shell **2.5** removing the
**top** face. Four feet 18 × 18 at X ±77.5, Y ±150, Z 0→3.5 as separate bodies.
Two USB-C ports on the **−X** face, 9.5 (Y) × 4.0 (Z), at Y −38.0 and −16.0,
centred Z 13.5 — build them; they remove exactly **190.0 mm³**. Use
`sk.modelToSketchSpace()` to place them so the sketch's own axes need no
reasoning about.

### Panel

135 × 211 × 2.0 centred **(0, +59.5)**, Z 43.6 → 45.6. Plain slab, 6 faces, no
shaft holes. Measured Y range **−46.000 … +165.000** — the tell that the panel is
at the specified +59.5 with its intended 4.0 mm margin at +Y.

### Small knobs

20 circles r 6.75 on Z 45.6 at X ∈ {−50.4, −16.8, 16.8, 50.4} × Y ∈
{28, 58, 88, 118, 148}, one tapered extrude **+15.5 at −5°**, then one fillet of
**0.75** over all 20 top edges.

```python
ei.setOneSideExtent(
    adsk.fusion.DistanceExtentDefinition.create(V(1.55)),
    adsk.fusion.ExtentDirections.PositiveExtentDirection,
    V(math.radians(-5.0)))
```

**Prove the taper by edge radii, not mass** — a frustum's volume is symmetric in
R and r, so a flipped taper is invisible to mass, body count and bbox:

```
[[45.6, 6.75], [60.42, 5.454], [61.1, 4.707]]   # must decrease with Z; 4 faces
```

### Large knobs, pads

Large: 3 circles r 16.0 at X −45 / 0 / +45, Y −23, on Z 45.6, extrude **+14.0**
straight, fillet **1.10**. Radii `[[45.6, 16.0], [58.5, 16.0], [59.6, 14.9]]`.

Pads: ten rounded squares **18.6, R3** on Z 44.2, extrude **+2.4**. 10 faces each.

```
bottom : (-88,-56) (-44,-56) (0,-56) (44,-56) (88,-56)
left   : (-88, 76) (-88, -4)
right  : ( 88, 93) ( 88, 40) ( 88, -4)
```

Edge pads sit **0.200 mm** inside the housing outline. That inset is deliberate.

### Ticks

One sketch on Z 45.6, 173 radial bars width **0.8**, extrude **+0.45**. Angles
from **+Y** over **250°**. Small: 7 each, r 8.75→11.25, step 250/6°. Large: 11
each, r 18→21.5, step 25°.

```python
a  = math.radians(ang)
ur = (-math.sin(a),  math.cos(a))      # radial, 0 deg = +Y
ut = ( math.cos(a),  math.sin(a))      # tangential
```

173 profiles gives 173 bodies in one call. Batching is not required.

### Pointers, power switch, dividers

**Pointers** — boxes 1.1 × 5.6 × 0.92 pointing +Y, two extrudes. Small (20):
centre (knob X, knob Y **+3.1**), Z 60.23 → 61.15. Large (3): centre
(knob X, **−15.65**), Z 58.73 → 59.65. Each clears its host by **0.05** — never
build an inlay coplanar with its host face.

**Power switch** — toggle Ø11.0 at **(−94.0, +130.0)**, Z 44.2 → 59.0; LED Ø5.2
at (91.0, 139.5), Z 46.0 → 46.6. Toggle bbox must read
`[-99.5, 124.5, 44.2, -88.5, 135.5, 59.0]`.

**Dividers** — raised 0.5 from Z 45.6. One horizontal rule 132 × 0.9 at Y +4,
two verticals 0.9 × 47 at X ±22.5 running **downward** from Y +4 to Y −43
(DEC-C7). They touch, so five profiles extrude into **one** body.

### Panel graphics — 50 bodies, five sub-extrudes

All raised **0.15** from Z 46.0.

| Sub-class | Bodies | Profile rule |
|---|---|---|
| Table | **1** | keep profiles with **min bbox dim ≤ 2 mm** |
| Grid blocks | **2** | same |
| Scale ticks | **30** | keep all |
| Legends R, I, V | **3** | **centroid-in-region** |
| Waveform | **14** | keep all |

**The min-dimension rule belongs to orthogonal bar grids only.** Applied to the
legends it deletes the R's leg and both of the V's strokes — their bounding boxes
are 2.5–3.3 mm at the narrow end — and the model builds a **"P"** and a collapsed
V *while still reporting the correct body count of 3*. Drop the R's counter by
centroid instead:

```python
cen = p.areaProperties().centroid
if bowl_x0 < cen.x*10 < bowl_x1 and bowl_y0 < cen.y*10 < bowl_y1:
    continue
```

**Table** — three rules 193 × 1.5 at Y −67.1 / −93.6 / −116.2, divider 1.0 × 49.1
at (−23.8, −91.65), seam 1.0 × 113 at (+68.5, −103.5). Fusion offers **21
profiles: 19 bars and 2 cells**; the bars merge into one body, top face
**1023 mm²**.

**Grid blocks** — X −8.3→5.2 and 16.8→30.3, Y −141→−127.6, 4 h-bars + 4 v-bars
at width 0.8, **inset so outer edges land on the stated outline** (h centres
−140.6 … −128.0 step 4.2; v centres x0+0.4 … x0+13.1). **75.8 mm² each** — the
regression tell. Bars centred *on* the outline overhang by 0.4 and give 80.3.

**Scale** — 30 ticks X −56.6 → −14.1 (spacing 42.5/29), baseline Y −146.7,
width 0.6, length 3.6 every fifth else 2.4.

**Legends** — "R" at (−69.5, −146.7), "IV" at (60.2, −146.7), 9.5 high, stroke
1.6. Verify by area: **R 42.1 · I 15.2 · V 27.9 mm²**.

**Waveform** — 14 bars width 0.8, X 34.0 → 62.0 (spacing 28/13), centred
Y −134.3. Not itemised in the PRD — carry as TBD-17.

### After every class

`app.activeDocument.save(...)`, confirm the running total, and at the end check
the whole timeline:

```python
[(i, des.timeline.item(i).name)
 for i in range(des.timeline.count)
 if des.timeline.item(i).entity is not None
 and int(des.timeline.item(i).entity.healthState) != 0]     # expect []
```

**Delete features by name, not by curve count.** A sketch matched on
`sketchLines.count` will eventually match the wrong one and leave a downstream
extrude on cached geometry, still reporting a healthy body count.

---

## 4 · CMF — configure all ten while unapplied, then assign

Writing a property on an **applied** appearance forks a copy. Create all ten from
one library source, set every property while nothing references them, assign last.

**The source is `Plastic - Glossy (Black)`, fetched from the material LIBRARY -
not from the document.** `des.appearances` holds only what the document already
uses, which on a fresh build is a steel or aluminium appearance. Copying one of
those gives you an appearance with **no `opaque_albedo` and no
`opaque_emission`**, and the canvas then renders every body **black** while
`surface_albedo` reads perfectly correct. That has happened; it looks exactly
like a lighting fault and is not one.

```python
lib = app.materialLibraries.itemByName('Fusion Appearance Library')
src = lib.appearances.itemByName('Plastic - Glossy (Black)')
REQ = ['surface_albedo','opaque_albedo','surface_roughness','opaque_f0',
       'opaque_emission','opaque_luminance','opaque_luminance_modifier']
missing = [i for i in REQ if src.appearanceProperties.itemById(i) is None]
assert src and not missing, f"bad source appearance, missing {missing}"
ap = des.appearances.addByCopy(src, name)          # x10
```

**Assert the seven ids on the source before the first copy.** A source missing
any of them cannot be fixed afterwards - the property does not exist to write.
Then set `surface_albedo` **and** `opaque_albedo` on every copy: one run wrote
only the first, the next wrote only the second, and both shipped wrong.

**Never assign a library appearance to a body.** All 289 bodies carry a `SLAB_*`
appearance created here. Picking the nearest-sounding stock material instead -
`Aluminum - Polished` for the knobs, `LED (Red)` for the indicators,
`Paint - Metallic (Dark Grey)` for the housing - leaves every body coloured and
every colour wrong, and no LED can glow because `opaque_emission` is never set.
It has happened twice. **Gate on it before assigning:**

Gate on the **name set**, not the count - see "Stage 4 is a gate" below. Ten
invented names carrying the `SLAB_` prefix pass a count check; one run shipped a
silver-and-green product that way. Zero means the section was skipped entirely
and the library was raided instead.

**Set `surface_albedo` and `opaque_albedo` together.**

### The exact names this stage needs

You write the code. What you must not do is *guess these strings* - six runs have
failed here, every one on a wrong identifier, never on design.

| What | The exact term |
|---|---|
| Material library | `app.materialLibraries.itemByName('Fusion Appearance Library')` |
| Source appearance | `.appearances.itemByName('Plastic - Glossy (Black)')` |
| Copy into the document | `des.appearances.addByCopy(src, name)` |
| Colour value | `adsk.core.Color.create(r, g, b, 255)` - the 4th arg is required |
| Read/write a property | `ap.appearanceProperties.itemById('<id>').value` |
| Scene exposure | `des.renderManager.sceneSettings` |

The **seven Prism property ids**: `surface_albedo`, `opaque_albedo`,
`surface_roughness`, `opaque_f0`, `opaque_emission`, `opaque_luminance`,
`opaque_luminance_modifier`.

**`app.materials`, `app.workspaces` and `des.renderSettings` do not exist.** An
`AttributeError` on those means the spelling is wrong, never that the bridge is
restricted. One run concluded "the execute_code bridge has restricted access",
fell back to the `set_appearance` tool and a plain `.color`, and shipped ten
appearances with no Prism ids set.

### Four rules that decide whether this stage works

**1 · Check the source before you copy it.** Assert all seven ids are present on
it first. `Steel - Satin` - the appearance a fresh document already carries - has
**no `opaque_albedo` and no `opaque_emission`**, so copies of it cannot hold a
colour the canvas can read, and the model renders **black** while
`surface_albedo` reads back perfectly correct. Guard against `None` from
`itemByName` before you dereference it.

**2 · Write `surface_albedo` AND `opaque_albedo` to the same value.** The
renderer reads the first, the canvas reads the second. One run wrote only one,
the next wrote only the other, and both shipped wrong.

**3 · Configure while unapplied, assign last.** Writing a property on an applied
appearance forks a duplicate; one session went 11 -> 14 -> 26 -> 15 -> 23.

**4 · Clear face overrides as you assign.** A face appearance beats the body
appearance, and `b.appearance = x` does not clear it.

### What goes where

**This table is keyed by COMPONENT, and the component names are not yours to
choose** - they come from the build stage and are already checksummed. Read a row,
apply that colour to that component's bodies. Do not route the lookup through the
appearance name, and do not match a component to an appearance because the two
strings look alike: `SLAB_Keypad` takes `SLAB_LED_Emissive`, and
`SLAB_Knob_Small` and `SLAB_Knob_Large` take **different** colours despite
sharing a prefix. Those are the two that get guessed wrong.

| Component | Bodies | Albedo | Rough | f0 | Appearance name |
|---|---|---|---|---|---|
| `SLAB_Housing_Upper` | 1 | **196,196,196** | 0.50 | 0.040 | `SLAB_Gray_Flat` |
| `SLAB_Housing_Base` | 5 | **48,48,50** | 0.38 | 0.055 | `SLAB_Black_Semi` |
| `SLAB_Panel_Control` | 1 | **78,78,82** | 0.60 | 0.042 | `SLAB_Panel_Dark` |
| `SLAB_Knob_Small` | 20 | **42,42,44** | 0.30 | 0.058 | `SLAB_Knob_Black` |
| `SLAB_Knob_Large` | 3 | **252,108,64** | 0.34 | 0.050 | `SLAB_Knob_Orange` |
| `SLAB_Keypad` | 10 | **255,122,48** | 0.26 | 0.050 | `SLAB_LED_Emissive` **+ emission** |
| `SLAB_Panel_Ticks` | 173 | **42,42,44** | 0.30 | 0.058 | `SLAB_Knob_Black` |
| `SLAB_Knob_Pointers` | 20 above Y 0 | **212,212,212** | 0.50 | 0.045 | `SLAB_Pointer_White` |
| `SLAB_Knob_Pointers` | 3 below Y 0 | **42,42,44** | 0.30 | 0.058 | `SLAB_Knob_Black` |
| `SLAB_Power_Switch` | 1, the taller | **200,200,200** | 0.35 | 0.050 | `SLAB_Toggle_Gray` |
| `SLAB_Power_Switch` | 1, the shorter | **255,122,48** | 0.26 | 0.050 | `SLAB_LED_Emissive` |
| `SLAB_LED_Indicators` | 1 | **252,108,64** | 0.34 | 0.050 | `SLAB_Knob_Orange` |
| `SLAB_Panel_Graphics` | 50 | **58,58,62** | 0.70 | 0.035 | `SLAB_Print_Ink` |
| *(none - defined, unused)* | 0 | **92,46,22** | 0.62 | 0.040 | `SLAB_Tick_Print` |

`SLAB_LED_Emissive` also carries `opaque_emission = True`,
`opaque_luminance = 150.0`, `opaque_luminance_modifier = (255,140,70)`.

**The ten appearance names in the last column are identifiers, not descriptions.**
The gate compares the name *set*, so `SLAB_Housing_Matte_Grey` fails even though
it reads better. Ten appearances, fourteen rows - `SLAB_Knob_Black`,
`SLAB_Knob_Orange` and `SLAB_LED_Emissive` each serve more than one row.

**Then look at the mockups** and say, one sentence per class, what colour you
actually see. Report any class more than ~25 per channel off the table - report
it, do not act on it. If the images did not arrive, say so and use the table.
**SLAB is orange on light grey**; silver knobs or green LEDs mean you are
describing a different product.

### Prove it before you leave this stage

Print one line per appearance - name, both albedo values, emission - and the
per-appearance body tally. The tally must be exactly:

```
SLAB_Gray_Flat 1 · SLAB_Black_Semi 5 · SLAB_Panel_Dark 1 · SLAB_Knob_Black 196
SLAB_Knob_Orange 4 · SLAB_LED_Emissive 11 · SLAB_Pointer_White 20
SLAB_Toggle_Gray 1 · SLAB_Print_Ink 50            total 289
```

`opaque_albedo` reading `None` means the wrong source - start over from the
library. `surface_albedo` reading (255,255,255) means only one id was written.

**Assignment touches every face of 289 bodies and will exceed the request
timeout while completing normally. Re-query the tally; do not retry.**

### Stage 4 is a gate. Do not open the Render workspace until it clears.

Colour is a **Design-workspace** problem and exposure is a **Render-workspace**
problem. Settle them in that order and never together - chasing both at once is
how a wrong albedo gets "fixed" with brightness, or a black frame gets blamed on
materials.

All four must hold before the workspace switch:

```python
EXP = {'SLAB_Gray_Flat','SLAB_Black_Semi','SLAB_Panel_Dark','SLAB_Knob_Black',
       'SLAB_Knob_Orange','SLAB_LED_Emissive','SLAB_Print_Ink',
       'SLAB_Pointer_White','SLAB_Toggle_Gray','SLAB_Tick_Print'}
got = {a.name for a in des.appearances if a.name.startswith('SLAB_')}
assert got == EXP, f"extra {got-EXP} / missing {EXP-got}"
assert all(b.appearance and b.appearance.name.startswith('SLAB_')
           for o in root.occurrences for b in o.component.bRepBodies)
```

3. A `render_view` capture has been compared against the mockups and every class
   reads as the right colour.
4. The keypad and power LED carry `opaque_emission = True`.

**Then, and only then, activate the Render workspace.** From that point colour is
frozen: everything after is exposure, camera and output. A dark render is
`brightness`, not the albedos - the Design canvas has its own lighting, so it
will look normal no matter how wrong the scene brightness is.

> This pass touches every face of 289 bodies and **can exceed the request timeout
> while completing normally**. Re-query the tally; do not retry.

---

## 5 · Verify cheaply

`render_view(view='top', fit=True)` costs a second and catches what no count can:
a filled region, a missing class, a letterform built wrong. Judge every layout
question on the orthographic top view.

Then the four implemented layout checks, knobs at their **widest** section:

| Check | Correct model |
|---|---|
| Pairwise knob gap ≥ 4.0 | **13.000 mm** |
| Knob vs pad clearance | **7.700 mm** |
| Panel inside the recess | **1.0 mm** all four sides |
| Pad inset from housing outline | **0.200 mm** |
| Pad-to-panel gap | **0.700 mm** |

Checks 5 and 6 are **not implemented**. Say so.

---

## 6 · Exposure — one pass

### Switching to the Render workspace is a required, visible step

**It is not setup for the render - it is part of the deliverable.** Someone is
watching this run happen on screen. The window changing to Render is how they see
the model reach the rendering stage, and a run that produces PNGs while the
Design window sits there has skipped something the operator specifically wants to
see.

It is also the easiest step to skip without consequence: every render tool works
on the active document regardless of what is displayed, so a full run can render
both finals, write both files and report success **while never leaving Design.**
That has happened. Nothing failed, because nothing checked.

```python
ui.workspaces.itemById('FusionRenderEnvironment').activate()
adsk.doEvents()
assert ui.activeWorkspace.id == 'FusionRenderEnvironment', ui.activeWorkspace.id
ss = des.renderManager.sceneSettings
ss.brightness = 1700.0
ss.cameraExposure = 9.5
print(f"STAGE 6 · workspace {ui.activeWorkspace.id}"
      f" · brightness {ss.brightness} · cameraExposure {ss.cameraExposure}")
```

**Print that line and do not fire a single render until it reads
`FusionRenderEnvironment` and `brightness 1700.0`.** Both numbers, every run.
Activating resets the viewport, so set the camera *after* this, never before.

Then one 256 px / quality 25 render.
Housing class **177–185 is converged** (measured 184.5).

> **Check `sceneSettings.cameraExposure` first — it must read 9.5.** It is a
> **second, inverse** exposure control (lower = brighter) that
> `set_scene_environment` never writes, and every lux figure here was derived at
> 9.5. If the document carries a different value, 1700 is void and you re-derive
> from scratch. Reach it with `execute_code` via `design.renderManager`.

For an exact matte, hide every occurrence, render the empty plate at identical
settings, and take `|render − plate| > 10`. The backdrop is perfectly uniform, so
this is exact. Do **not** key by colour distance.

---

## 7 · The two finals — pass `view='current'`

**Re-assert the workspace before each final.** `print(f"STAGE 7 · workspace "
f"{ui.activeWorkspace.id} · brightness {ss.brightness}")` - a quality-95 pass
costs ~2 minutes, and firing one from the Design workspace at default brightness
wastes it and produces a black frame that still writes a valid PNG.

**`start_render` defaults to `view='iso'` and applies its own camera, discarding
the live viewport camera.** The return payload states the view it used.

- **Hero:** perspective, azimuth 303°, elevation 46°, fov 14°, eye **d = 152 cm**
  from target (0, 0, 2.6 cm), up +Z. Height 1200, quality 95.
- **Plan:** orthographic, eye +Z, up +Y; `isFitView=True`, push, `vp.fit()`,
  re-read, `isFitView=False`, `viewExtents *= 1.10`, push. Height 1400, q95.

**Fusion rescales `eye` to preserve `viewExtents`** — 152 cm comes back as
247.6 cm. Push, read the achieved distance, scale `viewExtents` by
`(target/actual)²`, push again. Converges in one iteration.

`width` is discarded; output is `height × viewport aspect` unless you pin
`sceneSettings.aspectRatio`. Poll with `get_render_status`; never
`include_image=True`. Read the output path from the `start_render` payload — it
lives in a build-hash directory that changes on every Fusion update.

---

## 8 · Composite and measure

```bash
python scripts/composite.py hero_raw.png hero.png --aspect 1.328 --bloom-gains 0.10,0.055
python scripts/composite.py top_raw.png  top.png  --aspect 0.656 --plan --bloom-gains 0.08,0.04
```

Compare the **raw** render against the reference first. Accept on **both** halves:

| Test | Accept |
|---|---|
| LED pad **G:R** | 0.55 ± 0.03 |
| LED pad luminance | inside 144.0 – 160.5 (the plan reference measures 144.8) |
| Ten-pad connected components | exactly **10** blobs, spread ≤ 7 |
| Housing / dark luminance | inside the band the two references span - they disagree by 4.6 and 15.6 levels, so a midpoint matches neither. Outside the band is a **reported gap**, not a failure |

The G:R half is not optional: green clips first, so a blown pad reads 0.90 while
its luminance still looks fine. The ten-blob check is the only test that catches
a one-of-N defect; a correct model spreads 2–7 levels, the known defective one
spread 47.

Reference values, measured on the two mockups — they **disagree with each other**:

| | Hero mockup | Plan mockup |
|---|---|---|
| Housing | 174.9 | 179.5 |
| Dark | 43.4 | 27.8 |
| LED luminance | 159.0 | 144.8 |

Land inside the band and stop. Two finals per view; if the loop is still moving,
report the gap **with the number attached**.

---

## 9 · 2D output — views, sheet, then the drawing LAST

Hide the origin/sketch/construction folders on the root and every component, set
`WireframeWithVisibleEdgesOnlyVisualStyle`, capture top / front / right / iso at
one shared `viewExtents = 38.0`, target (0, 0, 3.06), then **restore
`ShadedVisualStyle`**.

```bash
python scripts/make_views.py --dir ./views --target-z 30.6 \
    --bbox=-99.52,97.52,-170.02,170.02,-0.03,61.18
python scripts/make_drawing.py scripts/slab_sheet.json -o SLAB_GA_RevC.pdf --views-dir ./views
pdftoppm -jpeg -r 115 SLAB_GA_RevC.pdf sheet_check
```

Expect crop-aspect error **≤ 0.11 %** per view. Over 1 % means a clipped capture.
Rasterise the sheet and look at the whole page.

Then, as the **final Fusion action**:

```
create_drawing(sheet_size='A3ISO', standard='ISO', units='mm',
               center_marks=False, open_drawing=True)
```

It **exceeds the request timeout while succeeding** — returns `Request timed out`
and silences `ping` for ~45 s. **`fusion-2d-drawings` §3 owns this procedure;
follow it there, not here.** In short: do not retry, do not poll, wait, then
confirm with
`get_design_type`: the `'Drawing' object has no attribute 'designType'` error
**is the proof it worked**. Note in the report that a human must click the
Design tab to reuse the model; do not ask for it, and do not wait for it. The run
finishes at stage 10 regardless.

**Never call `export_drawing_pdf`** — it opens a modal and hangs the MCP server.

---

## 10 · Report

Written outside Fusion. In order:

1. **Governing constraint with its arithmetic.** Enclosure top Z 46.000, tallest
   feature Z 61.180, so `46.000 − 61.180 = −15.180` against a required
   `≥ +2.000` — shortfall **17.180 mm**. Ruled on by DEC-C3. Report the
   arithmetic; do not flag it as blocking.
2. Change log, one row per edit with its basis.
3. Conformance findings, each naming **which source was wrong**.
4. New open decisions with owners.

**Do not re-raise DEC-C1 … DEC-C7.** Long axis is Y; 20 pots governs; no bezel;
no connector aperture crosses Z 23.0; power toggle Y = +130.0; the pads are lit
buttons; the dividers run downward.

Carry forward as open: zero named parameters (TBD-14); no shaft holes in the
panel (TBD-15); rear I/O plate and bay not built (TBD-13); orange panel speckle
and in-panel legend text not modelled; draft analysis not run; boss positions
predate the axis correction (TBD-16); layout checks 5 and 6 not implemented; the
waveform graphic not itemised in the PRD (TBD-17).

---

## Gate script

```python
CMF={'SLAB_Gray_Flat':((196,196,196),0.50,0.040),'SLAB_Black_Semi':((48,48,50),0.38,0.055),
'SLAB_Panel_Dark':((78,78,82),0.60,0.042),'SLAB_Knob_Black':((42,42,44),0.30,0.058),
'SLAB_Knob_Orange':((252,108,64),0.34,0.050),'SLAB_LED_Emissive':((255,122,48),0.26,0.050),
'SLAB_Print_Ink':((58,58,62),0.70,0.035),'SLAB_Pointer_White':((212,212,212),0.50,0.045),
'SLAB_Toggle_Gray':((200,200,200),0.35,0.050),'SLAB_Tick_Print':((92,46,22),0.62,0.040)}
root=design.rootComponent
comps={o.component.name:o.component for o in root.occurrences}
G={}
G['G1_bodies']=[sum(c.bRepBodies.count for c in comps.values()),289]
G['G2_components']=[len(comps)+1,12]
def chk(ap):
    if ap is None or ap.name not in CMF: return None
    P=ap.appearanceProperties
    sa=P.itemById('surface_albedo').value; oa=P.itemById('opaque_albedo').value
    r=P.itemById('surface_roughness').value; f=P.itemById('opaque_f0').value
    c,rr,ff=CMF[ap.name]
    ok=((sa.red,sa.green,sa.blue)==c and (oa.red,oa.green,oa.blue)==c
        and abs(r-rr)<=0.005 and abs(f-ff)<=0.003)
    return None if ok else [ap.name,(sa.red,sa.green,sa.blue),(oa.red,oa.green,oa.blue)]
bad=[]; unnamed=[]; overrides=[]
for cn,c in comps.items():
    for b in c.bRepBodies:
        ba=b.appearance.name if b.appearance else None
        if ba is None: unnamed.append(cn+'/'+b.name)
        else:
            r=chk(b.appearance)
            if r: bad.append(['body',cn,b.name]+r)
        for f in b.faces:
            if f.appearance:
                if ba and f.appearance.name!=ba: overrides.append([cn,b.name,f.appearance.name])
                r=chk(f.appearance)
                if r: bad.append(['face',cn,b.name]+r)
G['G3_resolved_mismatches']=[len(bad),0,bad[:5]]
G['G3_bodies_without_appearance']=[len(unnamed),0]
G['G3_stray_face_overrides']=[len(overrides),0]
n=0
for cn in ('SLAB_Housing_Upper','SLAB_Housing_Base'):
    if cn not in comps: continue
    for b in comps[cn].bRepBodies:
        for f in b.faces:
            g=f.geometry
            if g.surfaceType==1 and abs(abs(g.axis.y)-1.0)<0.01: n+=1   # 1=Cylinder (3 is Sphere, and has no .axis)
G['G5_DECC4_wall_apertures']=[n,0]
ks=comps.get('SLAB_Knob_Small')
if ks and ks.bRepBodies.count:
    G['G6_small_knob_faces']=[sorted(set(b.faces.count for b in ks.bRepBodies)),[4]]
    rad=sorted([[round(e.geometry.center.z*10,2),round(e.geometry.radius*10,3)]
                for e in ks.bRepBodies.item(0).edges
                if e.geometry.objectType=='adsk::core::Circle3D'])
    G['G6_radii']=[rad,[[45.6,6.75],[60.42,5.454],[61.1,4.707]]]
    G['G6_taper_decreases']=[all(rad[i][1]>=rad[i+1][1] for i in range(len(rad)-1)),True]
gt=None; oth=0
for b in (comps['SLAB_Panel_Graphics'].bRepBodies if 'SLAB_Panel_Graphics' in comps else []):
    a=max([f.area*100 for f in b.faces
           if f.geometry.surfaceType==0 and abs(f.geometry.normal.z)>0.99]+[0])
    if b.name=='Gfx_Table': gt=round(a,1)
    else: oth=max(oth,a)
G['G7_Gfx_Table_face_mm2']=[gt,'1023 +/- 10']
G['G7_max_other_graphic_mm2']=[round(oth,1),'75.8 = a correctly inset grid block']
ps=comps.get('SLAB_Power_Switch')
if ps and ps.bRepBodies.count:
    tb=max(ps.bRepBodies,key=lambda b:b.volume).boundingBox
    G['G8_toggle_bbox']=[[round(v*10,1) for v in (tb.minPoint.x,tb.minPoint.y,tb.minPoint.z,
                          tb.maxPoint.x,tb.maxPoint.y,tb.maxPoint.z)],
                         [-99.5,124.5,44.2,-88.5,135.5,59.0]]
G
```

G3 resolves appearances **through the bodies that carry them** rather than by
name, because a body and its own face overrides can resolve to two different
duplicates of one name.

---

## Time budget

| Stage | Cold | Warm |
|---|---|---|
| Save + gate | 2 min | 2 min |
| Build (12 classes) | ~20 min | 0 |
| CMF | ~3 min | 0 |
| Exposure | 1 pass, ~15 s | ~15 s |
| Two finals | ~4 min | ~4 min |
| Composite | ~10 s | ~10 s |
| Views + sheet + drawing | ~3 min | ~3 min |

Cold build to delivered drawing: **~45 min**. Warm: **~10 min**.

