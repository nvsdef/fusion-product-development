#!/usr/bin/env python3
"""Compose an A3 dimensioned general-arrangement drawing with a parts list.

Fusion's Drawing API cannot create a drawing document (see the parent SKILL.md),
so the sheet is composed here instead: border with zone markers, title block,
parts list, orthographic line-art views at true scale, an isometric with
balloons, dimensions and notes.

Driven entirely by a JSON spec so it works for any product. See
`slab_sheet.json` for a worked example.

    python make_drawing.py sheet.json -o out.pdf --views-dir ./views

Prerequisites for the view PNGs -- render them with the viewport set to
OrthographicCameraType + WireframeWithVisibleEdgesOnlyVisualStyle, otherwise
you get shaded perspective product photos rather than drawing views.

CRITICAL: dimension values in the spec must come from MEASURED body geometry,
not from the CAD model's user parameters. Parameters routinely drift from the
geometry they are supposed to drive.
"""
import argparse
import json
import os

import numpy as np
from PIL import Image
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

MASK = [252, 255, 252, 255, 252, 255]      # pure white -> transparent


# --------------------------------------------------------------------------
def view_img(path):
    """Crop to the ink bounding box and force the plate to pure white.

    The crop edges ARE the model's true bounding box, which is what makes
    millimetre-accurate placement possible. The plate renders at ~242 grey;
    reportlab's mask needs pure white or a grey rectangle shows behind the view.
    """
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.int16)
    lum = a.mean(2)
    ys, xs = np.nonzero(lum < 200)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    a[a.mean(2) > 205] = 255
    return Image.fromarray(a.astype(np.uint8))


def arrow(c, x, y, ux, uy):
    s, sp = 1.7, 0.32
    ang = np.arctan2(uy, ux)
    for d in (sp, -sp):
        c.line(x * mm, y * mm,
               (x - s * np.cos(ang + d)) * mm, (y - s * np.sin(ang + d)) * mm)


def dim_h(c, x1, x2, y, text, ext_to=None):
    c.setLineWidth(0.25)
    if ext_to is not None:
        for xx in (x1, x2):
            c.line(xx * mm, ext_to * mm,
                   xx * mm, (y + (1.6 if y > ext_to else -1.6)) * mm)
    c.line(x1 * mm, y * mm, x2 * mm, y * mm)
    arrow(c, x1, y, -1, 0)
    arrow(c, x2, y, 1, 0)
    c.setFont("Helvetica", 6)
    c.drawCentredString((x1 + x2) / 2 * mm, (y + 1.1) * mm, text)


def dim_v(c, y1, y2, x, text, ext_to=None):
    c.setLineWidth(0.25)
    if ext_to is not None:
        for yy in (y1, y2):
            c.line(ext_to * mm, yy * mm,
                   (x + (1.6 if x > ext_to else -1.6)) * mm, yy * mm)
    c.line(x * mm, y1 * mm, x * mm, y2 * mm)
    arrow(c, x, y1, 0, -1)
    arrow(c, x, y2, 0, 1)
    c.saveState()
    c.translate((x - 1.1) * mm, (y1 + y2) / 2 * mm)
    c.rotate(90)
    c.setFont("Helvetica", 6)
    c.drawCentredString(0, 0, text)
    c.restoreState()


def balloon(c, bx, by, px, py, text):
    c.setLineWidth(0.25)
    c.setFillColorRGB(0, 0, 0)
    c.line(bx * mm, by * mm, px * mm, py * mm)
    c.circle(px * mm, py * mm, 0.9 * mm, stroke=1, fill=0)
    c.circle(bx * mm, by * mm, 2.7 * mm, stroke=1, fill=1)
    c.setFillColorRGB(1, 1, 1)
    c.setFont("Helvetica-Bold", 6)
    c.drawCentredString(bx * mm, (by - 0.95) * mm, text)
    c.setFillColorRGB(0, 0, 0)


