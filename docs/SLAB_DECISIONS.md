# SLAB — closed decisions and known defects

**This file is the decision register of record.**
**`/skill slab-product-spec` supersedes it on dimensions** — every figure there was measured in
a live Fusion session during a complete from-scratch rebuild. Precedence:
`/skill slab-run` → `/skill slab-product-spec` → this file → `docs/SLAB_PRD_RevC.pdf`. Everything recorded below
has been checked against the as-built spec and agrees with it.

Rev C of the brief settled three findings that earlier runs kept re-raising as
defects, and the rebuild settled four more. Report them all as **decided**, not
as findings, and do not gate on them. Re-opening a closed decision costs a
review round and produces a "correction" that makes the model wrong.

The second half of this file is the known-defects list — things that *are*
wrong, or that look wrong and are not. Read both before auditing anything.

---

## Decisions already closed — do NOT re-raise these

| Decision | Ruling |
|---|---|
| **DEC-C1** — axis convention | **The model is correct; the brief was rewritten.** **Long axis is Y, 340 mm. Short axis is X, 195 mm. Z is up, and the product's functional top — the edge away from the operator — is +Y.** Origin is centred in plan, Z = 0 is the ground plane, and a plain top view is therefore the human's view. Getting it wrong presents as "everything is 90 degrees off", text reading sideways, and left/right landing on the wrong edges. Do **not** propose rotating the model, and do **not** patch it with `occurrence.transform` — that resets on rebuild. Bake it into the geometry. **Parameter names are not evidence:** this register has historically called the 340 axis `Overall_Width` and Rev A §8.3 called the 195 axis `Overall_Width`, and 48 of 50 parameters drive nothing anyway (defect 1). Quote the geometry — **195 on X, 340 on Y** — never the name. The legacy `DTM_Rear` / `DTM_Front` datums are part of the same stale naming; the as-built spec does not record them. |
| **DEC-C2** — knob count | **20 pots (4 × 5) governs.** The 4 × 4 = 16 in Rev A is superseded. `Knob_Sm_Count = 20`. Do not "correct" the count downward. As built: 20 small-knob bodies at X **−50.4 / −16.8 / 16.8 / 50.4** and Y **28 / 58 / 88 / 118 / 148**, plus 3 large knobs — 23 knobs and 23 pointer inlays in total. |
| **DEC-C3** — the bezel | **Not to be built.** `Bezel_Height` stays **0**. The Section 8.4 backpack constraint is met by a transport cover accessory, not by enclosure geometry — an 18 mm perimeter wall would destroy the exposed-control-deck form that is the product's identity. Do not add a bezel. Do not flag the 15.6 mm shortfall as blocking. |
| **DEC-C4** — tick colour | **All 173 graduation ticks are black** — `SLAB_Knob_Black`. Not brown, and not white. `SLAB_Tick_Print` (92,46,22) is a defined appearance carrying **zero** bodies; it is a decoy, not a target. Do not "restore" brown ticks as a regression fix. |
| **DEC-C5** — pointer inlays | **Two-tone, by host knob.** `SLAB_Pointer_White` on the 20 black small knobs; `SLAB_Knob_Black` on the 3 orange large knobs. Identify them by **position, not name** — the large-knob inlays are the only pointers below **Y = 0** (Y −15.6, at X −45 / 0 / +45). Do not unify them to one colour. |
| **DEC-C6** — the keypad | **The 10 pads are lit buttons**, `SLAB_LED_Emissive`, with `opaque_emission` **True**, `opaque_luminance` **150.0** and `opaque_luminance_modifier` **(255,140,70)**. They are not printed ink and must not be approximated with a glossy orange. The same appearance carries the power LED — 11 bodies in total. |
| **DEC-C7** — section-divider direction | **The two verticals run DOWNWARD, toward the large knobs at Y −23, into the gaps between them.** Horizontal rule **132 × 0.9** at Y **+4**; verticals **0.9 × 47** at X **±22.5** spanning Y **+4 → −43**, centred Y −19.5; all raised **0.5** from Z 45.6 in `SLAB_Knob_Orange`. An earlier build ran them upward to Y +51, away from the knobs. That was wrong. Re-apply the appearance after any rebuild of this body — it has come back as `Body2` on `Steel - Satin` before, and it is the step that gets forgotten. |

### The one caveat on DEC-C3

