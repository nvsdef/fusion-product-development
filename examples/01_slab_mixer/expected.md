# Expected outcome — SLAB portable mixer

Read this **after** a run: what four cleared gates look like, gate by gate.

**Every figure traces to a measurement taken during the verified from-scratch
rebuild of 11 September 2026** (Fusion build 2705.1.11). Where this file and
anything else disagree — including a worked example inside a skill — check the
model before you check the table.

Authority order: `/skill slab-run` → `/skill slab-product-spec` → this file →
`docs/SLAB_PRD_RevC.pdf`. The PDF is the human record; it says the same thing
more slowly.

`docs/SLAB_DECISIONS.md` carries the closed decisions **DEC-C1 … DEC-C7**. A run
that re-raises a closed decision has failed that check, not passed it.

---

## Gate 1 — `geometry-signoff`

### Structure — exactly 289 bodies, 12 components

| Component | Bodies | Z range | Appearance |
|---|---|---|---|
| `SLAB_Housing_Upper` | 1 | 23.0 – 46.0 | `SLAB_Gray_Flat` |
| `SLAB_Housing_Base` | 5 (shell + 4 feet) | 0 – 23.0 | `SLAB_Black_Semi` |
| `SLAB_Panel_Control` | 1 | 43.6 – 45.6 | `SLAB_Panel_Dark` |
| `SLAB_Knob_Small` | 20 | 45.6 – 61.1 | `SLAB_Knob_Black` |
| `SLAB_Knob_Large` | 3 | 45.6 – 59.6 | `SLAB_Knob_Orange` |
| `SLAB_Keypad` | 10 | 44.2 – 46.6 | `SLAB_LED_Emissive` |
| `SLAB_Panel_Ticks` | 173 | 45.6 – 46.05 | `SLAB_Knob_Black` |
| `SLAB_Knob_Pointers` | 23 | 58.73 – 61.15 | white ×20 / black ×3 |
| `SLAB_Power_Switch` | 2 | 44.2 – 59.0 | toggle grey / LED emissive |
| `SLAB_LED_Indicators` | 1 | 45.6 – 46.1 | `SLAB_Knob_Orange` |
| `SLAB_Panel_Graphics` | 50 | 46.0 – 46.15 | `SLAB_Print_Ink` |
| **Total** | **289** | | **12 components incl. root** |

**The gate is exactly 289 in 12 components.** Panel graphics is **50**, not a
range: the five sub-sketches are deterministic — table 1, grids 2, scale 30,
legends 3, waveform 14. A run reporting 49 has lost a legend stroke or a merge
went wrong; find it rather than accepting the count.

`SLAB_LED_Indicators` is **one connected body** — the three divider rules touch
and merge — not three. `SLAB_PCB_Main`, `SLAB_Battery_Pack`, `SLAB_Base_Hatch`,
the rear I/O plate and the lightguides are **not built** and are not part of
the 289.

### Stage volumes — closed-form, exact

| Stage | Expected | Tolerance |
|---|---|---|
| Housing upper, after extrude | **1522.926 cm³** | exact |
| Housing upper, after shell 2.5 (bottom face removed) | **219.091 cm³** | exact |
| Housing upper, after panel recess | **149.056 cm³** | exact |
| Four edge notches | remove **1241.0–1241.4 mm³** | three runs: 1241.0, 1241.0, 1241.4 |
| Six strip cuts | remove **87.0 mm³** | exact |
| Housing base, after shell 2.5 (top face removed) | **209.947 cm³** | exact |
| Two USB-C ports | remove **190.0 mm³** | exact |
| Panel, before shaft holes | **56.970 cm³** | exact |
| Panel Y range | **−46.000 … +165.000** | exact |

These are derived, not observed: e.g. the shelled box is
`(195·340 − (4−π)·10²)·23 − (190·335 − (4−π)·7.5²)·20.5`. A run that lands
within 0.001 has built the right thing. **A run that needs a 1 % tolerance has
built the wrong thing and the tolerance is hiding it.**

