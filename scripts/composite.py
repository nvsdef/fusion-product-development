#!/usr/bin/env python3
"""Composite a Fusion render onto a studio background matching the reference.

Fusion's start_render(transparent_background=True) writes a uniformly-zero
alpha channel, so the matte is useless. It does however render onto a
perfectly flat plate with zero noise, which keys cleanly by flood-fill. The
plate colour is READ FROM THE FRAME, never assumed: it was rgb(243,243,243) at
one exposure and rgb(178,178,178) at another.

Steps: key the flat plate -> flood-fill from the border so bright interior
highlights are not punched out -> lay a fitted gradient background -> add a
soft contact shadow -> crop to the reference aspect.

Reference background plane (measured): lum = 199.7 - 21.8*x - 28.2*y
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

REF_ASPECT = 1232.0 / 928.0     # default; override with --aspect


def plate_colour(rgb):
    """The plate is whatever colour fills most of the frame.

    Do NOT hard-code it. It was 243 grey at one exposure and 178 at another,
    and a wrong plate colour inverts the matte completely.
    """
    q = (rgb.reshape(-1, 3) // 2 * 2).astype(np.int32)
    keys, counts = np.unique(q[:, 0] * 65536 + q[:, 1] * 256 + q[:, 2],
                             return_counts=True)
    k = int(keys[counts.argmax()])
    return np.array([k >> 16, (k >> 8) & 255, k & 255], dtype=np.float32)


def key(rgb, tol=6.0, feather=1.2):
    """Hard flood-fill matte. 1 = subject.

    The plate is perfectly flat with zero noise, so **connectivity** defines
    the background, not colour distance. This matters: at a correctly derived
    exposure the grey housing renders within ~8 levels of the plate, so the old
    distance ramp (lo=3, hi=12) gave it alpha ~0.55 -- the product came out
    HALF TRANSPARENT and the backdrop and contact shadow bled through it as a
    smear. Nothing about that reads as a keying bug; it reads as a bad render.

    PIL's ImageDraw.floodfill silently does nothing on some Pillow builds
    (it returned a mask with no filled pixels at all), so the fill is explicit.
    """
    from collections import deque
    plate = plate_colour(rgb)
    close = np.linalg.norm(rgb - plate, axis=2) <= tol
    h, w = close.shape
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if close[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if close[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and close[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((ny, nx))
    a = (~seen).astype(np.float32)
    return np.asarray(Image.fromarray((a * 255).astype(np.uint8), "L")
                      .filter(ImageFilter.GaussianBlur(feather))) / 255.0


def gradient(h, w, c0=199.7, cx=-21.8, cy=-28.2):
    ys, xs = np.mgrid[0:h, 0:w]
    g = c0 + cx * (xs / w) + cy * (ys / h)
    # faint radial falloff so it reads as a lit seamless, not a flat ramp
    r = np.sqrt(((xs / w - 0.42) ** 2) * 1.1 + ((ys / h - 0.32) ** 2))
    g = g + 9.0 * (0.45 - np.clip(r, 0, 0.9))
    return np.dstack([g, g, g])


def contact_shadow(a, dx=-10, dy=16, blur=34, strength=0.40, squash=0.42):
    """Fake floor shadow: squash the matte toward its base, offset, blur."""
    h, w = a.shape
    ys, xs = np.nonzero(a > 0.5)
    if len(ys) == 0:
        return np.zeros_like(a)
    base = ys.max()
    src = Image.fromarray((a * 255).astype(np.uint8), "L")
    sq = src.transform((w, h), Image.AFFINE,
                       (1, 0, -dx, 0, 1 / squash, -(base * (1 / squash - 1)) - dy),
                       resample=Image.BILINEAR)
    sh = np.asarray(sq.filter(ImageFilter.GaussianBlur(blur))) / 255.0
    return np.clip(sh * strength, 0, 1)


def plan_shadow(a, dx=16, dy=20, blur=30, strength=0.30):
    """Plain offset-and-blur drop shadow, for orthographic plan views.

    contact_shadow squashes the matte toward its base, which is right for a
    three-quarter hero and produces a visible SMEAR across the middle of a top
    view -- there is no floor in a plan projection to squash onto.
    """
    h, w = a.shape
    src = Image.fromarray((a * 255).astype(np.uint8), "L")
    off = src.transform((w, h), Image.AFFINE, (1, 0, -dx, 0, 1, -dy),
                        resample=Image.BILINEAR)
    return np.clip(np.asarray(off.filter(ImageFilter.GaussianBlur(blur))) / 255.0
                   * strength, 0, 1)


def shoulder(rgb, knee=185.0, gain=29.0, tau=32.0):
    """Filmic highlight rolloff.

    Fusion's raytracer returns a near-linear response that clips: the lit top
    face lands at 216 where the reference photo sits at 203, while the shaded
    faces already match. A real camera's shoulder compresses only the top end.
    This leaves everything below `knee` untouched and rolls 255 -> ~211.

    Applied to luminance and scaled back onto RGB, so chroma is preserved. A
    per-channel curve clips the strong channel of a saturated colour hardest
    and visibly desaturates it (the orange LEDs went pale tan).
    """
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    new = lum.copy()
    hi = lum > knee
    new[hi] = knee + gain * (1.0 - np.exp(-(lum[hi] - knee) / tau))
    scale = np.where(lum > 1e-3, new / np.maximum(lum, 1e-3), 1.0)
    return np.clip(rgb * scale[..., None], 0, 255)


def bloom(rgb, sat_min=0.35, lum_min=176.0, radii=(10, 30), gains=(0.17, 0.09)):
    """Additive glow around the emissive LEDs.

    Fusion renders emissive faces as flat colour with no light spill; the
    reference photo shows a clear halo. Key on saturated warm pixels only, so
    the white housing does not bloom.
    """
    mx = rgb.max(2)
    sat = np.where(mx > 1, (mx - rgb.min(2)) / np.maximum(mx, 1), 0)
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    m = ((sat > sat_min) & (lum > lum_min)).astype(np.float32)
    src = rgb * m[..., None]
    out = np.zeros_like(rgb)
    for r, g in zip(radii, gains):
        blurred = np.dstack([
            np.asarray(Image.fromarray(src[..., c].astype(np.uint8), "L")
                       .filter(ImageFilter.GaussianBlur(r))).astype(np.float32)
            for c in range(3)])
        out += blurred * g
    return out


def main(src, dst, crop=True, aspect=None, plan=False, bloom_kw=None):
    global REF_ASPECT
    if aspect:
        REF_ASPECT = aspect
    im = Image.open(src).convert("RGB")
    rgb = np.asarray(im).astype(np.float32)
    h, w, _ = rgb.shape
    a = key(rgb)
    rgb = shoulder(rgb)
    bg = gradient(h, w)
    sh = plan_shadow(a) if plan else contact_shadow(a)
    bg = bg * (1.0 - sh[..., None] * 0.85)
    out = bg * (1 - a[..., None]) + rgb * a[..., None]
    out = out + bloom(rgb * a[..., None], **(bloom_kw or {}))  # spills onto housing and plate
    out = np.clip(out, 0, 255).astype(np.uint8)
    im2 = Image.fromarray(out)
    if crop:
        ys, xs = np.nonzero(a > 0.02)
        cx = (xs.min() + xs.max()) // 2
        cy = (ys.min() + ys.max()) // 2
        cw = int(h * REF_ASPECT)
        if cw > w:
            cw, ch = w, int(w / REF_ASPECT)
        else:
            ch = h
        x0 = int(np.clip(cx - cw // 2, 0, w - cw))
        y0 = int(np.clip(cy - ch // 2, 0, h - ch))
        im2 = im2.crop((x0, y0, x0 + cw, y0 + ch))
    im2.save(dst)
    print(f"wrote {dst}  {im2.size[0]}x{im2.size[1]}  subject={100*(a>0.5).mean():.1f}% of plate")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--aspect", type=float, default=None,
                    help="output aspect w/h, e.g. 1.328 hero, 0.656 plan")
    ap.add_argument("--plan", action="store_true",
                    help="orthographic top view: offset shadow, not squashed")
    ap.add_argument("--bloom-gains", default=None,
                    help="two comma-separated gains, e.g. 0.10,0.055")
    ap.add_argument("--bloom-lum-min", type=float, default=None)
    a = ap.parse_args()
    bk = {}
    if a.bloom_gains:
        bk["gains"] = tuple(float(v) for v in a.bloom_gains.split(","))
    if a.bloom_lum_min is not None:
        bk["lum_min"] = a.bloom_lum_min
    main(a.src, a.dst, aspect=a.aspect, plan=a.plan, bloom_kw=bk or None)
