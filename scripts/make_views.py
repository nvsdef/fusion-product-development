#!/usr/bin/env python3
"""Turn Fusion wireframe viewport captures into black-on-white drawing views.

Input:  ln_top.png, ln_front.png, ln_right.png, ln_iso.png -- square captures
        written by Viewport.saveAsImageFile with the viewport set to
        OrthographicCameraType + WireframeWithVisibleEdgesOnlyVisualStyle.
        See the parent SKILL.md for the capture snippet; do NOT use
        export_view_sheet, which clips the elevations against its own frame.

Output: top_line.png, front_line.png, right_line.png, iso_line.png, cropped so
        that the crop edges ARE the model's true bounding box, which is what
        makes millimetre-accurate placement on the sheet possible.

    python make_views.py --dir ./views --target-z 30.6 \
        --bbox=-99.52,97.52,-170.02,170.02,-0.03,61.18

NOTE the '=' on --bbox. The value starts with a minus sign, so the space form
is swallowed by argparse as an option.

Two things this handles that a naive ink-bbox crop does not:

1. On a dark Fusion theme the model edges are DARKER than the plate and the
   grid is LIGHTER, so ink is (plate - lum), and `plate` must be the MODAL
   luminance of the frame. A corner pixel is not safe -- it can land on a grid
   line, which inverts the entire mask.
2. The world-origin marker projects ~21 px BELOW the model in both elevations
   and adds ~3.8 mm of apparent Z to an ink-bbox crop. Hiding the origin,
   sketch and construction folders on every component does NOT remove it.
   So: drop blue-tinted pixels, and crop the elevations ANALYTICALLY from the
   known camera rather than from the ink bounds.
"""
import argparse
import os

import numpy as np
from PIL import Image


def to_ink(a, blue_reject=30.0, floor=0.14):
    """Dark-plate capture -> ink strength in 0..1. Grid (lighter) becomes 0."""
    lum = a.mean(2)
    vals, counts = np.unique(np.round(lum).astype(np.int32), return_counts=True)
    plate = float(vals[counts.argmax()])
    neutral = (a[..., 2] - a[..., 0]) < blue_reject      # drop the blue Z axis
    ink = np.clip((plate - lum) / max(plate, 1.0), 0.0, 1.0) * neutral
    ink[ink < floor] = 0.0
    return ink


def save(ink, box, path, gain=1.55):
    x0, x1, y0, y1 = [int(round(v)) for v in box]
    sub = ink[max(y0, 0):y1, max(x0, 0):x1]
    img = (255 * (1.0 - np.clip(sub * gain, 0, 1))).astype(np.uint8)
    Image.fromarray(np.dstack([img] * 3)).save(path)
    return sub.shape[1], sub.shape[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=".")
    ap.add_argument("--bbox", required=True,
                    help="x0,x1,y0,y1,z0,z1 of the model in mm")
    ap.add_argument("--target-z", type=float, required=True,
                    help="camera target Z in mm (the elevations centre on it)")
    ap.add_argument("--scale", type=float, default=None,
                    help="px/mm; derived from the top view's ink bbox if omitted")
    ap.add_argument("--centre", type=float, default=None,
                    help="image centre px; defaults to width/2")
    ap.add_argument("--clear-origin", default=None, metavar="HALFW,H",
                    help="whiten a HALFW x H mm box at the projected origin in "
                         "the elevations, e.g. 22,3.4. The origin marker leaves "
                         "a small chevron there even after the blue reject. "
                         "ONLY use this when the model has no geometry at plan "
                         "centre near the floor -- verify before enabling.")
    a = ap.parse_args()
    x0, x1, y0, y1, z0, z1 = [float(v) for v in a.bbox.split(",")]

    top = np.array(Image.open(os.path.join(a.dir, "ln_top.png"))
                   .convert("RGB")).astype(np.float32)
    ink_top = to_ink(top)
    C = a.centre if a.centre is not None else top.shape[1] / 2.0

    # Calibrate on the TOP view: in plan the origin marker sits inside the
    # silhouette, so its ink bounds are the true bounding box.
    ys, xs = np.nonzero(ink_top > 0.18)
    S = a.scale if a.scale else (xs.max() - xs.min() + 1) / (x1 - x0)

    px = lambda u: C + u * S                       # model mm -> px, horizontal
    py = lambda v: C - (v - a.target_z) * S        # model mm -> px, elevations

    plan = {
        "top":   ("ln_top.png",   (px(x0), px(x1), C - y1 * S, C - y0 * S),
                  (x1 - x0, y1 - y0)),
        "front": ("ln_front.png", (px(x0), px(x1), py(z1), py(z0)),
                  (x1 - x0, z1 - z0)),
        # looking from +X with up +Z, screen-right is -Y, so the span is symmetric
        "right": ("ln_right.png", (C - y1 * S, C - y0 * S, py(z1), py(z0)),
                  (y1 - y0, z1 - z0)),
    }
    co = None
    if a.clear_origin:
        hw, ch = [float(v) for v in a.clear_origin.split(",")]
        co = (hw, ch)

    print("px/mm = %.4f" % S)
    for name, (src, box, exp) in plan.items():
        img = np.array(Image.open(os.path.join(a.dir, src))
                       .convert("RGB")).astype(np.float32)
        ink = to_ink(img)
        if co and name != "top":
            # plan-centre column, from the model floor up
            ctr = px(0.0) if name == "front" else (C - 0.0 * S)
            xa, xb = int(ctr - co[0] * S), int(ctr + co[0] * S)
            ya, yb = int(py(z0 + co[1])), int(py(z0))
            ink[max(ya, 0):yb, max(xa, 0):xb] = 0.0
        w, h = save(ink, box, os.path.join(a.dir, name + "_line.png"))
        err = abs((w / h) / (exp[0] / exp[1]) - 1) * 100
        flag = "" if err < 1.0 else "   <-- CHECK"
        print("  %-6s %4dx%-4d  ext %.2f x %.2f  aspect err %.2f%%%s"
              % (name, w, h, exp[0], exp[1], err, flag))

    iso_p = os.path.join(a.dir, "ln_iso.png")
    if os.path.exists(iso_p):
        ink = to_ink(np.array(Image.open(iso_p).convert("RGB")).astype(np.float32))
        ys, xs = np.nonzero(ink > 0.18)
        w, h = save(ink, (xs.min(), xs.max() + 1, ys.min(), ys.max() + 1),
                    os.path.join(a.dir, "iso_line.png"))
        print("  %-6s %4dx%-4d  (ink bbox; carries no dimensions)" % ("iso", w, h))


if __name__ == "__main__":
    main()
