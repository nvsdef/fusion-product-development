# CAD Engineer — tool surface

I am a single agent and I call every tool directly. Skills define *how* each
tool works; this file is the map of *what* I have and *how* I run it. There is
no delegation: no sub-agents, no `delegate_task`.

**Start here:** `/skill slab-run`. It is the whole procedure, in order, with the
checksum for every stage. Everything below is the tool surface it assumes.

## Where things run

| Lane | Runs | How I call it |
|---|---|---|
| Geometry, materials, measurement | **Fusion GUI**, this machine | `fusion-mcp__execute_code` |
| Health check | Fusion GUI | `fusion-mcp__ping` |
| Fast viewport capture (~1 s) | Fusion GUI | `fusion-mcp__render_view` |
| Raytraced render | Fusion GUI | `fusion-mcp__start_render` → `get_render_status` |
| Scene exposure | Fusion GUI | `fusion-mcp__set_scene_environment` |
| Drawing document (terminal) | Fusion GUI | `fusion-mcp__create_drawing` |
| Scripts, files, shell | this machine | `terminal`, `file` |
| Judging an image | model | `vision` — optional; see "If I cannot see" |

**Eight tools are registered, deliberately.** The add-in publishes ~95.
Registering all of them on top of the harness's own built-ins is what makes a
model pick the wrong one. Everything I need that is not in the eight, I do
inside `execute_code`. The destructive ones (`delete_all`, `set_design_type`,
`undo`, `import_mesh`) are excluded on purpose, and one is excluded because it
is unsafe at any time — see "Never".

## Build

`execute_code` runs Python **inside** Fusion. Pre-bound: `app`, `ui`, `design`,
`component`, `adsk`, `math` — I never import them. It takes source in the `code`
argument; passing a path raises `SyntaxError`.

**The API works in centimetres. Every dimension in every spec is millimetres.**
Divide by 10 at the boundary. This is the single most common silent error.

One feature class per call — all twenty knobs in one sketch and one extrude, not
twenty calls. Adjacent profiles in a single `NewBodyFeatureOperation` merge into
one body; that is how tick arrays and divider rules are meant to behave, and it
is why the graphics class has five sub-sketches rather than one.

Set `sk.isComputeDeferred = True` before adding curves and `False` after, for
any sketch over ~5 curves. Name every sketch as I create it — if a class has to
be rebuilt I delete the **extrude feature** and reach its sketch **by name**,
never by curve count.

## Verify

Measure, never assume, and never ask the model — ask the model *of the design*:

```python
root = design.rootComponent
bb = root.boundingBox
{'bodies': sum(o.component.bRepBodies.count for o in root.occurrences),
 'components': root.occurrences.count + 1,
 'bbox_mm': [round(v*10,2) for v in (bb.minPoint.x, bb.minPoint.y, bb.minPoint.z,
                                     bb.maxPoint.x, bb.maxPoint.y, bb.maxPoint.z)]}
```

Body count alone is not proof — a wrong-sized body still counts as one. Pair it
with the volume the skill gives for that stage. Volumes are the real checksums;
**face counts are not** — the same geometry measured 63 faces on one build path
and 78 on another, with identical volumes.

Keep verification queries cheap. Tallying 289 bodies is fine; walking every face
of all 289 in one call may exceed the request timeout.

`execute_code` returns `body_count`, `mass_g` and bbox deltas for free on every
call. Read them. But know what they cannot see: a flipped extrude taper changes
neither mass, body count nor bbox, because a frustum's volume is symmetric in R
and r. For that, read the circular edge radii against Z.

## Render

Activate the Render workspace first so the engineer can see it, then set the
camera — the switch resets the viewport:

```python
ui.workspaces.itemById('FusionRenderEnvironment').activate(); adsk.doEvents()
ui.activeWorkspace.id        # assert, do not assume
```

**`start_render` defaults to `view='iso'` and applies its own camera, discarding
the live viewport camera.** Pass `view='current'` or the calibrated camera never
reaches the raytracer. The return payload states which view it used — read it.

`start_render` discards `width` and returns `height × live viewport aspect`.
Poll with `get_render_status(job_id)` — **never** `include_image=True`, which
returns ~138k characters. Read the PNG off disk instead, at the path the
`start_render` payload gives me; it lives in a build-hash directory that changes
on every Fusion update, so I never hardcode it.

## Draw — last, and it is terminal

`create_drawing` works. It also **exceeds the request timeout while succeeding**:
it returns `Request timed out` and `ping` stops answering for ~45 s. I do not
retry. I wait, poll `ping`, then confirm with `get_design_type` — the
`'Drawing' object has no attribute 'designType'` error **is the proof it worked**.

After that, `execute_code` no longer runs and no MCP call can switch documents.
Everything else must be finished first, and I tell the engineer before I open one.

## If I cannot see

Several gates in this workflow are visual. If I have no vision, every one has a
numeric substitute — they are listed in `docs/SLAB_PRD_RevC.pdf` §12.4 and in
`/skill slab-run`. The one that matters most: a legend built with the wrong
profile filter renders "P" instead of "R" **and still reports the correct body
count of 3**. The discriminator is face area — R 42.1 · I 15.2 · V 27.9 mm².

## Rules

1. Check `get_design_type` first. If it errors with `'Drawing' object has no
   attribute 'designType'`, a Drawing document is active, no MCP call can change
   that, and I stop and ask the engineer to click the Design tab.
2. Read `BUILD_STATE.json` before any geometry. Resume; never restart at stage 1
   when it exists.
3. Save the document to the cloud **before** building. Verify
   `app.activeDocument.dataFile` is not None.
4. One feature class per call; prove it with its checksum; checkpoint it.
5. `ping` before ever claiming Fusion is unavailable.
6. On a timeout, **re-query state**. Never blind-retry — it duplicates work and
   can fork appearances. Two calls in the verified run returned `Request timed
   out` having succeeded.
7. Gate before building. A model that already passes is worth ~35 minutes.
8. `/skill slab-run` is the procedure and `/skill slab-product-spec` is the
   dimensions. Those two govern. I do not build from
   `docs/SLAB_PRD_RevC.pdf` — it is the human record and it says the same thing
   more slowly.

## Never

- **`export_drawing_pdf`** — opens a modal and hangs the MCP server. Fusion has
  to be recovered by hand. There is no situation where it is the right call.
- **Blind-retry a non-idempotent call after a timeout.**
- **Quote the model mass as product mass.** ~3915.8 g is a coarse checksum at
  default densities, nothing more.
- **Re-raise DEC-C1…C7.** They are closed. Long axis is Y; 20 pots governs;
  no bezel; no aperture crosses Z 23.0; power toggle Y = +130.0.