# --------------------------------------------------------------------------
def build(spec, out, views_dir):
    S = spec["scale"]
    L = spec["layout"]
    V = spec["views"]

    c = canvas.Canvas(out, pagesize=landscape(A3))

    # border + zone markers
    c.setLineWidth(0.7); c.rect(10 * mm, 10 * mm, 400 * mm, 277 * mm)
    c.setLineWidth(0.25); c.rect(13 * mm, 13 * mm, 394 * mm, 271 * mm)
    c.setFont("Helvetica", 7)
    for i, lab in enumerate("4321"):
        xz = 10 + 400 * (i + 0.5) / 4
        c.drawCentredString(xz * mm, 285.5 * mm, lab)
        c.drawCentredString(xz * mm, 10.6 * mm, lab)
    for i, lab in enumerate("ABCD"):
        yz = 10 + 277 * (i + 0.5) / 4
        c.drawCentredString(11.3 * mm, yz * mm, lab)
        c.drawCentredString(408.6 * mm, yz * mm, lab)

    # orthographic views
    placed = {}
    for name, v in V.items():
        if name == "iso":
            continue
        x, y = L[name]
        w, h = v["ext"][0] / S, v["ext"][1] / S
        c.drawImage(ImageReader(view_img(os.path.join(views_dir, v["file"]))),
                    x * mm, y * mm, width=w * mm, height=h * mm, mask=MASK)
        placed[name] = (x, y, w, h)
        c.setFont("Helvetica-Bold", 7)
        c.drawString(x * mm, (y - 4.5) * mm, name.upper())

    # isometric
    if "iso" in V:
        im = view_img(os.path.join(views_dir, V["iso"]["file"]))
        ix, iy = L["iso"]
        iw = V["iso"]["width_mm"]
        ih = iw * im.size[1] / im.size[0]
        c.drawImage(ImageReader(im), ix * mm, iy * mm,
                    width=iw * mm, height=ih * mm, mask=MASK)
        c.setFont("Helvetica-Bold", 7)
        c.drawString(ix * mm, (iy - 4.5) * mm, "ISOMETRIC")
        for b in spec.get("balloons", []):
            balloon(c, ix + b["bx"] * iw, iy + b["by"] * ih,
                    ix + b["px"] * iw, iy + b["py"] * ih, b["text"])

    # dimensions -- 'from'/'to' are millimetres along the view's own axis,
    # measured from the view's lower-left corner
    for d in spec.get("dims", []):
        x, y, w, h = placed[d["view"]]
        off = d["offset"]
        if d["axis"] == "h":
            yy = (y + h + off) if off > 0 else (y + off)
            dim_h(c, x + d["from"] / S, x + d["to"] / S, yy, d["text"],
                  ext_to=(y + h) if off > 0 else y)
        else:
            xx = (x + w + off) if off > 0 else (x + off)
            dim_v(c, y + d["from"] / S, y + d["to"] / S, xx, d["text"],
                  ext_to=(x + w) if off > 0 else x)

    # parts list
    pl = spec["parts_list"]
    px, pw = pl["x"], pl["width"]
    colw = pl["col_widths"]
    rowh, top = 5.4, pl["top"]
    c.setFont("Helvetica-Bold", 7)
    c.drawString(px * mm, (top + 1.4) * mm, "PARTS LIST")
    y = top - 1.0
    c.setLineWidth(0.4)
    rows = [(pl["header"], True)] + [(r, False) for r in pl["rows"]]
    for vals, bold in rows:
        c.rect(px * mm, (y - rowh) * mm, pw * mm, rowh * mm)
        x = px
        c.setFont("Helvetica-Bold" if bold else "Helvetica", 5.4 if bold else 5.2)
        for w_, t in zip(colw, vals):
            c.drawString((x + 1.2) * mm, (y - rowh + 1.8) * mm, str(t))
            x += w_
            c.line(x * mm, (y - rowh) * mm, x * mm, y * mm)
        y -= rowh
    if pl.get("footer"):
        c.setFont("Helvetica-Bold", 5.4)
        c.drawString((px + 1.2) * mm, (y - 3.6) * mm, pl["footer"])

    # notes
    nx, ny = spec["notes_at"]
    c.setFont("Helvetica-Bold", 6.5)
    c.drawString(nx * mm, ny * mm, "NOTES")
    c.setFont("Helvetica", 5.0)
    yy = ny - 5.0
    for ln in spec["notes"]:
        c.drawString(nx * mm, yy * mm, ln)
        yy -= 3.9

    # title block
    tb = spec["title_block"]
    tx, ty, tw2, thh = tb["x"], tb["y"], tb["width"], tb["height"]
    c.setLineWidth(0.7); c.rect(tx * mm, ty * mm, tw2 * mm, thh * mm)
    c.setLineWidth(0.25)
    for yy in (ty + 9, ty + 17, ty + 26):
        c.line(tx * mm, yy * mm, (tx + tw2) * mm, yy * mm)
    c.line((tx + 88) * mm, ty * mm, (tx + 88) * mm, (ty + 26) * mm)
    c.setFont("Helvetica-Bold", 11)
    c.drawString((tx + 3) * mm, (ty + 29.5) * mm, tb["product"])
    c.setFont("Helvetica", 6)
    c.drawString((tx + 3) * mm, (ty + 27.2) * mm, tb["subtitle"])
    c.setFont("Helvetica-Bold", 6)
    c.drawString((tx + 108) * mm, (ty + 29.5) * mm, "UNITS: mm")
    c.setFont("Helvetica", 5.5)
    for xx, yy, t in [
        (tx + 3,  ty + 21,   "TITLE:  " + tb["title"]),
        (tx + 3,  ty + 18.2, "MODEL:  " + tb["model"]),
        (tx + 91, ty + 21,   "REV:  " + tb["rev"]),
        (tx + 91, ty + 18.2, "DATE:  " + tb["date"]),
        (tx + 3,  ty + 11.5, "SCALE:  1:%g" % S),
        (tx + 91, ty + 11.5, "SHEET:  " + tb.get("sheet", "1 OF 1")),
        (tx + 3,  ty + 3.5,  "OWNER:  " + tb["owner"]),
        (tx + 91, ty + 3.5,  "SIZE:  A3"),
    ]:
        c.drawString(xx * mm, yy * mm, t)
    c.setFont("Helvetica-Oblique", 4.8)
    c.drawString(34 * mm, 15.5 * mm, spec.get("footer", ""))

    c.showPage()
    c.save()
    print("wrote %s  (scale 1:%g, %d parts rows, %d dims)"
          % (out, S, len(pl["rows"]), len(spec.get("dims", []))))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("spec", help="JSON sheet specification")
    ap.add_argument("-o", "--out", default=None, help="output PDF")
    ap.add_argument("--views-dir", default=".", help="folder holding the view PNGs")
    a = ap.parse_args()
    spec = json.load(open(a.spec, encoding="utf-8"))
    out = a.out or spec.get("out", "drawing.pdf")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    build(spec, out, a.views_dir)


if __name__ == "__main__":
    main()
