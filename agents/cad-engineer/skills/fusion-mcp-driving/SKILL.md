---
name: "fusion-mcp-driving"
description: "How to drive a live Fusion 360 session through the fusion360 MCP - the call signatures that work, the arguments that must be passed explicitly, how to set a camera that holds, how to work the appearance API, the one scene write that kills the server, and the verification that proves each call landed. Use whenever calling any mcp__fusion360__ tool."
---

# Driving Fusion 360 through the fusion360 MCP

~110 tools operating on a **live Fusion GUI**. This is how to use them so each
call does what you meant, and how to prove it did.

**Precedence.** Supersedes `fusion-product-design:fusion-mcp-driving` on every
call signature and method it states. Verified on build 2705.1.11
(`a40f190f24413dd1bb4f1434f056c1379a3b5224`), 11 September 2026.

---

## 1 · Pass the arguments that actually steer the tool

Several tools have a parameter that selects between "use what I set up" and "use
my own preset", and the default is the preset. Pass these explicitly.

| Tool | Pass | Because |
|---|---|---|
| **`start_render`** | **`view='current'`** | The default is `view='iso'`, which applies the tool's own camera and discards the live viewport camera entirely. Every calibrated camera recipe depends on this argument. |
| `start_render` | `height` only | `width` is discarded; output is `height × live viewport aspect`. Measured: viewport 1693×671 → aspect 2.5231 → `height=1200` writes 3030×1200. Re-read `vp.width/vp.height` before each render. |
| `get_render_status` | `job_id` alone | `include_image=True` returns 138k characters for one frame. `Read` the PNG off disk instead. |
| `create_drawing` | `sheet_size='A3ISO'`, `center_marks=False` | `sheet_size` needs the full enum stem, not `A3`. `center_marks=True` raises `CenterMarkDisplayTypes not available in this Fusion build`. A bare `create_drawing()` cannot succeed. |
| `set_scene_environment` | `brightness` | It applies `brightness` and returns `unsupported` for `ground_plane`, `ground_reflections` and `background`. Read the `unsupported` list in the success payload. |

**Every tool states in its return payload what it actually did.** `start_render`
reports the `view` it used; `set_scene_environment` reports what it applied and
what it ignored. Read the payload, not just the `OK`.

**`set_scene_environment` is a thin wrapper, not the scene surface.** The three
settings it reports `unsupported` are not unavailable in Fusion — they are
unavailable *through that wrapper*. `renderManager.sceneSettings`, reached with
`execute_code`, exposes the whole scene: `cameraExposure` (a second, **inverse**
exposure control — lower is brighter, default 9.5, and the wrapper never writes
it), `lightAngle`, `backgroundSolidColor`, `isGroundDisplayed`,
`isGroundReflections`, `groundRoughness`, `aspectRatio`, `cameraFocalLength`.
Write them one per call on a saved document, with a liveness probe between —
batching eight writes took the MCP process down once.

> **`backgroundEnvironment` is the one fatal write.** Assigned while
> `backgroundType` is SolidColor it does not raise — it kills the process
> (`[WinError 10054] An existing connection was forcibly closed by the remote
> host`) and `ping` then reports not connected. `backgroundType` itself is
> **read-only**. Never assign `backgroundEnvironment`.

**The render frame is controllable.** `start_render` discards `width`, but
`sceneSettings.aspectRatio` governs the output shape — it defaults to
`CurrentViewport` (**0**), which is why output otherwise tracks the viewport.
`Square1to1` is **1**, then `Presentation4to3` 2, `Widescreen16to9` 3,
`Landscape5to4` 4, `Portrait4to5` 5, `Custom` 6.

Two more worth knowing so you do not spend a cycle on them:

- `start_render(transparent_background=True)` writes correct RGB with alpha
  uniformly 0. Key the plate instead — see §5.
- `Color.create(r, g, b, 0)` stores and reads back `opacity=0`, and the
  raytracer ignores alpha on albedo. Pass `255`.

---

## 2 · `execute_code` is the real API surface

The typed tools cover perhaps a third of a build. `execute_code` gives the whole
Fusion Python API with `app`, `ui`, `design`, `adsk`, `math` pre-bound, and
**returns the last expression REPL-style**. Return a dict of the measurements
that prove the call worked, and read them on the way past:

```python
{'vol_after_shell': round(b.volume, 3), 'target': 219.09,
 'faces': b.faces.count, 'bodies': c.bRepBodies.count}
```

