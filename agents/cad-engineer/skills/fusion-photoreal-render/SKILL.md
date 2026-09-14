---
name: "fusion-photoreal-render"
description: "How to produce a calibrated photoreal render from Fusion's local raytracer - activate Render visibly, pin exposure in one pass, set a camera that holds its distance, render with view='current', and stop on a two-part numeric criterion. Covers the second (inverse) exposure control, the aspectRatio frame lock, and the one scene write that kills the MCP server. Use when producing a product render or matching a render to a reference."
---

# Calibrated photoreal rendering in Fusion 360

The render loop, in the order that converges: **workspace → exposure → camera →
finals → composite → measure.** Stop on a number rather than on appearance.

**CMF comes first and is finished before you get here.** `slab-run` stage 4 owns
colour and closes before the Render workspace opens; this file owns exposure.
"Pin exposure before touching materials" applies *within* the render stage - if a
frame is wrong, fix brightness before you suspect an albedo - not to the run
order.

**Precedence.** Supersedes `fusion-product-design:fusion-photoreal-render`.
Verified on Fusion build 2705.1.11, 11 September 2026.

---

## 1 · Activate the Render workspace, visibly

Every render tool works on the active document regardless of what is on screen,
so a whole run can complete with the Design window showing and no sign that
anything happened. Switch first, and assert:

```python
ui.workspaces.itemById('FusionRenderEnvironment').activate()
adsk.doEvents()
assert ui.activeWorkspace.id == 'FusionRenderEnvironment', ui.activeWorkspace.id
print(f"WORKSPACE · {ui.activeWorkspace.id}")
```

**Print that line. It is the only evidence the switch happened**, and a run that
skips it leaves nothing behind either way. One run rendered both finals, wrote
both files, reported success, and finished in `FusionSolidEnvironment` - it had
never switched at all. Nothing failed, because nothing checks.

`ui.activeWorkspace.id` is the test. `products.itemByProductType(
'RenderingProductType')` returns `3 : failed to find product` even when the
switch worked, so it tells you nothing.

**Activating resets the viewport.** Measured 1693×671 in one session, 804 → 684
in another. So: activate **first**, set the camera **second**, and re-read
`vp.width / vp.height` immediately before each render.

---

## 2 · Pin exposure in one pass

Exposure is a property of the **document**, not of the product — the same
product with byte-identical CMF needed 22000 lux in one document and **1700** in
a from-scratch rebuild of the same model. Derive it every run, and do not debug
materials until it is pinned.

### Set brightness explicitly, then read it back. Every run.

**A fresh document defaults to `brightness = 1.2`** — measured at exactly
1.2000000476837158 in two unrelated documents. At that value the model renders as
a **pure black silhouette against a correctly-lit background**: a SolidColor
background is painted rather than lit, so it survives at full strength while the
model receives no light at all. The Design canvas has its own lighting and looks
perfectly normal, so nothing reveals this until the Render workspace opens.

**Two runs have shipped a black hero this way, and in neither case had the model
written brightness at all.** It is not a unit mistake. It is a write that never
happened, because "start at 1700" reads like a default rather than an action.

So stage 6 begins with three lines, not one:

`sceneSettings` is reached at **`des.renderManager.sceneSettings`**. There is no
`des.renderSettings`; guessing that name and getting `AttributeError` does not
mean the build lacks exposure control. **Never set exposure through
`set_scene_environment` with a number you invented** - that wrapper writes only
`brightness` and cannot write `cameraExposure` at all.

```python
ss = des.renderManager.sceneSettings
ss.brightness = 1700.0
ss.cameraExposure = 9.5
assert ss.brightness >= 1200, f"brightness {ss.brightness} - below the 1200-22000 band"
assert ss.cameraExposure == 9.5, f"cameraExposure {ss.cameraExposure} - reset it"
print(f"EXPOSURE · workspace {app.userInterface.activeWorkspace.id}"
      f" · brightness {ss.brightness} · cameraExposure {ss.cameraExposure}")
```

**Print that line before any render, and do not tune by eye.** A run that skipped
it walked `brightness` 0.7 -> 1.5 -> 3.0 -> 5.0 -> 8.0 across six render passes,
each one still black, and finally concluded that "matte black PBR materials
absorbing light is expected behaviour." It was three orders of magnitude short
the whole time. **If the frame is dark and `brightness` is a single- or
double-digit number, you have the wrong scale - do not keep doubling it.**

That same run moved `cameraExposure` from 9.5 to **12.0** while trying to
brighten. It is **inverse**: raising it makes the image darker. Turning both
controls at once means neither reading tells you anything. Set it to 9.5, assert
it, and leave it.