DEC-C3 is a **working assumption pending PM and ID sign-off before tooling
release**. It is settled for CAD purposes only. If asked whether the design is
production-ready, say that this signature is outstanding — but never let it
block modelling or rendering.

The datasheet envelope is therefore **340 × 195 × 46 mm**, not the 64 mm Rev A
predicted, because there is no bezel.

### The small knob — Ø20 straight was evaluated and REJECTED

Rev A §8.3 used to list the small knobs as **Ø20 × 15** straight
cylinders. That form was built, judged **squat and crowded**, and rebuilt on
8 September 2026. The PRD has since been reconciled and now records the
rejection as a decision (§3.0 there); this entry stays as the canonical
statement.

The as-built form is **Ø13.5 base → Ø10.79 top, 15.5 mm tall, 5° draft
narrowing upward, 0.75 mm top edge round, smooth** — ratio 1.15, top-to-base
1.25 — built as one sketch of 20 circles at base diameter, one tapered extrude,
then one fillet over all 20 top edges. Base plane Z = 45.6 mm, top Z = 61.1 mm,
pitch X 33.6 / Y 30.0, centres X ∈ {−50.4, −16.8, 16.8, 50.4},
Y ∈ {28, 58, 88, 118, 148}. Ø13.5 is the **widest** section, so every clearance
is checked there. **Face count 8 is the signature of the rejected straight
form** — never adopt it as a baseline, and if a model shows it, that model has
rebuilt the defect.

Pointer inlays are 1.1 × 5.6 × 0.92 mm. Small knobs: offset **3.1** mm radially,
top at Z **61.15** against a 61.10 knob top. Large knobs: offset **7.35** mm,
top at Z **59.65** against a 59.60 knob top. **Both stand 0.05 mm proud, and
that is deliberate** — an inlay coplanar with its host face z-fights, and built
at exactly Z 59.60 the large-knob pointer rendered on one knob out of three with
identical, correct material on all three. **No inlay, decal plate or applied
marking may be coplanar with its host face; clear it by ≥ 0.05 mm.**

Large knobs are unchanged: **Ø32 × 14** at X = −45 / 0 / +45, Y = −23, Z 45.6 →
59.6, top edge round 1.10 mm, straight and not tapered. Do not apply the −5°
taper to these.

---

## Known defects — check these before trusting any change

1. **48 of 50 parameters drive nothing.** They were authored alongside
   hard-modelled features. Editing them moves no geometry. Only the Rev B
   small knobs are genuinely parameter-driven. Dimension a sheet from
   **measured** geometry — the live parameters read `Overall_Depth = 150`
   against a measured 195, `Knob_Pitch_X = 30` against a measured 33.6, and
   `Knob_Sm_Dia = 15.0` while the bodies were 20.0. **Never trust
   `get_parameters` as a description of the model.** Measure the bodies and
   diff. A parameter sitting at 0 is what an un-built feature looks like, not a
   zero-height feature.
2. ~~173 tick marks are scattered (OD-B4)~~ — **WITHDRAWN.** The orthographic
   top view shows them arranged in tidy radial arrays around each knob. The
   "scattered" reading came from judging a perspective render, where the arcs
   foreshorten into noise. Nothing to fix. **Judge layout orthographically.**
   The lesson generalises: judge *layout* from an orthographic view and never
   raise a geometry defect off a perspective render.
5. **Every appearance property write FORKS a duplicate.** This is the real
   hazard, and it is a from-scratch hazard — it happens on a clean build, not
   just on an inherited document. The appearance count was observed going
   **11 → 14 → 26 → 15 → 23** inside a single session. Three rules:
   - **Snapshot appearance *objects* before writing.** Never index
     `d.appearances` inside a write loop; the indices shift mid-loop and
     cross-contaminate. `SLAB_Knob_Black` ended up carrying `Panel_Dark`'s
     `opaque_albedo` and the LED's luminance exactly this way.
   - **Choose the canonical instance by VALUE READBACK, never by lowest
     index.** Lowest-index was tried and it selected forks carrying the wrong
     roughness.
   - **Consolidate to the canonical instance, then delete the orphans**, and
     re-audit. The end state is **10 appearances defined, 9 of them carrying
     bodies** — `SLAB_Tick_Print` is the deliberate decoy at zero (DEC-C4).

   Also set **both** `surface_albedo` and `opaque_albedo`. The raytracer uses
   `opaque_albedo` while the API shows you `surface_albedo`, so an audit on
   `surface_albedo` alone passes a wrong material — a shader reading back as
   (212,212,212) white rendered orange because `opaque_albedo` was still
   (255,122,48).

   *(The earlier version of this item reported two objects named
   `SLAB_Lens_Orange` and 11 orphaned legacy appearances. That was an artefact
   of the superseded document. It does not occur in a from-scratch build, and
   it is withdrawn — do not go looking for it.)*