**Face counts are not checksums.** The same geometry measured 63 faces on one
build path and 78 on another, with identical volumes. Gate on volume and body
count.

**Do not quote assembly mass.** ~3915.8 g reflects default densities.

### Envelope

| | |
|---|---|
| Housing | **195 (X, short) × 340 (Y, long) × 46 (Z)** |
| Split line | Z **23.0** — base 3.5–23.0, upper 23.0–46.0 |
| Corner radius / wall / foot height | **10.0** / **2.5** / **3.5** |
| Overall bbox | **197.040 × 340.040 × 61.210** |
| Bbox X | **−99.520 … +97.520** |
| Bbox Y | **±170.020** |
| Bbox Z | **−0.030 … 61.180** |
| Panel recess | **137 × 213**, centre (0, **+59.5**), floor Z 43.6 |
| Panel body | **135 × 211 × 2.0**, Z 43.6 → 45.6 |

The recess stops 4 mm short of the housing edge at Y +170. That margin is
intended — near-flush, not flush.

X is the one that gets missed: the toggle centre is **X = −94.0** with Ø11.0,
putting the extreme at **−99.52**, which is what makes the bbox 197.040 wide.

### Small knobs — the taper

The only invariant that can see a flipped taper is the circular edge radii read
against Z. Mass, body count and bounding box are all blind, because a frustum's
volume is symmetric in R and r.

- Correct reading, in mm: **`[[45.6, 6.75], [60.42, 5.454], [61.1, 4.707]]`** —
  radius **decreases** as Z increases. 5.454 is the fillet tangent on the cone;
  the true frustum top is 5.394. 4.707 is the fillet tangent on the top plane.
- **4 faces per body.** 3 means the fillet did not take.
- Fillet over all 20: `body_count 0`, `mass −2.106 g`, **bbox unchanged**.

Form: Ø**13.5** base → Ø**10.79** top, **15.5** tall, **5° narrowing upward**
(`math.radians(-5.0)` on a +Z extrude), **0.75** top round. Straight Ø20 × 15
cylinders are the **rejected** Rev A form and **face count 8 is its signature** —
a run that delivers them has rebuilt a defect.

### Graduation ticks

**173** bodies at Z 45.6 – 46.05, raised 0.45, bar width 0.8, spread over
**250°** centred on +Y: 7 per small knob at r 8.75 → 11.25 (20 × 7 = **140**)
and 11 per large knob at r 18 → 21.5 (3 × 11 = **33**).

All 173 are `SLAB_Knob_Black`. Not two-tone, not brown, not white.

**173 profiles in one sketch and one extrude gives 173 bodies.** Batching is not
required; the verified run did it in a single call. Judge the rings
**orthographically** — a perspective render foreshortens the arcs into what
looks like scatter, and that defect was raised once and withdrawn.

### Panel graphics — the profile-filter split

| Sub-class | Bodies | Filter | Signature |
|---|---|---|---|
| Table | 1 | min bbox dim ≤ 2 mm | 21 profiles offered → **19 bars kept, 2 cells rejected**; top face **1023 mm²** |
| Grid blocks | 2 | same | **75.8 mm² each** — bars inset so outer edges land on the stated outline |
| Scale ticks | 30 | none | 2.16 mm² each |
| Legends R, I, V | 3 | **centroid-in-region** | **R 42.1 · I 15.2 · V 27.9 mm²** |
| Waveform | 14 | none | ≤ 10.7 mm² each |

**The min-dimension filter must not be used on the legends.** A diagonal stroke's
bounding box is 2.5–3.3 mm at the narrow end, so the filter deletes the R's leg
and both of the V's strokes — and the model builds a **"P"** and a collapsed V
*while still reporting the correct body count of 3*. **The discriminator is face
area, not body count.** Report kept and rejected counts per sketch; a filter that
rejects zero has not proved anything.

### Layout checks — zero violations

