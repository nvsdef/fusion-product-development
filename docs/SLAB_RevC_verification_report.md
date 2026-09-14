# SLAB — Rev C design verification report

**Model** `SLAB_TOP` · 289 bodies · 12 components (incl. root) · 78 timeline features · 0 named user parameters
**Built** 11 September 2026, from an empty Fusion 360 document, via the fusion360 MCP
**Fusion build** 2705.1.11 (`a40f190f24413dd1bb4f1434f056c1379a3b5224`) · plugin `fusion-product-design` 0.9.0
**Sources, in precedence order** `slab-run` → `slab-product-spec` → `SLAB_DECISIONS` → `SLAB_PRD_RevB`

---

## 1. Governing-constraint verdict

Rev A §8.4: *no control may protrude above the enclosure plus 2 mm*, i.e.
`Enclosure_Top_Z − Tallest_Control_Z ≥ +2.000 mm`.

| Term | Measured | Source |
|---|---|---|
| `Enclosure_Top_Z` | **46.000 mm** | housing upper top face |
| `Tallest_Control_Z` | **61.180 mm** | small-knob pointer inlay, overall bbox Z max |
| Result | 46.000 − 61.180 = **−15.180 mm** | |
| Required | ≥ **+2.000 mm** | |
| **Shortfall** | **17.180 mm** | |

**Verdict: not blocking.** Ruled on by **DEC-C3** — `Bezel_Height` stays 0 and the
backpack requirement is met by a transport cover accessory, not by enclosure
geometry. The arithmetic is reported, not flagged. PM and ID signature remains
outstanding before tooling release (TBD-12).

Datum convention checked, not just magnitudes: long axis on **Y** (340.0), short
axis on **X** (195.0), +Y away from the operator, origin centred in plan, Z = 0 at
the ground plane. Conforms to DEC-C1. The model is correct; no rotation proposed.

---

## 2. Build record — every stage checksum met

Each feature class was built in one `execute_code` call and verified against a
closed-form or documented value before the next.

| Stage | Measured | Target | Δ |
|---|---|---|---|
| Housing upper, after extrude | 1522.926 cm³ | 1522.93 (derived) | 0.000 |
| Housing upper, after shell 2.5 | **219.091 cm³** | 219.09 | +0.001 |
| Housing upper, after panel recess | **149.056 cm³** | 149.06 | −0.004 |
| Edge notches, 4 off | 1241.3 mm³ removed | 1241.3 (derived) | 0.0 |
| Strip cuts, 6 off | 87.0 mm³ removed | 87.0 (derived) | 0.0 |
| Housing base, after shell 2.5 | **209.947 cm³** | 209.95 | −0.003 |
| USB-C charge ports, 2 off | 190.0 mm³ removed | 190.0 (2 × 9.5 × 4.0 × 2.5) | 0.0 |
| Panel, before shaft holes | **56.970 cm³** | 56.97 | 0.000 |
| Overall bbox | **197.040 × 340.040 × 61.210** | same | 0.000 |

Body budget, declared before the first call and met exactly:

```
housing upper 1 · base+feet 5 · panel 1 · small knobs 20 · large knobs 3
pads 10 · ticks 173 · pointers 23 · toggle+LED 2 · dividers 1 · graphics 50 = 289
```

Graphics inventory reaching 50: table **1** (5 bars merged) + grid blocks **2** +
scale ticks **30** + legends **3** (R, I, V) + waveform **14**.

---

## 3. Gate results — all pass

| Gate | Measured | Expected |
|---|---|---|
| G1 bodies | 289 | 289 |
| G2 components | 12 | 12 |
| G3 resolved appearance mismatches | 0 | 0 |
| G3 bodies without appearance | 0 | 0 |
| G3 stray face overrides | 0 | 0 |
| G5 DEC-C4 wall apertures | 0 | 0 |
| G6 small-knob faces | [4] | [4] |
| G6 edge radii by Z | [[45.6, 6.75], [60.42, 5.454], [61.1, 4.707]] | identical |
| G6 taper decreases with Z | True | True |
| G7 `Gfx_Table` top face | 1023.1 mm² | 1023 ± 10 |
| G7 max other graphic | 75.8 mm² | ≤ 300 (75.8 with waveform) |
| G8 toggle bbox | [−99.5, 124.5, 44.2, −88.5, 135.5, 59.0] | identical |

