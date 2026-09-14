#!/usr/bin/env python3
"""Pre-build layout check for SLAB — pure arithmetic, no Fusion, stdlib only.

Runs the four implemented layout checks against the specified control positions
BEFORE any geometry exists, so a clearance violation is caught in 30 ms instead
of after a 20-minute build.

Clearances are evaluated at the WIDEST section of each knob (small Ø13.5 base,
large Ø32), because that is where they govern. Evaluating a tapered knob at its
top diameter understates every gap.

Expected output on the correct model:
    worst knob-to-knob gap   13.000 mm   (two large knobs)
    worst knob-to-pad gap     7.700 mm   (Knob_Lg_1 <-> Pad_05)
    panel margin in recess    1.000 mm   all four sides
    worst pad inset           0.200 mm   (deliberate, edge pads)
    worst pad-to-panel gap    0.700 mm

Exit 0 = clean. Exit 1 = at least one violation.
"""
import math
import sys

# ── specified geometry (mm) ────────────────────────────────────────────────
HOUSING_X, HOUSING_Y = 195.0, 340.0          # half-extents +-97.5, +-170.0
RECESS_W, RECESS_H, RECESS_C = 137.0, 213.0, (0.0, 59.5)
PANEL_W, PANEL_H, PANEL_C = 135.0, 211.0, (0.0, 59.5)

KNOB_SM_BASE_D = 13.5                        # widest point
KNOB_LG_D = 32.0
SMALL_X = [-50.4, -16.8, 16.8, 50.4]
SMALL_Y = [28.0, 58.0, 88.0, 118.0, 148.0]
LARGE = [(-45.0, -23.0), (0.0, -23.0), (45.0, -23.0)]

PAD_SIDE = 18.6
PADS = [(-88, -56), (-44, -56), (0, -56), (44, -56), (88, -56),
        (-88, 76), (-88, -4),
        (88, 93), (88, 40), (88, -4)]

MIN_KNOB_GAP = 4.0                           # adult finger-and-thumb grip


def main():
    fail = 0
    knobs = ([("Knob_Sm_%02d" % (i + 1), x, y, KNOB_SM_BASE_D / 2)
              for i, (x, y) in enumerate((x, y) for x in SMALL_X for y in SMALL_Y)]
             + [("Knob_Lg_%d" % (i + 1), x, y, KNOB_LG_D / 2)
                for i, (x, y) in enumerate(LARGE)])
    pads = [("Pad_%02d" % (i + 1), x - PAD_SIDE / 2, y - PAD_SIDE / 2,
             x + PAD_SIDE / 2, y + PAD_SIDE / 2) for i, (x, y) in enumerate(PADS)]

    print("small knob Ø%.1f base -> Ø10.79 top (clearance checked at base)"
          % KNOB_SM_BASE_D)
    print("knobs=%d pads=%d" % (len(knobs), len(pads)))

    # 1 — pairwise knob gap, at the widest section
    worst, pair, v = 1e9, None, 0
    for i in range(len(knobs)):
        for j in range(i + 1, len(knobs)):
            a, b = knobs[i], knobs[j]
            g = math.hypot(a[1] - b[1], a[2] - b[2]) - a[3] - b[3]
            if g < worst:
                worst, pair = g, (a[0], b[0])
            if g < MIN_KNOB_GAP:
                v += 1
    print("  -> worst knob-to-knob gap %.3f mm on %s/%s, requirement %.1f mm"
          % (worst, pair[0], pair[1], MIN_KNOB_GAP))
    fail += v

    # 2 — knob vs pad
    worst, pair, v = 1e9, None, 0
    for k in knobs:
        for p in pads:
            dx = max(p[1] - k[1], 0, k[1] - p[3])
            dy = max(p[2] - k[2], 0, k[2] - p[4])
            g = math.hypot(dx, dy) - k[3]
            if g < worst:
                worst, pair = g, (k[0], p[0])
            if g < 0:
                v += 1
    print("  -> worst knob-to-pad gap %.3f mm on %s/%s, must be > 0"
          % (worst, pair[0], pair[1]))
    fail += v

    # 3 — panel containment inside the recess
    m = [(PANEL_C[0] - PANEL_W / 2) - (RECESS_C[0] - RECESS_W / 2),
         (PANEL_C[1] - PANEL_H / 2) - (RECESS_C[1] - RECESS_H / 2),
         (RECESS_C[0] + RECESS_W / 2) - (PANEL_C[0] + PANEL_W / 2),
         (RECESS_C[1] + RECESS_H / 2) - (PANEL_C[1] + PANEL_H / 2)]
    print("  -> panel margin in recess -X %.3f -Y %.3f +X %.3f +Y %.3f mm"
          % tuple(m))
    fail += sum(1 for x in m if x < 0)

    # 4 — pads inside the housing outline and clear of the panel
    hx, hy = HOUSING_X / 2, HOUSING_Y / 2
    px0, py0 = PANEL_C[0] - PANEL_W / 2, PANEL_C[1] - PANEL_H / 2
    px1, py1 = PANEL_C[0] + PANEL_W / 2, PANEL_C[1] + PANEL_H / 2
    worst_h, worst_p, v = 1e9, 1e9, 0
    for p in pads:
        ins = min(p[1] + hx, hx - p[3], p[2] + hy, hy - p[4])
        worst_h = min(worst_h, ins)
        if ins < 0:
            v += 1
        dx = max(px0 - p[3], 0, p[1] - px1)
        dy = max(py0 - p[4], 0, p[2] - py1)
        d = math.hypot(dx, dy) if (dx > 0 or dy > 0) else -1.0
        worst_p = min(worst_p, d)
        if d < 0:
            v += 1
    print("  -> worst pad inset from housing outline %.3f mm (0.2 expected)"
          % worst_h)
    print("  -> worst pad-to-panel gap %.3f mm, must be > 0" % worst_p)
    fail += v

    print("checks 5 (indicator under knob) and 6 (boss-to-aperture >= 6.0) are "
          "NOT IMPLEMENTED and are not silently passing")

    if fail:
        print("LAYOUT CHECK FAILED — %d violation(s)" % fail)
        return 1
    print("all layout checks clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
