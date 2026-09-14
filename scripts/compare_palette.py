#!/usr/bin/env python3
"""Quantitative render-vs-reference comparison.

Separates the subject from the seamless background, then k-means clusters the
subject pixels into a material palette. Comparing palettes between the
reference photo and a Fusion render tells us numerically which material is
too dark / too saturated / too flat, instead of eyeballing it.
"""
import sys
import numpy as np
from PIL import Image


def load(path, max_dim=700):
    im = Image.open(path).convert("RGB")
    im.thumbnail((max_dim, max_dim), Image.LANCZOS)
    return np.asarray(im).astype(np.float32)


def split_bg(a, tol=14.0):
    """Background = pixels near the median of the four corner patches."""
    h, w, _ = a.shape
    k = max(4, min(h, w) // 25)
    corners = np.concatenate([
        a[:k, :k].reshape(-1, 3), a[:k, -k:].reshape(-1, 3),
        a[-k:, :k].reshape(-1, 3), a[-k:, -k:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    dist = np.linalg.norm(a - bg, axis=2)
    mask = dist > tol           # True = subject
    return bg, mask


def kmeans(X, k=6, iters=40, seed=0):
    rng = np.random.default_rng(seed)
    C = X[rng.choice(len(X), k, replace=False)]
    for _ in range(iters):
        d = ((X[:, None, :] - C[None, :, :]) ** 2).sum(2)
        lab = d.argmin(1)
        for j in range(k):
            m = lab == j
            if m.any():
                C[j] = X[m].mean(0)
    d = ((X[:, None, :] - C[None, :, :]) ** 2).sum(2)
    lab = d.argmin(1)
    return C, lab


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def sat(c):
    mx, mn = float(max(c)), float(min(c))
    return 0.0 if mx == 0 else (mx - mn) / mx


def report(path, k=6):
    a = load(path)
    bg, mask = split_bg(a)
    X = a[mask]
    if len(X) > 60000:
        X = X[np.random.default_rng(0).choice(len(X), 60000, replace=False)]
    C, lab = kmeans(X, k)
    order = np.argsort([lum(c) for c in C])
    print(f"\n=== {path.split('/')[-1]} ===")
    print(f"  size(sampled) {a.shape[1]}x{a.shape[0]}  subject={100*mask.mean():.1f}% of frame")
    print(f"  BACKGROUND  rgb({bg[0]:.0f},{bg[1]:.0f},{bg[2]:.0f})  lum={lum(bg):.0f}")
    print("  --- subject material palette (dark -> light) ---")
    for j in order:
        share = 100.0 * (lab == j).mean()
        c = C[j]
        print(f"   rgb({c[0]:6.1f},{c[1]:6.1f},{c[2]:6.1f})  lum={lum(c):6.1f} "
              f" sat={sat(c):.2f}  {share:5.1f}% of subject")
    sub = X
    print(f"  subject mean lum={lum(sub.mean(0)):.1f}  "
          f"contrast(p95-p5 lum)={np.percentile(sub@[.2126,.7152,.0722],95)-np.percentile(sub@[.2126,.7152,.0722],5):.1f}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