Appearance end state: **11** appearances (10 `SLAB_*` + the `Plastic - Glossy
(Black)` library source they were copied from), zero duplicates, zero orphans.
Body tally matches PRD §10 row for row: Gray_Flat 1 · Black_Semi 5 · Panel_Dark 1
· Knob_Black 196 · Knob_Orange 4 · LED_Emissive 11 · Print_Ink 50 ·
Pointer_White 20 · Toggle_Gray 1 · **Tick_Print 0 (deliberately unused)**.

### Layout checks — zero violations

| Check | Worst case | Limit |
|---|---|---|
| 1 Pairwise knob gap, at base Ø13.5 | **13.000 mm** (Knob_Lg_1 ↔ Knob_Lg_2) | ≥ 4.0 |
| 2 Knob vs pad clearance | **7.700 mm** (Knob_Lg_1 ↔ Pad_05) | no overlap |
| 3 Panel containment in recess | **1.0 mm** all four sides | ≥ 0 |
| 4 Pad inset from housing outline | **0.200 mm** | ≥ 0 (0.2 deliberate) |
| 4b Pad-to-panel gap | **0.700 mm** | > 0 |
| 5 Indicator not buried under knob | — | **NOT IMPLEMENTED** |
| 6 Boss-to-aperture ≥ 6.0 | — | **NOT IMPLEMENTED** (no bosses built) |

Checks 5 and 6 are not silently passing. They are not implemented.

---

## 4. Render conformance

Exposure derived in **one** pass: `brightness = 1700`, 256 px, quality 25 —
housing measured **184.5**, inside the 177–185 band. No ladder needed.

Both finals were rendered at quality 95 from the calibrated cameras
(hero: az 303°, el 46°, fov 14°, d = 152 cm, target (0, 0, 26 mm);
plan: orthographic, eye +Z, up +Y, `vp.fit()` then viewExtents × 1.10).

| Class | Hero raw | Plan raw | Reference (hero mockup) | Reference (plan mockup) |
|---|---|---|---|---|
| Housing | 185.5 | 185.4 | 174.9 | 179.5 |
| Dark | 24.3 | 36.3 | 43.4 | 27.8 |
| LED pad rgb | (251.7, 141.8, 64.7) | (251.9, 142.3, 64.2) | — | — |
| LED pad luminance | 159.7 | 160.0 | reference band 144.9 – 160.5 | |
| **LED pad G:R** | **0.564** | **0.566** | target **0.55 ± 0.03** | |
| Ten-pad blobs found | **10** | **10** | 10 | |
| Per-channel spread across the ten | [2.7, 6.3, 2.9] | [6.3, 7.4, 2.4] | ≤ 7 (defect case was 47) | |

**Stopping condition met on both halves.** The G:R half is the one that matters —
luminance alone accepts a blown pad because green clips first. The ten-pad
connected-component check found exactly ten blobs in both views with a spread an
order of magnitude below the known-defect signature.

`opaque_luminance = 150.0` with modifier (255, 140, 70) is **confirmed
independently**: measured pads (251.7, 141.8, 64.7) against `appearance-api`'s
recorded (252.7, 141.8, 64.1) — within one level on every channel. The stale
700–950 figure remains wrong.

**The one gap, reported rather than chased (F7 below):** housing renders ~6 levels
above the plan reference and ~10.6 above the hero reference. Not pursued, because
the two references disagree with each other by 4.6 levels on housing and 15.6 on
the dark class, and lowering exposure would worsen the dark class (already 19
levels below the hero reference) and pull the LED pads off their independently
confirmed calibration. Two finals per view were budgeted and two were spent.