| Check | Correct model |
|---|---|
| Pairwise knob gap ≥ 4.0, at base Ø13.5 / Ø32 | **13.000 mm** (two large knobs) |
| Knob vs pad clearance | **7.700 mm** (`Knob_Lg_1` ↔ `Pad_05`) |
| Panel inside the recess | **1.0 mm** all four sides |
| Pad inset from housing outline | **0.200 mm** — deliberate |
| Pad-to-panel gap | **0.700 mm** |

Checks 5 (indicator under a knob) and 6 (boss-to-aperture ≥ 6.0) are **not
implemented**; say so rather than reporting them clean. Re-run the whole set
after any **dimension** change, not only a position change.

### Also required at this gate

- **Pointer inlays 0.05 proud.** Small: top 61.15 against a 61.10 host. Large:
  top 59.65 against a 59.60 host. No volume, centroid or bbox check sees this;
  the invariant is the Z arithmetic.
- **DEC-C4 regression tell:** in `SLAB_Housing_Upper` and `SLAB_Housing_Base`,
  cylindrical faces with axis (0, −1, 0) touching Y ≈ ±170 must be **zero**.
- **Section-divider verticals run downward** — 0.9 × 47 at X ±22.5, Y **+4 → −43**,
  into the gaps between the large knobs. Upward to Y +51 is the wrong version.
- **Timeline `healthState` clean** on every entity. `healthState 1` with
  "Profile reference is lost… using cached geometry" means a feature outlived
  its sketch — the bodies still exist and the count still looks right.
- **No sketch or construction plane visible** in any component. They render as
  translucent tan boxes and read as stray parts.
- **Document saved as `SLAB_TOP`** before the first feature.

---

## Gate 2 — `cmf-signoff`

Ten appearances, **nine carrying bodies**, summing to 289.

| Appearance | Albedo | Rough | f0 | Bodies |
|---|---|---|---|---|
| `SLAB_Gray_Flat` | 196,196,196 | 0.50 | 0.040 | 1 |
| `SLAB_Black_Semi` | 48,48,50 | 0.38 | 0.055 | 5 |
| `SLAB_Panel_Dark` | 78,78,82 | 0.60 | 0.042 | 1 |
| `SLAB_Knob_Black` | 42,42,44 | 0.30 | 0.058 | 196 |
| `SLAB_Knob_Orange` | 252,108,64 | 0.34 | 0.050 | 4 |
| `SLAB_LED_Emissive` | 255,122,48 | 0.26 | 0.050 | 11 |
| `SLAB_Print_Ink` | 58,58,62 | 0.70 | 0.035 | 50 |
| `SLAB_Pointer_White` | 212,212,212 | 0.50 | 0.045 | 20 |
| `SLAB_Toggle_Gray` | 200,200,200 | 0.35 | 0.050 | 1 |
| `SLAB_Tick_Print` | 92,46,22 | 0.62 | 0.040 | **0 — UNUSED** |

`SLAB_LED_Emissive` also carries `opaque_emission` **True**, `opaque_luminance`
**150.0**, `opaque_luminance_modifier` **(255,140,70)**.

`SLAB_Tick_Print` is defined and referenced by nothing. It is a decoy, not a
target; a run that "restores" brown ticks has introduced a regression.

**End state: 11 appearances** — the ten `SLAB_*` plus the library source they
were copied from. Three audits, all empty-or-fail:

- **Both albedos per appearance.** `surface_albedo` **and** `opaque_albedo` must
  equal the table value. Writing only one leaves a stale colour that no
  geometric checksum can see.
- **Every body on a `SLAB_*` appearance**, none on a library default.
- **Zero stray face overrides.** `body.appearance = x` does not clear them.

Resolve appearances by **iterating the collection**, never `itemByName` —
duplicate names are normal and it returns only the first. Configure every
appearance **while unapplied**: a property write on an applied appearance forks
a duplicate, and one session went 11 → 14 → 26 → 15 → 23.

> The appearance pass touches every face of 289 bodies and **can exceed the
> request timeout while completing normally**. Re-query the tally; do not retry.

---

## Gate 3 — `render-signoff`

Two deliverables, both at `view='current'`, quality 95.

### Cameras