`brightness` is photometric — **lux, not a gain**. The working band is
**1200–22000**; it is not a 0–2 multiplier. **Anything below 100 means the scene
was never configured.** Read it back before every render pass, not just the first:
`cameraExposure` must read 9.5 at the same time.

Then fire one 256 px, quality 25 pass (**~2-3 s**; the 15 s figure elsewhere included setup).
Measure the housing class — the largest, most stable class in frame. **183–185 is converged** (the wider 177–185
band is the ladder's row for neighbouring lux values). Measured on a clean run: **184.5**. That is the expected outcome
in a fresh document and it is usually the whole calibration.

If it misses by more than ~5 levels, bracket with this ladder. The response is
steeply non-linear — ~23 levels per decade at the top, ~137 per decade between
1200 and 3000 — so bracket, never extrapolate:

| brightness | housing | emissive pads |
|---|---|---|
| 22000 | 233 | blown to yellow, G:R 0.93 |
| 12000 | 227 | lum 211, G:R 0.82 |
| 3000 | 213 | lum 166, G:R 0.58 |
| **1700** | **183–185** | **lum 152–160, G:R 0.52–0.56** |
| 1200 | 159 | lum 140, G:R 0.50 |

After **any** change to brightness, re-fire the 256 px test before changing
anything else.

**Emissive luminance is absolute and belongs to the exposure it was derived at.**
For a lit orange button, `opaque_luminance = 150.0` with
`opaque_luminance_modifier = (255, 140, 70)` is confirmed at the calibrated
exposure: it renders the pads at rgb (251.7, 141.8, 64.7), **G:R 0.564**.
Re-derive it whenever brightness changes.

Fusion renders emissive faces as flat colour with **no spill and no halo**. Add
the glow in post; the compositor's bloom pass does this.

### There are TWO exposure controls, and the second one runs backwards

`sceneSettings.cameraExposure` is a **separate control from `brightness`**, and
`set_scene_environment` does not write it. It defaults to **9.5** and it is
**inverse — lower is brighter**, like a photographic stop, and nothing in the
property name says so. Measured: 9.5 → 11.0 visibly darkened and flattened the
whole frame.

**Every lux figure in this file was derived at `cameraExposure` 9.5.** Read it
before trusting them. Tune `brightness` and leave `cameraExposure` alone unless
you need a large move — two knobs on one setting means turning both at once
tells you nothing about either. Move it and every brightness number here is void
and you re-derive from scratch.

### `set_scene_environment` is a thin wrapper, not the surface

It writes `brightness` and returns
`unsupported: ['ground_plane','ground_reflections','background']`. Those
settings are **not** unavailable in Fusion — they are unavailable *through that
wrapper*. The real surface is `renderManager.sceneSettings`, reached with
`execute_code`, and it exposes the whole scene: `cameraExposure`, `lightAngle`,
`backgroundSolidColor`, `isGroundDisplayed`, `isGroundReflections`,
`groundRoughness`, `aspectRatio`, `cameraFocalLength`.

Reporting the wrapper's gap as a Fusion limitation is a false statement — say
which one you mean.

Write scene properties **one per call**, on a saved document, with a liveness
probe between each. Batching eight writes took the MCP process down once.

> **`backgroundEnvironment` is a fatal write.** Assigned while `backgroundType`
> is SolidColor it does not raise — it kills the process:
> `[WinError 10054] An existing connection was forcibly closed by the remote
> host`, after which `ping` reports not connected. `backgroundType` itself is
> **read-only**, so Environment mode is unreachable from the API at all and
> needs a manual GUI change. Never assign `backgroundEnvironment`.

---

## 3 · Measure with a rendered plate, not a colour guess

Because the API cannot enable a ground plane, the backdrop renders **perfectly
uniform** — measured std 0.000 at rgb (178,178,178). Exploit that. Two exact
mattes:

1. **Difference matte.** Hide every occurrence, render the empty plate at
   identical settings, unhide, and take `|render − plate| > 10` as the subject.
   One extra 2 s render, zero tolerance tuning, and it gives an exact class
   split even where the subject and plate are within a few levels.
   ```python
   for o in root.occurrences: o.isLightBulbOn = False
   # render bg
   for o in root.occurrences: o.isLightBulbOn = True
   ```
2. **Border flood-fill** — connectivity from the frame edge over pixels within
   ~6 of the **modal** frame colour. This is what `composite.py` does.

Use connectivity or a rendered plate, **not colour distance**: at a correct
exposure the grey housing sits within ~8 levels of the plate, so a distance ramp
gives it alpha ≈ 0.55 and the product composites half-transparent.

---

## 4 · Set a camera that holds its distance

`vp` is **not** pre-bound: `vp = app.activeViewport`, and `cam = vp.camera`.
Only `app, ui, design, component, adsk, math` are bound - `Point3D` and
`Vector3D` need their `adsk.core.` prefix, and trig needs `math.`.


**Fusion rescales `eye` to preserve `viewExtents`.** A perspective camera
requested 152 cm from its target comes back at 247.6 cm — direction preserved
exactly, a pure 1.629× scaling. Correct it by the square of the ratio and push
again; it converges in one iteration:

```python
def place(d, ve=None):
    cam = vp.camera
    cam.cameraType = adsk.core.CameraTypes.PerspectiveCameraType
    cam.target = TGT
    cam.eye = adsk.core.Point3D.create(*[TGT[i] + d*u[i] for i in range(3)])
    cam.upVector = adsk.core.Vector3D.create(0, 0, 1)
    cam.perspectiveAngle = math.radians(FOV)
    cam.isFitView = False
    if ve is not None: cam.viewExtents = ve
    vp.camera = cam; adsk.doEvents()
    c = vp.camera
    return c.eye.distanceTo(c.target), c.viewExtents

dist, ve = place(D)
for _ in range(4):                      # converges in 1; 4 is the hard cap
    if abs(dist - D) <= 0.05:
        break
    ve = ve * (D/dist)**2
    dist, ve = place(D, ve)
else:
    raise RuntimeError(f"camera distance did not converge: {dist:.2f} vs {D}")
```

A property set on a camera object you have not yet pushed is ignored. Always
push, re-read, correct, push.

**Three-quarter hero** — azimuth 303°, elevation 46°, fov **14°** (telephoto;
this is what gives the reference's compression), eye at **d = 152 cm** from a
target at (0, 0, 2.6 cm), up +Z.

```python
u = (math.cos(el)*math.cos(az), math.cos(el)*math.sin(az), math.sin(el))
```

**Orthographic plan** — eye +Z, up +Y, `isFitView = True`, push, `vp.fit()`,
then re-read, set `isFitView = False`, `viewExtents *= 1.10`, push again.

---

## 5 · Render the finals — pass `view='current'`

**`start_render` defaults to `view='iso'` and applies its own camera preset,
discarding the live viewport camera.** Everything in §4 only reaches the
raytracer when `view='current'` is passed. The return payload states the view it
used — read it; a "plan" job that comes back reporting `view: iso` has rendered a
three-quarter view of a top-down camera setup.

```
start_render(height=1200, quality=95, view='current', filename='hero_raw')
start_render(height=1400, quality=95, view='current', filename='top_raw')
```

`width` is discarded — **but the frame is still yours.** It is governed by
`sceneSettings.aspectRatio`, which defaults to `CurrentViewportRenderAspectRatio`,
which is why output otherwise tracks the viewport (1693×671 → `height=1200`
writes 3030×1200). Set it and the frame is pinned:

```python
rm = design.renderManager                      # via execute_code
rm.sceneSettings.aspectRatio = 1               # Square1to1 -> height x height
```

Members: `CurrentViewport` **0**, `Square1to1` **1**, `Presentation4to3` **2**,
`Widescreen16to9` **3**, `Landscape5to4` **4**, `Portrait4to5` **5**,
`Custom` **6**. `Square1to1` + `height=1100` wrote exactly **1100 × 1100**.

Leaving it at `CurrentViewport` and letting the compositor crop to the reference
aspect also works, and is what the SLAB run did. Either is fine — but **a run
that says the frame cannot be controlled has quoted a retired finding.** State
the actual pixel dimensions read off the file on disk.

### Polling — read `elapsed_seconds`, not `progress_percent`

**`progress_percent` reports only 0 / 50 / 100.** Queued is 0, processing is 50,
finished is 100. **50 does not mean half done** — it means "running", and it will
sit at 50.0 for the entire render. A model watching that number concludes the job
has hung. It has not.

**`elapsed_seconds` is the only field that moves.** Poll on it.

The protocol:

1. `start_render(...)` returns a `job_id`. Note it.
2. **Wait before the first poll** — `sleep 30` in the terminal, or any other
   real work. Polling immediately just burns a turn.
3. `get_render_status(job_id)`. If `state` is `queued` or `processing`, wait
   again and re-poll. **Never** pass `include_image=True` — 138k characters for
   one frame.
4. `state: finished` with `file_written: True` and non-zero `bytes` is the only
   success condition. Then `Read` the PNG off disk at the returned `path`.
5. If `elapsed_seconds` passes **3× the expected duration** below, stop polling
   and report the elapsed time. Do not fire a second render.

**Call `get_render_status` with no `job_id` to see the whole queue.** That is how
you find out a job is `queued` behind something else rather than stalled.

### Write renders to a local folder, never a synced one

`start_render(filename=...)` decides where the PNG lands. Point it at a **local,
non-synced** directory — `FUSION_OUTPUT_DIR` from `.env_template`, default
`~/fusion-renders`. A 450 KB PNG written into a OneDrive- or Dropbox-synced
project folder triggers a sync on every frame, slows the write, and drops build
artefacts into the repo. The composited finals get copied into `renders/`
deliberately at the end; the raws do not belong there.

### Renders queue strictly one at a time

A second `start_render` while one is `processing` sits at `queued` until the
first finishes, and adds its own duration on top. **Never fire a render to
"check on" a render** — poll the queue instead. There is no cancel tool; a
queued job must run.

### Expected duration

Roughly proportional to `height × quality`. Measured on this machine:

| height | quality | duration |
|---|---|---|
| 256 | 25 | **~2–3 s** — the exposure probe |
| 900 | 80 | ~40–60 s |
| 1200 | 95 | **~135 s** |
| 1400 | 95 | **~110 s** |

**Do not exceed height 1400 at quality 95** for a deliverable. A larger frame is
not a better render — it is the same image with more samples, and it scales past
ten minutes fast. The composite crops to the reference aspect anyway, so extra
pixels are discarded.

If you need to know a render is progressing rather than hung: `elapsed_seconds`
rising with `state: processing` is progress. That is the whole signal.

### Cost ladder — use the cheapest tool that can answer the question

| Question | Use | Cost |
|---|---|---|
| Bodies present, materials plausible, layout right | `render_view(view='top'/'iso', fit=True)` | ~1 s |
| Exposure confirmation | one 256 px, quality 25 pass | ~15 s |
| Deliverables | quality 95 | ~110–135 s |

**Judge every layout question on an orthographic top view.** In a perspective
hero, repeated radial features foreshorten into what looks like scatter — a
"ticks are scattered" defect was raised on exactly that misreading and later
withdrawn. And a one-second viewport capture catches most build defects: a
filled region, a dark panel, a letterform built wrong.

---

## 6 · Composite once

Compare the **raw** render against the reference **first**. Grading first makes
the loop converge on post settings while the materials stay wrong.

```bash
python scripts/composite.py hero_raw.png hero.png --aspect 1.328 --bloom-gains 0.10,0.055
python scripts/composite.py top_raw.png  top.png  --aspect 0.656 --plan --bloom-gains 0.08,0.04
```

Everything is a flag — do not edit the script. `--plan` swaps the squashed
contact shadow for a plain offset-and-blur, which is what an orthographic view
needs; a squashed matte smears across the middle of a top view because there is
no floor to squash onto. Runs in 3–5 s.

---

## 7 · Stop on a two-part criterion

| Test | Accept |
|---|---|
| Emissive **G:R** | **0.55 ± 0.03** |
| Emissive luminance | inside the reference band |
| Connected components across N repeated lit features | exactly **N** blobs, per-channel spread **≤ 7 levels** |
| Housing and dark luminance | inside the band the two references span, **not** a midpoint - they disagree by 4.6 and 15.6 levels. Measured 185.5 against references 174.9 / 179.5 is a **reported gap, not a failure**; do not chase it |

**The G:R half is not optional.** The green channel clips first, so a blown
emissive reads G:R **0.90** while its luminance still looks plausible —
luminance alone will accept it, and an eight-pass loop once converged on exactly
that.

**Always run the connected-component check on repeated lit features.** It is the
only test that catches a one-of-N defect such as a dead pad from a stray face
override. A correct model measures a per-channel spread of 2–7 levels across ten
pads; the known defective one measured 47. The same blob pass separates emissive
pads from reflective coloured knobs — split at the midpoint of the blob G:R
range, since pads land high (≈0.56) and reflective orange low (≈0.41) — so you
compare pads to pads.

Mask before measuring: legend text where the reference is AI-generated and its
text is nonsense, and anything the spec lists as not modelled.

**Expect the references to disagree with each other.** Two mockups of the same
product measured housing 174.9 vs 179.5 and dark 43.4 vs 27.8 — a 15.6-level
spread on the dark class. Converging on the midpoint moves you toward one and
away from the other. Land inside the band and stop.

**Budget two finals per view.** If the loop is still moving after that, stop and
report the gap **with the number attached**. A representative honest outcome:
housing 185.5 against references of 174.9 / 179.5, reported as a finding rather
than chased, because lowering exposure would have worsened an already-dark shadow
class and pulled the emissives off an independently confirmed calibration. An
open-ended render loop is the easiest place in this workflow to burn an hour with
nothing to show.