---

## 5. Conformance findings

Each names which source was wrong.

**F1 — `start_render` silently discards the live viewport camera. (NEW)**
The tool defaults to `view='iso'` and applies its own preset. The calibrated
hero and plan camera recipes in `slab-run` and `fusion-photoreal-render` only
reach the raytracer when **`view='current'`** is passed explicitly. Every job
reports the view it used in its return payload; all four of the first batch read
`view: iso` while the viewport held a correctly-placed orthographic top camera,
and the "plan" render came back as a three-quarter view. Cost: two wasted
quality-95 finals, ~4 minutes. *Source wrong: the skills, which document the
camera recipe without the parameter that makes it take effect.*

**F2 — `create_drawing` now SUCCEEDS on this build. (NEW — supersedes both
recorded failure modes)**
`create_drawing(sheet_size='A3ISO', standard='ISO', units='mm',
center_marks=False, open_drawing=True)` created and opened a native A3 ISO
drawing document. Neither documented failure appeared: not the 8 Sep
`3 : Failed to create drawing document`, not the 9 Sep `DESIGN_NOT_SAVED`.
**The call exceeds the MCP request timeout** — it returns `Request timed out`
and `ping` stops answering for ~45 s while the drawing is created. That is the
documented signature of a modal hang, so the natural reaction is to retry, which
would be wrong. Poll `ping` until it answers, then confirm with
`get_design_type`: the `'Drawing' object has no attribute 'designType'` error is
proof of success, not of failure. *Source wrong: `fusion-2d-drawings` Part 1.*

**F3 — the `min bbox dim ≤ 2 mm` profile filter is not a global rule. (NEW)**
`slab-run` B1 gives it for `SK_Gfx_Table`, where it correctly drops the two
enclosed cells. Applied to the legend sketch it also drops the **slanted**
strokes — the R's leg and both of the V's strokes have a minimum bbox dimension
of 2.5–3.3 mm — and the model built a **"P"** and a collapsed V while still
reporting the correct body count of 3. Caught in a one-second viewport capture,
invisible to every checksum. The rule is per-sketch: use the min-dimension filter
for orthogonal bar grids, and drop enclosed cells by **centroid-in-region** where
strokes are slanted. *Source wrong: `slab-run` B1, by over-generalisation.*

**F4 — grid blocks must be inset, not centred on the block outline. (NEW)**
PRD §3.2 states the blocks as `X −8.3 → 5.2` and `Y −141 → −127.6`. Bars centred
on those boundaries overhang by 0.4 mm each side and measure **80.3 mm²**. Bars
inset so their outer edges land *on* the outline measure **75.8 mm²** — exactly
the figure `slab-run` G7 records as the correct signature. 75.8 is therefore a
usable regression tell for the grid construction, not just a bound. *Source
wrong: neither; the PRD is ambiguous and the correct reading is recoverable from
the G7 reference value.*

**F5 — `Housing_Upper` face count is not a checksum.**
Measured **63 faces** against `slab-product-spec`'s recorded 78, while **both**
volume checksums are exact (219.091 and 149.056) and the notch and strip material
removals match closed-form to 0.1 mm³. Face count is a function of the build
path, not of the geometry. *Source wrong: `slab-product-spec`, for presenting it
alongside genuine checksums.*

**F6 — never delete a sketch by curve count.**
Removing the grid sketch by `sketchLines.count == 32` deleted the **legend**
sketch, which happened to have 32 lines; the grid sketch had 64. The legend
extrude survived on cached geometry with `healthState 1` and a "Profile 1
missing" reference failure while still reporting 3 healthy-looking bodies.
Delete the **extrude feature** and reach its sketch **by name**. *Source wrong:
none — a method error made during this run, recorded so the next run avoids it.*

**F7 — housing exposure gap.** See §4. Reported with the number attached,
per the two-finals rule.