6. **Face-level overrides survive body assignment.** `body.appearance = x` does
   **not** clear them. `Pad_05` carried a stray top-face appearance pointing at
   the old non-emissive material and rendered as a dead pad through five
   material passes. On a freshly built model, assigning the ten appearances
   cleared **265** face overrides — body assignment alone would have left every
   one of them wrong. **Run the face loop every time, including on geometry you
   have just created**, and re-run the face-override audit after any material
   work.
7. **Mass is not meaningful.** The whole-model figure of ~**3916 g** reflects
   default densities, not the real product. Do not quote it.

(The numbering is the register's own and is not contiguous — items 3 and 4 were
closed and struck before Rev C. Keep the identifiers stable rather than
renumbering, so a finding raised in an earlier run still resolves.)

---

## Where this bites, stage by stage

- **Build stage** — do not rotate the model (DEC-C1), do not drop to 16 knobs
  (DEC-C2), do not add a bezel (DEC-C3). Do not verify a taper by mass: frustum
  volume is symmetric in R and r, so an inverted taper is invisible to a mass
  check. Read the circular edge radii by Z instead.
- **Render stage** — the render *will* show controls standing proud of the
  46 mm housing, by up to 15.1 mm. That is the intended form under DEC-C3, not
  a conflict to surface. `SLAB_LED_Emissive` is a real emissive appearance
  (DEC-C6); do not approximate it with glossy colour, and re-derive its
  `opaque_luminance` whenever exposure changes — 150.0 is correct only for the
  current settings. Reach appearances by iterating `design.appearances`, never
  `itemByName`, and select the canonical fork by value readback (defect 5).
  **Never assign `backgroundEnvironment`** — assigned while `backgroundType` is
  SolidColor it does not raise, it kills the Fusion process, and `backgroundType`
  has no setter so Environment mode cannot be reached from the API at all.
- **Drawing stage** — carry DEC-C1 through DEC-C7 in the sheet notes as
  closed decisions. Judge layout from the orthographic top view. Dimension from
  measured geometry, not from parameters (defect 1). Do not quote assembly mass
  in the parts list.

## Still open

PRD §6 — the rear I/O (4 × combo, 6 × TRS, USB-C) is **suppressed**, so as it
stands the mixer has no inputs. **[HOLD-A]** (Neutrik NCJ6FI-V DXF) still
blocks the combo cutouts. Owner: ME, due before drawing release (TBD-13).
Un-suppressing it is a product decision, not a render fix or a drawing fix.

DEC-C3 is settled for CAD and render purposes only and is a **working
assumption pending PM and ID sign-off before tooling release**. See the caveat
above.

### `TODO(verify):` carried forward

Four items are genuinely unresolved. Carry them as open questions; do not close
them by guessing, and do not report them as defects.

1. **Shaft-hole diameter.** No shaft-hole Ø is stated anywhere. Panel volume
   before holes measured **56.97 cm³**; the historical "after 23 shaft holes"
   baseline is **54.48**, implying **2.49 cm³** of holes ≈ **Ø8.3** through
   2 mm. Confirm against the chosen potentiometer before adopting (TBD-15).
2. **The 7.35 mm large-knob pointer offset.** It is 3.1 × 32/13.5 — an
   assumption. The brief gives 3.1 once and it only fits the Ø13.5 knobs.
3. **No contact shadow.** With `isGroundDisplayed` True, `isGroundReflections`
   True and `groundOffset` 0.0, no contact shadow appears and the product reads
   as floating. The reference has a clear soft shadow. Cause unknown.
4. **The LED "bright core" look.** Emission renders flat, with no light spill
   and no halo — Fusion does not bloom. The reference LEDs show a bright core
   with falloff; that is either a post-process step, or a higher luminance
   paired with a lower `brightness`. Not yet solved.
