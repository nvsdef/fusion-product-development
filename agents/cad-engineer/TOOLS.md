# CAD Engineer — tool reference

`AGENTS.md` is the short map. This file is the detail: exact signatures, the
arguments that must be passed explicitly, and what each call returns.

All eight tools are published by the `fusion-mcp` plug-in and prefixed
`fusion-mcp__`. The prefix is omitted below for readability.

---

## `ping`

No arguments. Returns `pong: True`.

The liveness check, and the only thing that still answers when the MCP wrapper
is broken by a Drawing document. **A silent `ping` means one of two things** —
a modal dialog is open, or a long command is still running. They are
indistinguishable, so: wait ~45 s, poll again, and only then conclude.

## `get_design_type`

No arguments. Returns `design_type: parametric`.

**Run this first, every session.** If it errors with

```
'Drawing' object has no attribute 'designType'
```

a Drawing document is active. No MCP call can change that — a human must click
the Design tab. Stop and say so.

## `execute_code`

```
execute_code(code="<python source>")
```

The real API surface. Runs inside Fusion with `app`, `ui`, `design`,
`component`, `adsk`, `math` pre-bound — never import them. **Takes source, not a
path**; passing a path raises `SyntaxError`.

Returns the **last expression, REPL-style**, plus free instrumentation on every
call: `body_count`, `mass_g`, and before/after bounding-box deltas.

Return a dict of the measurements that prove the call worked:

```python
{'vol_after_shell': round(b.volume, 3), 'target': 219.09,
 'faces': b.faces.count, 'bodies': c.bRepBodies.count}
```

Notes that cost time if you learn them the hard way:

- **Units are centimetres.** Every spec is millimetres.
- The bbox instrumentation carries a ±0.03 mm pad — a body sitting exactly on
  Z 0 reports −0.003 cm. Expect it.
- Scope each call to one logical operation (one *feature class* during a cold
  build). Never batch a parameter edit with deletes and a rebuild.
- **On `Request timed out`, re-query state first.** The operation has very
  likely completed.

## `render_view`

```
render_view(view='top'|'front'|'right'|'iso', fit=True)
```

~1 s viewport capture, returned inline as an image. This is the cheap gate:
missing bodies, a filled region, an obviously wrong material, a letterform built
wrong — all visible here, none visible in a body count.

**Judge every layout question on `view='top'`.** In perspective, radial tick
arrays foreshorten into what looks like scatter.

## `start_render`

```
start_render(height=1200, quality=95, view='current', filename='hero_raw')
```

| Argument | Behaviour |
|---|---|
| `view` | **Defaults to `'iso'` and applies the tool's own camera preset, discarding the live viewport camera.** Pass `'current'` to use the camera you set. The return payload states which view it used — read it. |
| `width` | **Discarded.** Output is `height × live viewport aspect`. Measured: viewport 1693×671 (aspect 2.5231) + `height=1200` → 3030×1200. |
| `height` | Honoured. |
| `quality` | 25 for a ~15 s exposure probe, 95 for a ~110–135 s final. |
| `transparent_background` | Writes correct RGB with **alpha uniformly 0**. The matte is dead; key the plate instead. |

Returns `job_id` and `path`. **Read the path from the payload** — it lives in a
Fusion build-hash directory that changes on every update.

## `get_render_status`

```
get_render_status(job_id='render_1')
```

Poll until `state: finished`. **Never pass `include_image=True`** — 138k
characters for one frame, which overflows the tool budget and still does not
show you the image. `Read` the PNG off disk instead.

## `set_scene_environment`

```
set_scene_environment(brightness=1700)
```

Applies `brightness` and returns `unsupported: [...]` for `ground_plane`,
`ground_reflections` and `background`. Read the `unsupported` list in the
success payload.

Two things follow from what it cannot do:

- Nothing bounces into shadowed faces, so dark materials crush. The albedos in
  the spec are photographic matches, not physical values — do not "correct" them.
- The backdrop renders **perfectly uniform** (measured std 0.000 at rgb
  178,178,178), which makes an exact difference matte possible: hide every
  occurrence, render the empty plate, unhide, and take `|render − plate| > 10`.

**`brightness` is not the only exposure control.** `sceneSettings.cameraExposure`
is a second one, it is **inverse** (lower = brighter), it defaults to **9.5**,
and `set_scene_environment` does not write it. Every lux figure in these skills
was derived at `cameraExposure 9.5`. Confirm it before trusting them, and if you
move it, every brightness number is void and you re-derive from scratch.

## `create_drawing`

```
create_drawing(sheet_size='A3ISO', standard='ISO', units='mm',
               center_marks=False, open_drawing=True)
```

Two arguments are non-negotiable: `sheet_size` needs the full enum stem
`A3ISO`, not `A3`; `center_marks=True` raises `CenterMarkDisplayTypes not
available in this Fusion build`. **A bare `create_drawing()` cannot succeed.**

It works — and it **exceeds the request timeout while succeeding**. Expect
`Request timed out` and a silent `ping` for ~45 s. Do not retry. Wait, poll
`ping`, then call `get_design_type`: the `'Drawing' object has no attribute
'designType'` error is the proof it worked.

**This call is terminal.** After it, `execute_code` no longer runs and no MCP
call can switch documents. It is the last Fusion action of any run.

---

## Not registered, and why

| Tool | Why |
|---|---|
| **`export_drawing_pdf`** | Opens a modal and hangs the entire MCP server. `ping` stops answering and Fusion must be recovered by hand. Never call it, on any branch. |
| `delete_all`, `set_design_type`, `undo`, `import_mesh` | Destructive or state-changing in ways that are hard to detect afterwards. If I want one, the answer is to do it deliberately inside `execute_code`, or to ask. |
| The other ~85 add-in tools | Everything they do is reachable through `execute_code`, usually faster. Registering them degrades tool selection — the surface goes from 8 to ~95 and the model starts guessing. |

## Host-side scripts

Not MCP tools — I run these with `terminal`, outside Fusion.

| Script | Purpose |
|---|---|
| `scripts/composite.py` | Key, grade, shadow, bloom and crop a raw render. Everything is a flag; do not edit it. |
| `scripts/measure_classes.py` | Class luminance, LED G:R, and the ten-pad connected-component check. Pure numpy — no scipy. |
| `scripts/make_views.py` | Crop and calibrate the line-art captures. Prints a crop-aspect error per view; expect ≤ 0.11 %. |
| `scripts/make_drawing.py` + `scripts/slab_sheet.json` | Compose the dimensioned A3 sheet. Edit the JSON's content, not its layout. |
| `scripts/compare_palette.py` | k-means palette comparison against a reference. |

They need **PIL, numpy, reportlab**, and `pdftoppm` (poppler) for the raster
check.
