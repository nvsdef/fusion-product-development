#!/usr/bin/env python3
"""Measure a SLAB render or reference photo by material class, and run the
ten-pad connected-component check.

Why this exists: luminance alone accepts a blown LED pad, because the green
channel clips first. The accept test is two-part -- housing/dark luminance
AND the pad G:R ratio -- and the per-pad spread is the only thing that catches
a one-of-N defect such as a dead pad from a stray face override.

No scipy in the sandbox, so labelling is iterative max-propagation in numpy:
seed every masked pixel with its flat index, then repeatedly take the 4-
neighbour maximum inside the mask until stable. Converges in ~blob-diameter
iterations and is plenty fast at these sizes.
"""
import sys
import argparse
import numpy as np
from PIL import Image

LUMW = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def plate_colour(rgb, q=4):
    z = (rgb.reshape(-1, 3) // q * q).astype(np.int32)
    k, c = np.unique(z[:, 0] * 65536 + z[:, 1] * 256 + z[:, 2], return_counts=True)
    kk = int(k[c.argmax()])
    return np.array([kk >> 16, (kk >> 8) & 255, kk & 255], dtype=np.float32)


def subject_mask(rgb, plate, tol):
    """Flood-fill from the border over pixels close to the plate colour.

    Connectivity, not colour distance: at a correct exposure the grey housing
    sits within ~8 levels of the plate, so a distance ramp keys it half away.
    """
    close = np.linalg.norm(rgb - plate, axis=2) <= tol
    seen = np.zeros_like(close)
    seen[0, :] = close[0, :]; seen[-1, :] = close[-1, :]
    seen[:, 0] = close[:, 0]; seen[:, -1] = close[:, -1]
    while True:
        g = seen.copy()
        g[1:, :] |= seen[:-1, :]; g[:-1, :] |= seen[1:, :]
        g[:, 1:] |= seen[:, :-1]; g[:, :-1] |= seen[:, 1:]
        g &= close
        if g.sum() == seen.sum():
            break
        seen = g
    return ~seen


def label(mask):
    idx = np.arange(mask.size, dtype=np.int64).reshape(mask.shape)
    lab = np.where(mask, idx, -1)
    while True:
        g = lab.copy()
        g[1:, :] = np.maximum(g[1:, :], lab[:-1, :])
        g[:-1, :] = np.maximum(g[:-1, :], lab[1:, :])
        g[:, 1:] = np.maximum(g[:, 1:], lab[:, :-1])
        g[:, :-1] = np.maximum(g[:, :-1], lab[:, 1:])
        g = np.where(mask, g, -1)
        if np.array_equal(g, lab):
            return lab
        lab = g


def stats(px):
    lum = px @ LUMW
    gr = px[:, 1] / np.maximum(px[:, 0], 1.0)
    return dict(n=int(len(px)), rgb=px.mean(0).round(1).tolist(),
                lum=round(float(lum.mean()), 1), gr=round(float(gr.mean()), 3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("img")
    ap.add_argument("--tol", type=float, default=6.0)
    ap.add_argument("--min-blob", type=int, default=120)
    ap.add_argument("--label", default="")
    a = ap.parse_args()

    rgb = np.asarray(Image.open(a.img).convert("RGB")).astype(np.float32)
    plate = plate_colour(rgb)
    m = subject_mask(rgb, plate, a.tol)
    lum = rgb @ LUMW
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 1, (mx - mn) / np.maximum(mx, 1), 0)
    warm = (rgb[:, :, 0] > rgb[:, :, 2] + 25) & (sat > 0.28)

    housing = m & ~warm & (lum > 120)
    dark = m & ~warm & (lum <= 90)
    print(f"== {a.label or a.img}   {rgb.shape[1]}x{rgb.shape[0]}  plate={plate.astype(int).tolist()}")
    print(f"   subject {100*m.mean():.1f}% of frame")
    for nm, sel in (("housing", housing), ("dark", dark)):
        if sel.sum() > 50:
            s = stats(rgb[sel])
            print(f"   {nm:<9} n={s['n']:>8}  rgb={s['rgb']}  lum={s['lum']:>6}  G:R={s['gr']}")

    # warm blobs: separate lit pads from orange knobs
    wm = m & warm
    lab = label(wm)
    ids, cnt = np.unique(lab[lab >= 0], return_counts=True)
    blobs = []
    for i, c in zip(ids, cnt):
        if c < a.min_blob:
            continue
        sel = lab == i
        px = rgb[sel]
        ys, xs = np.nonzero(sel)
        s = stats(px)
        s["bbox"] = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        s["area"] = int(c)
        blobs.append(s)
    blobs.sort(key=lambda b: -b["area"])
    print(f"   warm blobs >= {a.min_blob}px: {len(blobs)}")
    # pads are emissive -> highest G:R; knobs are reflective orange -> lowest
    if blobs:
        gr = np.array([b["gr"] for b in blobs])
        split = (gr.max() + gr.min()) / 2 if gr.max() - gr.min() > 0.06 else 1e9
        pads = [b for b in blobs if b["gr"] >= split]
        knobs = [b for b in blobs if b["gr"] < split]
        for nm, grp in (("LED_PAD", pads), ("KNOB_ORANGE", knobs)):
            if not grp:
                continue
            w = np.array([b["area"] for b in grp], dtype=float)
            rgbm = (np.array([b["rgb"] for b in grp]) * w[:, None]).sum(0) / w.sum()
            lm = np.array([b["lum"] for b in grp])
            g = np.array([b["gr"] for b in grp])
            print(f"   {nm:<11} blobs={len(grp)}  rgb={rgbm.round(1).tolist()}  "
                  f"lum={lm.mean():.1f} [{lm.min():.1f}-{lm.max():.1f}]  "
                  f"G:R={g.mean():.3f} [{g.min():.3f}-{g.max():.3f}]")
            if nm == "LED_PAD":
                ch = np.array([b["rgb"] for b in grp])
                spread = (ch.max(0) - ch.min(0)).round(1)
                print(f"   {'':11} per-channel spread across {len(grp)} pads = {spread.tolist()}"
                      f"   (correct model <= 7 levels)")


if __name__ == "__main__":
    main()