**F8 — charge ports built; PRD §8 confirmed stale.**
Two 9.5 × 4.0 apertures on the −X face at Y −38.0 / −16.0, centred Z 13.5,
removing exactly 190.0 mm³ = 2 × 9.5 × 4.0 × 2.5 — clean through the 2.5 wall,
wholly inside the black base band, crossing no parting line. PRD §8 lists them as
"recorded as intent, absent from the measured model". *Source wrong: PRD §8;
`slab-product-spec` and `slab-run` are right.*

**F9 — `Panel_Control` built at the specified +59.5.**
Measured Y −46.000 … +165.000, restoring the intended 4.0 mm margin at the +Y
edge. Known-defect #2 is closed and was not reproduced.

**F10 — camera distance must be iterated.**
Assigning `camera.eye` at a chosen distance does not hold: Fusion rescales it to
preserve `viewExtents` (152 cm was silently rewritten to 247.6 cm, direction
preserved, a pure 1.629× scaling). Set the camera, read the achieved distance
back, scale `viewExtents` by `(target/actual)²`, and push again. Converges in one
iteration.

---

## 6. New open decisions

| ID | Decision | Owner | Due |
|---|---|---|---|
| TBD-17 | The waveform graphic (14 bodies) is required to reach the specified 50 panel graphics and is visible in both reference mockups, but is **not itemised in PRD §3.2**. Its position and 14-bar form are this run's interpretation. Itemise it or replace it. | ID | pre-drawing |
| TBD-18 | Legend glyph construction (stroke width 1.6, R/I/V forms) is unspecified. The PRD gives position and 9.5 mm height only. | ID | P2 |
| TBD-19 | Scale-tick baseline anchoring — PRD §3.2 gives "at Y −146.7" without stating whether that is the baseline or the centreline. Built as baseline, extending +Y. | ID | P2 |

**Do not re-raise DEC-C1 … DEC-C5.** Long axis is Y; 20 pots governs; no bezel and
the shortfall is met by a transport cover; no connector aperture crosses Z 23.0;
power toggle Y = +130.0.

---

## 7. Carried forward, still open

- **Zero named user parameters.** The model is hard-modelled throughout. No
  dimensional change can be made by editing a parameter, because there is none.
- No shaft holes in `Panel_Control` — 6 faces, a plain slab. Shaft Ø is unstated
  everywhere; volume arithmetic implies ≈ Ø8.3 through 2 mm (TBD-15).
- Rear I/O plate and recessed bay not built (DEC-C4 ruling, TBD-13).
- Orange speckle in the black panel, and in-panel legend text, not modelled.
- Draft angles and draft analysis not run.
- Boss positions predate the axis correction; boss-to-aperture ≥ 6.0 unimplemented
  (TBD-16).
- Layout checks 5 and 6 not implemented.
- Hidden internals — `SLAB_PCB_Main`, `SLAB_Battery_Pack`, `SLAB_Base_Hatch` —
  outside the 289 measured bodies.

**Mass is not quoted.** The whole-model figure of ~3915.8 g reflects default
material densities and is a coarse checksum only.

---

## 8. Deliverables

| File | What |
|---|---|
| `slab_hero.png` | 1593 × 1200 composited hero, calibrated camera |
| `slab_top.png` | 918 × 1400 composited orthographic plan |
| `slab_hero2_raw.png`, `slab_top2_raw.png` | raw quality-95 renders, pre-grade |
| `SLAB_GA_RevC.pdf` | A3 ISO general arrangement, 1:2.5, 3 dimensioned views + isometric with balloons, 12-row parts list, 13 notes |
| `views/` | orthographic line art; crop aspect error 0.04 % / 0.07 % / 0.11 % |
| `measure_classes.py` | class and ten-pad measurement used for §4 |

A native Fusion drawing document is also open in the session. **Fusion is now in
the Drawing workspace — a human must click back to the Design tab before the MCP
can operate on the model again.**