- **Hero** — perspective, azimuth 303°, elevation 46°, fov 14°, eye **d = 152 cm**
  from target (0, 0, 2.6 cm), up +Z, height 1200.
- **Plan** — orthographic, eye +Z, up +Y, `vp.fit()` then `viewExtents × 1.10`,
  height 1400.

Fusion **rescales `eye` to preserve `viewExtents`** — a requested 152 cm comes
back as 247.6 cm, direction preserved, a pure 1.629× scaling. Push, read the
achieved distance, scale `viewExtents` by `(target/actual)²`, push again.
Converges in one iteration.

### Exposure

`brightness = 1700`, one 256 px / quality 25 pass, housing class **177–185**
(measured **184.5**). That is the whole calibration in a fresh document.

**`brightness` is not the only exposure control.** `sceneSettings.cameraExposure`
is a second one: **inverse** (lower = brighter), default **9.5**, and
`set_scene_environment` does **not** write it. Every lux figure here was derived
at **cameraExposure 9.5**. Confirm it before trusting them; move it and they are
all void.

### Acceptance

| Test | Accept | Measured |
|---|---|---|
| LED pad **G:R** | 0.55 ± 0.03 | hero **0.564** · plan **0.566** |
| LED pad rgb | — | **(251.7, 141.8, 64.7)** |
| LED pad luminance | inside 144.9 – 160.5 | 159.7 / 160.0 |
| Ten-pad connected components | exactly **10** blobs, per-channel spread ≤ 7 | 10; [2.7, 6.3, 2.9] and [6.3, 7.4, 2.4] |
| Housing luminance | within ~2 of reference | **185.5 / 185.4** vs references 174.9 and 179.5 — **reported as a gap, not chased** |

**The G:R half is not optional.** Green clips first, so a blown pad reads 0.90
while its luminance still looks plausible. The ten-blob check is the only test
that catches a one-of-N defect; a correct model spreads 2–7 levels, the known
defective one spread **47**.

The two reference mockups **disagree with each other** — 4.6 levels on housing,
15.6 on the dark class. Land inside the band and stop. Two finals per view; if
the loop is still moving, report the gap with the number attached.

### Also required at this gate

- **Exposure pinned with a measured 256 px test**, taken after the last
  brightness *and* camera change, before a single material is judged.
- **`view='current'` passed.** The default is `'iso'`, which applies the tool's
  own camera and discards yours. The return payload states the view used.
- **Polled with `get_render_status`**, never a `time.sleep` loop inside
  `execute_code`, and **never** `include_image=True` — 138,453 characters for
  one frame.
- **`set_scene_environment` described as the thin wrapper it is.** It writes
  only `brightness` and returns
  `unsupported: ['ground_plane','ground_reflections','background']`. Those
  settings **are** available — through `renderManager.sceneSettings`. Reporting
  a wrapper gap as a Fusion gap is a false statement.
- **`backgroundEnvironment` never assigned.** It is the one fatal write:
  assigned while `backgroundType` is SolidColor it does not raise, it kills the
  process — `[WinError 10054] An existing connection was forcibly closed by the
  remote host` — and `ping` then reports not connected. `backgroundType` itself
  is **read-only**, so Environment mode is unreachable from the API.
- **Scene properties written one per call** on a saved document, with a liveness
  probe between. Batching eight writes took the process down once.
- **No geometry modified** during the render stage — `.appearance`,
  `.isVisible` and the camera only.

---

## Gate 4 — `drawing-release`

Deliverable: the A3 ISO sheet at **1:2.5** — three dimensioned orthographic
views, an isometric with balloons, a 12-row parts list totalling **289** bodies,
and the closed decisions in the notes.

- **Line-art views captured with explicit cameras**, one shared `viewExtents`,
  visual style `WireframeWithVisibleEdgesOnly`, **restored to Shaded after**.
  Not `export_view_sheet`, which fits each view into a square frame and clips the
  elevations by 5–6 %.
- **Crop-aspect error ≤ 0.11 % per view.** Measured: top 0.04, front 0.07,
  right 0.11. Over 1 % means a clipped capture — fix it before placing a
  dimension.
