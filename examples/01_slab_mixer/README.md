# 01 — SLAB portable mixer

The reference workload. A portable 6-channel production mixer / USB-C audio
interface, built from nothing to a verified model, two calibrated renders, an A3
general arrangement drawing and a verification report.

**Target: 289 bodies, 12 components.** Cold build to delivered drawing, ~45 min.

## Files

| File | What it is |
|---|---|
| `prompt.md` | The run prompt — one paragraph plus three attachments. The skills carry the procedure and the numbers. |
| `expected.md` | The acceptance baseline. Read it **after** a run. |
| `reference/` | The two concept mockups. Supplied per-checkout, not committed. |

## Before you start

1. **Fusion open on a Design document.** Call `get_design_type` first; if it
   errors with `'Drawing' object has no attribute 'designType'`, a Drawing
   document is active and only a human clicking the Design tab can recover it.
2. **The agent on the same machine as Fusion.** A remote backend cannot reach a
   GUI application.
3. `python3 scripts/setup/verify_layout.py` — must exit 0.
4. Decide the document name. `SLAB_TOP` may already exist in the cloud project;
   either accept versioning or pick a new name, or the gate may pass against the
   old model.

## About the reference images

Two AI-generated concept mockups: one three-quarter hero (1232 × 928) and one
top-down plan (1178 × 1796). They are design intent for form, proportion and
CMF — **not** dimensional truth.

Three things to know before measuring against them:

- **Their legend text is nonsense.** Mask it before any pixel comparison.
- **They disagree with each other** — by 4.6 luminance levels on the housing
  class and 15.6 on the dark class. Converging on the midpoint moves you toward
  one and away from the other. Land inside the band and stop.
- **They are not traced.** Where a mockup and `/skill slab-product-spec`
  disagree, the spec governs. The one exception is documented: the power toggle's
  Y position was *recovered* from the plan mockup photogrammetrically, because
  the brief never stated it (DEC-C5).

## The four gates

| Gate | Cleared when |
|---|---|
| `geometry-signoff` | 289 bodies · 12 components · timeline clean · every stage volume met |
| `cmf-signoff` | 11 appearances · 0 mismatches · 0 unnamed bodies · 0 stray face overrides |
| `render-signoff` | LED pad G:R 0.55 ± 0.03 · exactly 10 pad blobs · per-channel spread ≤ 7 |
| `drawing-release` | crop-aspect error ≤ 0.11 % per view · sheet rasterised and inspected |

## Closed decisions

**DEC-C1 … DEC-C7 are closed.** Long axis is Y (340 mm); 20 pots (4 × 5)
governs; no bezel — the 17.180 mm shortfall is met by a transport cover; no
connector aperture crosses the Z 23.0 parting line; power toggle Y = +130.0.

A run that re-raises one of these has failed that check, not passed it.

## Known-open, and not failures

TBD-12 … TBD-19, listed in `expected.md` and `docs/SLAB_PRD_RevC.pdf` §11.2. The
largest is **TBD-14: the model carries zero named user parameters**, so no
dimensional change can be made parametrically. Carry them forward with the
number you actually used; closing one by guessing is the failure, and so is
reporting one as a defect.