**It also returns free assertions.** Every call reports `body_count`, `mass_g`
and before/after bounding-box deltas. Use them as the first check:

| Operation | Expected signature |
|---|---|
| Fillet 23 knob top edges | `body_count 0`, `mass −2.106 g`, **bbox unchanged** |
| Rebuild 20 knobs | `body_count +20`, bbox Z max 6.063 → 6.113 |
| Flip an extrude taper | `body_count 0`, **mass unchanged** |

That last row is the principle: **a gate is blind to any defect its own quantity
cannot see.** A frustum's volume is symmetric in R and r, so choose a quantity
that can see the thing you changed. For a taper, read the circular edge radii
against Z — radius must decrease as Z increases on a knob:

```python
sorted([(round(e.geometry.center.z, 3), round(e.geometry.radius, 4))
        for e in b.edges
        if e.geometry.objectType == adsk.core.Circle3D.classType()], reverse=True)
```

The bbox instrumentation carries a ±0.03 mm pad, so a body sitting exactly on
Z 0 reports −0.003 cm. Expect it and do not chase it.

### Scope each call to one logical operation — and read state before retrying

Long operations can exceed the MCP request timeout **while completing
normally**. Deleting 40 bodies from a 440-feature tree returned
`Error: Request timed out` and had finished. A 289-body appearance pass did the
same and had finished. So on a timeout:

```python
# re-query FIRST; never blind-retry a non-idempotent call
[(o.name, o.component.bRepBodies.count) for o in design.rootComponent.occurrences]
```

Keep each call to one logical operation, and never batch a parameter edit with
deletes and a rebuild — that combination is what produces the timeout in the
first place. (Cold builds batch differently; see `fusion-scratch-build`.)

---

## 3 · Cameras: push, read back, correct, push again

**A camera property assigned to a camera object you have not yet pushed to the
viewport is ignored.** The pattern that works everywhere:

```python
cam = vp.camera            # take a copy
... set properties ...
vp.camera = cam            # push
adsk.doEvents()
cam2 = vp.camera           # read back what Fusion actually did
```

**Fusion rescales `eye` to preserve `viewExtents`.** Requesting a perspective
camera 152 cm from its target gives back 247.6 cm — direction preserved
exactly, a pure 1.629× scaling. To hold a chosen distance, correct `viewExtents`
by the square of the ratio and push again. It converges in one iteration:

```python
dist, ve = place(D)
for _ in range(4):                      # hard cap; converges in 1
    if abs(dist - D) <= 0.05: break
    ve = ve * (D/dist)**2
    dist, ve = place(D, ve)
```

For an orthographic view: set `isFitView = True`, push, call `vp.fit()`, then
re-read the camera, set `isFitView = False` and scale `viewExtents`, and push
again.

---

## 4 · Appearances

Full Autodesk Standard Surface. See `fusion-product-design`'s
`reference/appearance-api.md` for property ids; the working method is here.

**Resolve by iteration, never `itemByName`.** Duplicate names are normal and
`itemByName` returns the first match, so half the edits silently miss:

```python
hits = [aps.item(i) for i in range(aps.count) if aps.item(i).name == target]
assert len(hits) == 1, f'{target} resolved to {len(hits)}'
```

**Configure while unapplied, then assign.** Writing a property on an applied
appearance forks a local copy — one session reached 167 appearances, 156 of them
duplicates of a single emissive material. So: create all appearances from a
library source with `des.appearances.addByCopy(src, name)`, set every property
while nothing references them, and assign to bodies last.

Pick the source by capability, not by name: filter the Fusion Appearance Library
for one exposing all of `surface_albedo, opaque_albedo, surface_roughness,
opaque_f0, opaque_emission, opaque_luminance, opaque_luminance_modifier`.
`Plastic - Glossy (Black)` works; 85 candidates qualify.

**Set `surface_albedo` and `opaque_albedo` together.** The renderer reads
`surface_albedo`; writing only `opaque_albedo` leaves a stale colour that no
geometric checksum can see.

**Clear face-level overrides explicitly.** A face appearance beats the body
appearance and `b.appearance = x` does not touch it:

```python
def assign(b, ap):
    for f in b.faces:
        if f.appearance is not None and f.appearance.name != ap.name:
            f.appearance = ap
    b.appearance = ap
```

Audit afterwards, resolving **through the bodies** rather than by name — that is
what catches a body and its own face overrides pointing at two different
duplicates of one name:

```python
for occ in root.occurrences:
    for b in occ.component.bRepBodies:
        ba = b.appearance.name if b.appearance else None
        for i, f in enumerate(b.faces):
            if f.appearance and f.appearance.name != ba:
                print(occ.name, b.name, i, f.appearance.name)
```

**One appearance per optical behaviour, not per colour.** A single orange
material driving both emissive LEDs and printed tick marks turns the ticks into
confetti the moment the LEDs are made to glow.

Face-level appearance is useful **on purpose**: select pocket floors by exact Z
and assign a dark matte ink, and engraved silkscreen reads as printed with zero
geometry change.

---

## 5 · Measuring a render

The API cannot enable a ground plane, so the backdrop renders **perfectly
uniform** — measured std 0.000 at rgb (178,178,178). Two exact ways to separate
subject from plate:

1. **Difference matte.** Hide every occurrence (`o.isLightBulbOn = False`),
   render the empty plate at identical settings, unhide, and take
   `|render − plate| > 10`. One extra 2 s render, no tolerance tuning.
2. **Border flood-fill.** Connectivity from the frame edge over pixels within
   ~6 of the **modal** frame colour.

Use connectivity or a rendered plate — **not colour distance**. At a correctly
derived exposure a grey housing sits within ~8 levels of the plate, so a
distance ramp keys the product half-transparent.

Then measure the pixels. Eyeballing a render produces wrong diagnoses; a
connected-component analysis of repeated lit features is what finds the one in
ten that carries a stale face override.

---

## 6 · Workspaces, and the one-way door

Every tool operates on the active document regardless of which workspace is
showing, so a whole run can complete with the Design workspace on screen and no
visible sign of activity. Switch visibly:

```python
ui.workspaces.itemById('FusionRenderEnvironment').activate()
adsk.doEvents()
assert ui.activeWorkspace.id == 'FusionRenderEnvironment'
```

`ui.activeWorkspace.id` is the test. `products.itemByProductType(
'RenderingProductType')` returns `3 : failed to find product` even when the
switch worked. Switching to Render **resets the viewport** (height 804 → 684 in
one measured case, 1693×671 in another), so activate **first**, set the camera
**second**, and re-read the viewport dimensions immediately before rendering.

**A Drawing document is a one-way door.** The MCP reads `design.designType` in
its instrumentation, and a `Drawing` product has no such attribute, so with a
drawing active:

```
'Drawing' object has no attribute 'designType'    <- execute_code, get_design_type
```

`ping` still answers — the *wrapper* is what stops. No MCP call activates a
different document, so only a human clicking the Design tab can return the
session to the model. **Plan the run so the drawing is the last Fusion action**,
and say so when you open it. Check the active product before concluding a call
failed for its own reasons:

```python
app.activeProduct.productType      # expect 'DesignProductType'
```

**Never call `export_drawing_pdf`.** It opens a modal and hangs the MCP server.

### Telling a modal apart from a slow call

A modal dialog blocks the API thread and `ping` stops answering — but so does a
long-running command. `create_drawing` takes longer than the MCP request timeout
and leaves `ping` unresponsive for ~45 s while succeeding normally. So when
`ping` goes quiet: **wait and poll it**, rather than retrying the call. If it
comes back, the command completed; check `get_design_type` to see what state you
are in. The `'Drawing' object has no attribute 'designType'` error at that point
is proof the drawing was created.

---

## 7 · Verification habits

1. A tool's return value is not evidence. A second, independent derivation is.
2. Check `healthState` on every timeline entity after any structural edit —
   a silently failed feature is worse than a raised one:
   ```python
   [(i, design.timeline.item(i).name)
    for i in range(design.timeline.count)
    if design.timeline.item(i).entity is not None
    and int(design.timeline.item(i).entity.healthState) != 0]    # expect []
   ```
3. Name every sketch and body as you create it. Delete features **by name**;
   a sketch matched on curve count will eventually match the wrong one and leave
   a downstream extrude running on cached geometry (`healthState 1`, "Profile
   reference is lost… using cached geometry") while still reporting a healthy
   body count.
4. Order deletes after dependents: a fillet **earlier** in the timeline than a
   body delete still computes, so delete afterwards and nothing errors.
5. Measure the bodies; never read `get_parameters` as a description of the
   model. A parameter can read 15.0 while the geometry is 20.0.
6. For anything visual, take a one-second `render_view` capture before spending
   100 s on a raytraced final. Most build defects are visible there.
7. Prefer volumes and closed-form material removals as checksums. **Face counts
   are build-path dependent** — the same geometry measured 63 faces on one build
   path and 78 on another with identical volumes.