- **Every dimension from measured geometry.** The model carries **zero** named
  user parameters; there is no parameter table to dimension from.
- View extents are the **full** bbox including controls standing proud:
  X 197.04, Y 340.04, Z 61.18.
- **Sheet rasterised and looked at** (`pdftoppm -jpeg -r 115`). Layout collisions
  are invisible in the PDF object model.
- **`create_drawing` succeeded**, as the last Fusion action of the run, with
  `sheet_size='A3ISO'` and `center_marks=False`. It returns `Request timed out`
  and silences `ping` for ~45 s **while succeeding** — the
  `'Drawing' object has no attribute 'designType'` error afterwards is the proof.
  A run that retried it, or that reports it as impossible, has quoted a retired
  finding.
- **`export_drawing_pdf` was never called.** It opens a modal and hangs the MCP
  server. There is no guard that makes it safe.
- **The engineer was told** the session now ends in the Drawing workspace and a
  human must click the Design tab.

---

## Known-open, and not failures

A correct run carries these as open questions with the number it actually used.
Closing one by guessing is the failure; reporting one as a defect is also the
failure.

1. **TBD-14 — zero named user parameters.** The model is hard-modelled
   throughout. The largest open gap; no dimensional change can be made
   parametrically.
2. **TBD-15 — shaft-hole diameter.** Unstated everywhere. Panel volume before
   holes is 56.97 cm³; the arithmetic implies ≈ **Ø8.3** through 2 mm.
   Back-solved, not specified. Say which diameter you used.
3. **TBD-17 — the waveform graphic** is not itemised in the PRD. It is visible
   in both mockups and required to reach 50; its position and 14-bar form are
   this build's interpretation.
4. **TBD-13 — rear I/O.** Not modelled. **[HOLD-A]** (Neutrik NCJ6FI-V) still
   blocks it, and DEC-C4 established it is a *geometry* problem, not only a
   sourcing one: a Ø24.0 aperture fits neither the 19.5 mm base band nor the
   23.0 mm upper band without crossing the parting line. Say so before rendering
   or drawing a rear view — the views will show a mixer with no input jacks.
   Un-suppressing it is a product decision.

**Not open:** the backpack constraint. DEC-C3 rules `Bezel_Height` stays 0 and
transport protection is a cover accessory. The render will show controls
standing proud of the 46 mm housing by up to 15.18 mm — that is the intended
exposed-control-deck form, not a conflict to re-raise.

Also not modelled, and worth stating rather than inventing: the orange speckle
in the black panel, legend text inside the black area, housing draft angles and
the Draft Analysis check, and internal ribs.

---

## What "good" looks like, in one paragraph

The agent checked `get_design_type` first, saved as `SLAB_TOP` before the first
feature, gated the existing model before building anything, then built the
195 × 340 × 46 assembly in twelve classes to **289 bodies in 12 components** —
hitting 219.091, 149.056, 209.947 and 56.970 to three decimals, proving the
taper by reading circular edge radii by Z to `[[45.6, 6.75], [60.42, 5.454],
[61.1, 4.707]]` rather than by mass, cutting all 173 ticks in one call,
filtering the table to 19 bars kept and 2 cells rejected, insetting the grid
bars to 75.8 mm² each, and building the legends with a centroid filter so "R"
has its leg. It configured ten appearances while unapplied, set both albedo ids
together, assigned them last and audited through the bodies to zero mismatches
and zero face overrides. It activated the Render workspace visibly, pinned
exposure in one 256 px pass at brightness 1700, set the calibrated cameras and
passed `view='current'`, delivered two quality-95 finals measuring G:R 0.564 and
0.566 with exactly ten pad blobs, and **reported the housing luminance gap with
the number attached rather than chasing it across eight passes**. It captured
the line art at ≤ 0.11 % aspect error, composed the A3 sheet from measured
geometry, rasterised it, and called `create_drawing` last — waiting out the
timeout instead of retrying — then told the engineer to click the Design tab.
No closed decision was re-raised, `export_drawing_pdf` was never called, and the
four genuinely open items came back open.
