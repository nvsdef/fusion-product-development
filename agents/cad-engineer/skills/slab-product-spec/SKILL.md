---
name: slab-product-spec
description: The dimensional specification and build sequence for SLAB - every feature's three coordinates, absolute Z bands, body counts and checksums, the Fusion API utilities, the derivation rules, and numbered steps for all 12 feature classes. You write the geometry code; this tells you what to build and how to prove it. Use when building, modifying or checking any part of the SLAB model.
---

# SLAB — dimensional specification and build sequence

Portable 6-channel production mixer. **289 bodies, 12 components including root.**

**This file does not contain a build script.** It gives you everything needed to
write one yourself:

| § | What |
|---|---|
| 1 | **API utilities** — Fusion vocabulary, paste verbatim. Not design. |
| 2 | **Derivation rules** — how a dimension becomes a call |
| 3 | **Build sequence** — 12 classes, numbered steps, dimensions, checksums |
| 4 | Whole-model checks |
| 5 | CMF |
| 6 | Closed decisions |

You compose every sketch and extrude. The checksums tell you whether you got it
right; `fusion-scratch-build` §1 tells you what to do when one misses — reset,
rebuild twice, then **stop and report the numbers.**

**One exception, stated where it applies: the class 12 legend areas.** A legend
outside its band is recorded as an open item and the run continues — a malformed
letterform blocks nothing downstream. Every other checksum halts.

---

## 1 · API utilities

`execute_code` shares no state between calls. Paste these at the top of each one.
They are how the Fusion API works, not what SLAB is — the equivalent of a
utility module a human engineer would already have.

```python
import adsk.core, adsk.fusion, math
app  = adsk.core.Application.get()
des  = adsk.fusion.Design.cast(app.activeProduct)
root = des.rootComponent
V  = adsk.core.ValueInput.createByReal
P3 = adsk.core.Point3D.create
MM = lambda v: v / 10.0        # THE API IS IN CENTIMETRES. Every spec number is mm.

def comp(name):                # get-or-make: never fork a second component
    for o in root.occurrences:
        if o.component.name == name: return o.component
    o = root.occurrences.addNewComponent(adsk.core.Matrix3D.create())
    o.component.name = name
    return o.component

def plane(c, z_mm):            # ALWAYS from the component XY plane, absolute Z
    pi = c.constructionPlanes.createInput()
    pi.setByOffset(c.xYConstructionPlane, V(MM(z_mm)))
    return c.constructionPlanes.add(pi)

def allprof(sk):
    pf = adsk.core.ObjectCollection.create()
    for p in sk.profiles: pf.add(p)
    return pf

def extrude(c, profs, h_mm, taper_deg=0.0, cut=False):
    op = (adsk.fusion.FeatureOperations.CutFeatureOperation if cut
          else adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    ei = c.features.extrudeFeatures.createInput(profs, op)
    d  = adsk.fusion.DistanceExtentDefinition.create(V(MM(abs(h_mm))))
    dr = (adsk.fusion.ExtentDirections.NegativeExtentDirection if h_mm < 0
          else adsk.fusion.ExtentDirections.PositiveExtentDirection)
    if taper_deg: ei.setOneSideExtent(d, dr, V(math.radians(taper_deg)))
    else:         ei.setOneSideExtent(d, dr)
    return c.features.extrudeFeatures.add(ei)

def fillet_edges(c, edges, r_mm):
    fi = c.features.filletFeatures.createInput(); fi.isRollingBallCorner = True
    fi.addConstantRadiusEdgeSet(edges, V(MM(r_mm)), True)
    return c.features.filletFeatures.add(fi)

def vertical_edges(b):         # the 4 side edges of an extruded rectangle
    ed = adsk.core.ObjectCollection.create()
    for e in b.edges:
        g = e.geometry
        if g.objectType == adsk.core.Line3D.classType():
            d = g.startPoint.vectorTo(g.endPoint)
            if abs(d.x) < 1e-6 and abs(d.y) < 1e-6: ed.add(e)
    return ed

def circles_above(c, z_mm, tol=0.001):    # circular edges at/above a Z, for fillets
    ed = adsk.core.ObjectCollection.create()
    for b in c.bRepBodies:
        for e in b.edges:
            g = e.geometry
            if (g.objectType == adsk.core.Circle3D.classType()
                and g.center.z > MM(z_mm) - tol): ed.add(e)
    return ed

def face_at_z(b, z_mm):        # planar horizontal face, for shelling
    fs = adsk.core.ObjectCollection.create()
    for f in b.faces:
        g = f.geometry
        if (g.objectType == adsk.core.Plane.classType()
            and abs(g.normal.z) > 0.99 and abs(g.origin.z - MM(z_mm)) < 1e-4): fs.add(f)
    return fs

def shell(c, faces, wall_mm):
    si = c.features.shellFeatures.createInput(faces, False)
    si.insideThickness = V(MM(wall_mm))
    return c.features.shellFeatures.add(si)

def rect(sk, cx, cy, w, h):    # centre + size. USE THIS, never the raw API call.
    # addCenterPointRectangle's 2nd argument is an ABSOLUTE CORNER, not a
    # half-size. Passing (cx + w/2, h/2) silently drops the centre Y and you get
    # a rectangle of the wrong length in the right place. This wraps it.
    sk.sketchCurves.sketchLines.addCenterPointRectangle(
        P3(MM(cx), MM(cy), 0), P3(MM(cx + w/2.0), MM(cy + h/2.0), 0))

def circle(sk, cx, cy, d):     # centre + DIAMETER (the spec quotes diameters)
    sk.sketchCurves.sketchCircles.addByCenterRadius(P3(MM(cx), MM(cy), 0), MM(d/2.0))

def bar(sk, cx, cy, angle_deg, r0, r1, w):
    # ROTATED RECTANGLE — the vocabulary for every stroke that is NOT axis
    # aligned: graduation ticks, legend strokes, waveform bars. Angle is
    # measured FROM +Y, positive toward +X. Spans radius r0 -> r1, width w.
    a   = math.radians(angle_deg)
    rad = (-math.sin(a), math.cos(a))          # along the stroke, outward
    tan = ( math.cos(a), math.sin(a))          # across the stroke
    pts = [P3(MM(cx + rad[0]*r + tan[0]*s*w/2.0),
              MM(cy + rad[1]*r + tan[1]*s*w/2.0), 0)
           for r, s in ((r0, -1), (r1, -1), (r1, 1), (r0, 1))]
    for i in range(4):
        sk.sketchCurves.sketchLines.addByTwoPoints(pts[i], pts[(i+1) % 4])

def profile_extent(p):         # mm — check a profile is where you meant it
    bb = p.boundingBox
    return [round(bb.minPoint.x*10, 2), round(bb.minPoint.y*10, 2),
            round(bb.maxPoint.x*10, 2), round(bb.maxPoint.y*10, 2)]

def reset_component(c):        # MAKE EVERY CLASS RE-RUNNABLE. Call it first.
    for f in reversed(list(c.features)):
        try: f.deleteMe()
        except Exception: pass
    for b in list(c.bRepBodies):
        try: b.deleteMe()
        except Exception: pass
    for sk in list(c.sketches):
        try: sk.deleteMe()
        except Exception: pass
    for pl in list(c.constructionPlanes):
        try: pl.deleteMe()
        except Exception: pass
    return c.bRepBodies.count          # must be 0

def bbox(b):                   # mm — the primary checksum for every class
    x = b.boundingBox
    return [round(v*10, 3) for v in (x.minPoint.x, x.minPoint.y, x.minPoint.z,
                                     x.maxPoint.x, x.maxPoint.y, x.maxPoint.z)]

def radii(b):                  # circular edge radii by Z — the taper check
    return sorted([[round(e.geometry.center.z*10, 2), round(e.geometry.radius*10, 3)]
                   for e in b.edges if e.geometry.objectType == 'adsk::core::Circle3D'])

def top_area(b):               # largest horizontal planar face, mm^2
    return round(max([f.area*100 for f in b.faces
                      if f.geometry.surfaceType == 0
                      and abs(f.geometry.normal.z) > 0.99] + [0]), 1)
```

### The four accessors that get guessed wrong

These are **verified working through `execute_code` on this build.** Paste them;
do not search for them.

```python
lib = app.materialLibraries.itemByName('Fusion Appearance Library')
src = lib.appearances.itemByName('Plastic - Glossy (Black)')   # CMF source
ss  = des.renderManager.sceneSettings                          # brightness, cameraExposure
ws  = ui.workspaces.itemById('FusionRenderEnvironment')        # note: ui, not app
prop = ap.appearanceProperties.itemById('surface_albedo').value # Prism properties
```

**Wrong paths that raise `AttributeError`:** `app.materials`, `app.workspaces`,
`des.renderSettings`, `des.materials`. They do not exist. They are not disabled.

> **An `AttributeError` means your path is wrong - it never means the bridge is
> restricted.** `execute_code` runs inside Fusion with the full API surface. A run
> that hit `app.materials` concluded "the execute_code bridge has restricted
> access - no workspaces or materials", fell back to the `set_appearance` tool and
> a plain `.color`, and shipped ten appearances with none of the Prism ids set.
> The capability was there the whole time, one attribute name away.

Do not reason about what the bridge "supports". Fix the spelling and re-run.

**Draw rectangles with `rect(sk, cx, cy, w, h)` and circles with
`circle(sk, cx, cy, d)`** — centre and size, in mm, matching how the spec states
them. Both always close. Do not call `addCenterPointRectangle` directly: its
second argument is an **absolute corner**, and the natural-looking
`(cx + w/2, h/2)` drops the centre Y and gives a rectangle of the wrong length
in the right place. That exact slip produced a 137 x 94 panel recess instead of
137 x 213.

For anything else — slanted strokes, radial bars — build a closed polyline with
`addByTwoPoints` and check `sk.profiles.count` afterwards.

---

## 2 · Derivation rules

**R1 — Extrude distance is `Z_to - Z_from`.** Every class states an absolute Z
band. Sketch on `plane(c, Z_from)`, extrude the difference. Never chain off the
previous feature's plane; error accumulates and you land at Z -5.0 instead of 3.5.

**R2 — A rounded rectangle is a rectangle plus a vertical fillet.** Do not
hand-assemble one from lines and arcs — the loop fails to close, the sketch
yields 0 profiles, and the usual recovery forks a duplicate component. Rect ->
extrude -> `fillet_edges(c, vertical_edges(b), R)`. Face count 6 -> 10 is the
proof. Volume is identical to a rounded-rect extrusion.

**R3 — Assert `sk.profiles.count` before every extrude**, against the number you
expect. Zero means the outline did not close. Fix the sketch; never retry into a
new component.

**R3a — Check the profile's EXTENT, not only the count.** A count of 1 tells you
the loop closed; it says nothing about size or position. Before extruding, print
`profile_extent(p)` and compare it to the extent the spec implies:

```python
# panel recess: 137 x 213 centred (0, +59.5)  ->  [-68.5, -47.0, 68.5, 166.0]
assert profile_extent(sk.profiles.item(0)) == [-68.5, -47.0, 68.5, 166.0]
```

Every rectangle in this spec is stated as centre + size, so the expected extent
is `[cx-w/2, cy-h/2, cx+w/2, cy+h/2]`. Computing it and asserting it costs one
line and catches every arithmetic slip before it becomes a cut.

**R4 — N closed profiles in one extrude give N bodies** — unless they touch, in
which case touching ones merge into one connected body. Each class below says
which behaviour it relies on.

**R5 — Negative taper narrows in the extrude direction.** A knob widest at its
base, extruded +Z, needs `taper_deg = -5.0`. Mass, body count and bbox are all
blind to the sign, because a frustum's volume is symmetric in R and r. Only the
circular edge radii read against Z can see it.

**R6 — Cut with a negative distance, from a face that still exists.** Shell
first (the top face survives a bottom-face shell), then sketch on Z 46.0 and
extrude `-depth, cut=True`. A sketch on a datum plane over an already-shelled
body cuts nothing: "No target body found to cut".

**R7 — One feature class per `execute_code` call, one sketch per cut group.** A
recess, a set of notches and a set of strips are three features with three
volume deltas. Merged into one sketch you get a wrong total and no way to
localise it.

**R8a — Sketch on a CONSTRUCTION PLANE, never on a model face.** This is the
single most expensive mistake in this build.

A sketch created on a **face** inherits that face's boundary edges. Your
rectangle is then split where it crosses the face edge, and the *leftover* face
area becomes its own profile. You get far more profiles than shapes you drew:

| You drew | On a construction plane | On the model's top face |
|---|---|---|
| 1 recess rectangle | **1 profile** | **2** — your rect + the rest of the face |
| 4 notch rectangles (overhanging) | **4 profiles** | **10** — each splits at the edge |
| 6 strip rectangles | **6 profiles** | **11** |

**The symptom is a profile count higher than the number of shapes you drew.** If
you see that, you sketched on a face. `plane(c, 46.0)` returns a construction
plane and gives exactly what you drew — use it for every cut.

Do not "fix" an inflated count by filtering or clamping. That changes the removed
volume and the checksum will still miss.

**R8b — A cut profile that overhangs the body is correct.** The four edge
notches are 21 mm wide on X centred at X −90.2 and +91.0, so they deliberately
extend past the ±97.5 outline — that is what makes the silhouette step inward.
Fusion removes only the intersection with the solid. **Do not clamp the
rectangle to the outline.** Clamped notches remove the wrong volume and the
1241.0 mm³ check will fail.

**R9 — Every class must be re-runnable.** Start each one with:

```python
c = comp('SLAB_Housing_Upper')
if c.bRepBodies.count: reset_component(c)
```

Without it, a failed class that you retry leaves the first attempt behind and you
end up with `SLAB_Housing_Upper`, `(1)`, `(2)`, `(3)` — four identical bodies,
all wrong, and a body count that never reconciles. Retry means **rebuild the
class from clean**, not add another one.

**Retry a class at most twice** (same cap as `fusion-scratch-build` §1; the
three-attempt budget in `slab-run` is for *transport* failures, not geometry). If the same class misses its checksum on a
second clean rebuild, stop and report the measured-vs-expected numbers. A third
attempt has never been the one that works, and repeatedly building and deleting
the same geometry is the signature of a loop, not of progress. When you do
retry, change something specific and say what — "the recess profile measured
137 x 94, so I corrected the corner point" — not "trying again".

**R8 — Crossing bars enclose cells.** Overlapping bars offer more profiles than
bars: they split at intersections and each enclosed cell is a profile too.
Filter before extruding, and the filter depends on the shape:

- orthogonal bars -> keep profiles whose **minimum** bbox dimension <= the bar width
- slanted strokes (letterforms) -> that filter **deletes** them, because a
  diagonal's bbox is far wider than the stroke. Use a centroid-in-region test for
  the known enclosed area instead.

Report kept and rejected counts. A filter rejecting zero has proved nothing.

---

## 3 · Build sequence

Origin centred in plan, **Z 0 at the ground plane**. **+Y is the long axis, away
from the operator** (DEC-C1). All values mm.

**Envelope:** housing 195 (X) x 340 (Y) x 46 (Z) · corner radius 10.0 · wall 2.5
· split line Z 23.0 · feet Z 0->3.5 · **overall bbox 197.040 x 340.040 x 61.210**
(X -99.520...+97.520 · Y +/-170.020 · Z -0.030...61.180).

---

### Class 1 — `SLAB_Housing_Upper` · 1 body · Z 23.0 -> 46.0

1. Get the component. **If it already has bodies, `reset_component(c)` first** (R9).
2. Sketch on `plane(c, 23.0)`. One centre-point rectangle **195 x 340** at
   (0, 0). Assert **1 profile**.
3. Extrude **+23.0**. New body, name it.
4. Fillet the **4 vertical edges** at **R10** (R2). Faces 6 -> 10.
5. Shell **2.5**, removing the face at **Z 23.0** — the bottom.

> extrude **1522.926 cm3** · after shell **219.091 cm3**
> bbox `[-97.5, -170.0, 23.0, 97.5, 170.0, 46.0]`

---

### Class 2 — housing-upper cuts · still 1 body

Three separate cut features (R7), each on its own sketch. **Every one of them is
sketched on `plane(c, 46.0)` — a construction plane, not the body's top face
(R8a)** — and extruded **negative** (R6). Measure the volume after each.

Assert the profile count per sketch: recess **1**, notches **4**, strips **6**.
Anything higher means you sketched on a face.

Then assert each profile's **extent** (R3a). These are the values:

| Sketch | Expected profile extents, mm `[xmin, ymin, xmax, ymax]` |
|---|---|
| recess | `[-68.5, -47.0, 68.5, 166.0]` |
| notches | `[-100.7, 136.65, -79.7, 150.95]` · `[-100.7, 28.85, -79.7, 51.75]` · `[80.5, 134.75, 101.5, 144.25]` · `[80.5, 60.3, 101.5, 72.7]` |
| strips | X `[-97.5,-68.5]` and `[68.5,97.5]`, each at Y `[12.1,13.1]`, `[56.9,57.9]`, `[112.3,113.3]` |

A recess measuring `[-68.5, 12.5, 68.5, 106.5]` is the corner-point slip: right
width, right centre, **94 long instead of 213**. Use `rect()`.

| Cut | Qty | Plan size | Centre (X, Y) | Depth |
|---|---|---|---|---|
| Panel recess | 1 | 137 x 213 | (0, **+59.5**) | 2.4 |
| Edge notches | 4 | **21** x H | TL (-90.2, 143.8) H 14.3 · TR (91.0, 139.5) H 9.5 · ML (-90.2, 40.3) H 22.9 · MR (91.0, 66.5) H 12.4 | 1.2 |
| Strip cuts | 6 | 29 x 1.0 | X +/-83, Y 112.8 / 57.4 / 12.6 | 0.5 |

Notches are 21 wide on X, **overhanging the +/-97.5 outline** so the silhouette
steps inward. Their heights differ by design — do not make them uniform.

> after recess **149.056 cm3** · notches remove **1241.0-1241.4 mm3** (three runs measured 1241.0, 1241.0, 1241.4) · strips remove
> **87.0 mm3** · still 1 body

---

### Class 3 — `SLAB_Housing_Base` · 5 bodies

1. Sketch on `plane(c, 3.5)`, rectangle **195 x 340**. Extrude **+19.5**
   (-> Z 23.0). Fillet 4 vertical edges **R10**. Shell **2.5** removing the face
   at **Z 23.0** — the **top** this time.
2. Sketch on the component XY plane. Four **18 x 18** squares at X +/-77.5,
   Y +/-150. Extrude **+3.5** -> 4 foot bodies.
3. Charge ports: sketch on a plane offset from `yZConstructionPlane` at
   **X -97.5**. Two rectangles **9.5 (Y) x 4.0 (Z)** at Y **-38.0** and
   **-16.0**, centred **Z 13.5**. Extrude **+4.0 as a cut** (into the wall).
   Use `sk.modelToSketchSpace()` to place them so the sketch's own axes need no
   reasoning about.

> after shell **209.947 cm3** · bbox `[-97.5, -170.0, 3.5, 97.5, 170.0, 23.0]`
> · ports remove **190.0 mm3** · 5 bodies

---

### Class 4 — `SLAB_Panel_Control` · 1 body · Z 43.6 -> 45.6

1. Sketch on `plane(c, 43.6)`. One rectangle **135 x 211** centred
   (0, **+59.5**). **Sharp corners — no fillet.**
2. Extrude **+2.0**.

> **56.970 cm3** · **6 faces** · bbox `[-67.5, -46.0, 43.6, 67.5, 165.0, 45.6]`

The Y range -46.000...+165.000 is the tell it sits at +59.5 with its intended
4.0 mm margin at +Y. Plain slab, no shaft holes.

---

### Class 5 — `SLAB_Knob_Small` · 20 bodies · Z 45.6 -> 61.1

| | |
|---|---|
| Base dia | **13.5** — the widest point; evaluate every clearance here |
| Top dia | 10.79 (= 13.5 - 2*15.5*tan 5deg) |
| Draft | **5 deg narrowing upward** -> `taper_deg = -5.0` (R5) |
| Top edge round | **0.75** |
| Grid | X in {-50.4, -16.8, +16.8, +50.4} x Y in {28, 58, 88, 118, 148} |

1. Sketch on `plane(c, 45.6)`. **20 circles r 6.75** on the grid. Assert
   **20 profiles**.
2. One extrude, **+15.5**, `taper_deg = -5.0`. Assert **20 bodies**. Name them.
3. Collect circular edges above **Z 61.1** (`circles_above`). Assert **20 edges**.
   Fillet at **0.75**.

> **4 faces** per body · radii **`[[45.6, 6.75], [60.42, 5.454], [61.1, 4.707]]`**,
> decreasing with Z

3 faces means the fillet missed. Dia 20 x 15 straight cylinders are the
**rejected** Rev A form and **8 faces is its signature**.

---

### Class 6 — `SLAB_Knob_Large` · 3 bodies · Z 45.6 -> 59.6

1. Sketch on `plane(c, 45.6)`. **3 circles r 16.0** at X -45 / 0 / +45,
   **Y -23**. Assert 3 profiles.
2. Extrude **+14.0**, **no taper**.
3. Fillet circular edges above **Z 59.6** at **1.10**.

> 4 faces · radii `[[45.6, 16.0], [58.5, 16.0], [59.6, 14.9]]`

MASTER / PHONES / GLUE.

---

### Class 7 — `SLAB_Keypad` · 10 bodies · Z 44.2 -> 46.6

1. Sketch on `plane(c, 44.2)`. Ten **18.6 squares** at the centres below.
   Assert 10 profiles.
2. Extrude **+2.4** -> 10 bodies. Name them.
3. For **each body**, fillet its 4 vertical edges at **R3** (R2).

```
bottom : (-88,-56) (-44,-56) (0,-56) (44,-56) (88,-56)
left   : (-88, 76) (-88, -4)
right  : ( 88, 93) ( 88, 40) ( 88, -4)
```

> **10 faces** per body · 0.6 proud of the Z 46.0 face

Edge pads sit **0.200 mm** inside the housing outline. Deliberate — a layout
check using an arbitrary 1 mm margin produces seven false positives.

---

### Class 8 — `SLAB_Panel_Ticks` · 173 bodies · Z 45.6 -> 46.05

Radial bars, width **0.8**, raised **0.45**. Angles measured **from +Y**, spread
over **250 deg** (-125 to +125).

| Ring | Per knob | Radii | Step | Count |
|---|---|---|---|---|
| Small knobs | 7 | 8.75 -> 11.25 | 250/6 deg | 20 x 7 = **140** |
| Large knobs | 11 | 18 -> 21.5 | 25 deg | 3 x 11 = **33** |

1. Sketch on `plane(c, 45.6)`, `isComputeDeferred = True`.
2. For each knob centre and each angle, draw a **4-point closed polyline**. For
   angle `a` from +Y: radial unit = `(-sin a, cos a)`, tangential unit =
   `(cos a, sin a)`. The four corners are
   `centre + radial*r +/- tangential*0.4` for `r` = inner and outer radius.
   **Emit them walking the perimeter — inner-minus, outer-minus, outer-plus,
   inner-plus.** Any other order crosses the quad into a bowtie.
3. `isComputeDeferred = False`. Assert **173 profiles**. **346 means bowtie** —
   every quad closed as two triangles. Fix the corner order and redraw.
4. One extrude **+0.45** -> 173 bodies (they never touch, R4).
5. `sk.isVisible = False`. **If you redrew after a bad profile count, delete the
   failed sketch** — `sk.deleteMe()`. An abandoned sketch left visible puts 692
   white sketch points on the panel, which read as beads in every viewport and
   screenshot while the bodies underneath are perfect.

> 173 bodies · all `SLAB_Knob_Black` — not two-tone, not brown, not white

---

### Class 9 — `SLAB_Knob_Pointers` · 23 bodies

Boxes **1.1 (X) x 5.6 (Y) x 0.92 (Z)**, pointing +Y. **Two extrudes**, two Z bands.

| | Centre | Z band | Host top | Proud |
|---|---|---|---|---|
| Small (20) | (knob X, knob Y **+3.1**) | 60.23 -> 61.15 | 61.10 | 0.05 |
| Large (3) | (knob X, **-15.65**) | 58.73 -> 59.65 | 59.60 | 0.05 |

1. Sketch on `plane(c, 60.23)`, 20 rectangles 1.1 x 5.6 at the small-knob
   centres offset **+3.1 in Y**. Extrude **+0.92**.
2. Sketch on `plane(c, 58.73)`, 3 rectangles at X -45 / 0 / +45, **Y -15.65**.
   Extrude **+0.92**.

Never build an inlay coplanar with its host — it renders on some and not others.
Identify them by position, not name: the large-knob inlays are the **only
pointers below Y = 0**.

---

### Class 10 — `SLAB_Power_Switch` · 2 bodies

| | Dia | Centre | Z band |
|---|---|---|---|
| Toggle | 11.0 | (**-94.0**, **+130.0**) | 44.2 -> 59.0 |
| Power LED | 5.2 | (91.0, 139.5) | 46.0 -> 46.6 |

Two sketches, two extrudes.

> toggle bbox `[-99.5, 124.5, 44.2, -88.5, 135.5, 59.0]`

The toggle's rounded X extreme reaches **-99.520** (the bbox above rounds to
-99.5), and that is what makes the overall bbox 197.040 wide. Centred on
Y = 0 is the DEC-C5 defect.

---

### Class 11 — `SLAB_LED_Indicators` · 1 merged body · Z 45.6 -> 46.1

1. Sketch on `plane(c, 45.6)`:
   - one horizontal rule **132 x 0.9** at **Y +4**
   - two verticals **0.9 x 47** at **X +/-22.5**, running **downward** from
     Y +4 to **Y -43** (centre Y -19.5)
2. Extrude **+0.5**. The three rules touch, so the profiles **merge into one
   body** (R4). Expect ~5 profiles, 1 body.

> bbox `[-66.0, -43.0, 45.6, 66.0, 4.45, 46.1]`

Verticals run downward into the gaps between the large knobs. Upward to Y +51 is
the wrong version (DEC-C7).

---

### Class 12 — `SLAB_Panel_Graphics` · 50 bodies · Z 46.0 -> 46.15

**Five separate sketches and extrudes** — the profile filter differs between
them (R8). All raised **0.15**, on the lower deck (Y < -46).

| Sub-class | Bodies | Geometry | Filter | Checksum |
|---|---|---|---|---|
| Table | **1** | 3 rules **193 x 1.5** at Y -67.1 / -93.6 / -116.2; divider **1.0 x 49.1** at (-23.8, -91.65); seam **1.0 x 113** at (+68.5, -103.5) | min bbox dim <= 2 | 21 profiles -> **19 kept, 2 cells rejected**; top face **1023 mm2** |
| Grid blocks | **2** | X -8.3->5.2 and 16.8->30.3, Y -141->-127.6. 4 h-bars **13.5 x 0.8** at Y -140.6...-128.0 step 4.2; 4 v-bars **0.8 x 13.4** at x0+0.4...x0+13.1. **Inset so outer bar edges land on the stated outline** | same | **75.8 mm2 each** |
| Scale ticks | **30** | X -56.6 -> -14.1 (spacing 42.5/29), baseline Y -146.7, width 0.6, length **3.6 every fifth else 2.4** | none | **2.16 mm2** (6 long) and **1.44 mm2** (24 short) |
| Legends | **3** | "R" at (-69.5, -146.7), "IV" at (60.2, -146.7); **9.5 high, stroke 1.6** | **centroid** — drop only the R's counter | **R 42.1 · I 15.2 · V 27.9 mm2** |

**Legend tolerance is ±1.5 mm²** — R 40.6–43.6, I 13.7–16.7, V 26.4–29.4. That
is the whole acceptance test, and it is the only one. **Outside it is a miss.**

You work out the letterforms yourself; three closed strokes per letter, `bar()`
for the diagonals, the counter of the R excluded by centroid. How you get there
is yours. What is not yours is the verdict:

- **Do not call a miss "cosmetic only".** Area is the checksum for this class
  precisely because body count cannot see a malformed letter - a collapsed V and
  a correct V both report 1 body.
- **Do not invent a tolerance.** If a figure is outside the band above, it failed.
  28.7 against 27.9 is inside; 46.2 against 42.1 is not, and +10 % is not rounding.
- **Two rebuilds, then stop.** One run built R three times - 26.0, then a 2-body
  split, then 46.2 - and shipped the worst of the three. Diverging attempts mean
  the approach is wrong, not that the next one will land. Record the measured
  area as an open item and move on; a wrong R does not block CMF or the renders.

| Waveform | **14** | 14 bars width 0.8, X 34.0 -> 62.0 (spacing 28/13), centred Y -134.3, heights varying within the -141...-127.6 band | none | <= 10.7 mm2 each |

**The min-dimension filter applied to the legends deletes the R's leg and both V
strokes** — the model then builds a **"P"** and a collapsed V *while still
reporting 3 bodies*. **Face area is the discriminator, not body count.**

Build "R" as stem + top bar + waist + bowl side + a slanted leg (a 4-point
polyline); "I" as one bar; "V" as two slanted strokes meeting at an apex, which
merge into one body.

---

## 4 · Whole-model checks

**289 bodies, 12 components.** Face counts are build-path dependent and are
**not** checksums — the same geometry measured 63 faces one way and 78 another.
Mass (~3915.8 g) is a coarse smell test at default densities, never quoted as
product mass.

### Layout — zero violations, these exact values

Evaluate knobs at their **widest** section (dia 13.5 / dia 32).

| Check | Correct model |
|---|---|
| Pairwise knob gap >= 4.0 | **13.000 mm** (two large knobs) |
| Knob vs pad clearance | **7.700 mm** |
| Panel inside the recess | **1.0 mm** all four sides |
| Pad inset from housing outline | **0.200 mm** |
| Pad-to-panel gap | **0.700 mm** |
| 5 indicator-under-knob · 6 boss-to-aperture | **NOT IMPLEMENTED** — say so |

`scripts/setup/verify_layout.py` runs 1-4 in pure arithmetic, no Fusion, ~30 ms.
Run it before building.

---

## 5 · CMF — assign after all 289 bodies exist

**Steps**

1. Copy **`Plastic - Glossy (Black)`** from the material library — it exposes all
   seven Prism ids (`surface_albedo`, `opaque_albedo`, `surface_roughness`,
   `opaque_f0`, `opaque_emission`, `opaque_luminance`,
   `opaque_luminance_modifier`). Do not go looking for an alternative.
2. `des.appearances.addByCopy(src, name)` for all ten.
3. Set every property **while unapplied** — a write on an applied appearance
   forks a duplicate. Set `surface_albedo` **and** `opaque_albedo` together; the
   renderer reads the first and writing only the second leaves a stale colour.
4. Assign to bodies last. Clear face overrides explicitly —
   `b.appearance = x` does not.
5. Resolve appearances by **iterating** `des.appearances`, never `itemByName`.
6. **Never assign a library appearance to a body.** Every one of the 289 bodies
   carries a `SLAB_*` appearance built in step 2. Assigning the nearest-sounding
   stock material instead — `Stainless Steel - Brushed` for the knobs,
   `Paint - Enamel Glossy (Blue)` for the graphics — leaves every body coloured
   and every colour wrong, and the LEDs cannot glow because `opaque_emission` is
   never set. **The check is one line:
   `len([a for a in des.appearances if a.name.startswith('SLAB_')]) == 10`.**
   Zero means this section was skipped.

| Appearance | Albedo | Rough | f0 | Bodies |
|---|---|---|---|---|
| `SLAB_Gray_Flat` | 196,196,196 | 0.50 | 0.040 | 1 upper housing |
| `SLAB_Black_Semi` | 48,48,50 | 0.38 | 0.055 | 5 base + feet |
| `SLAB_Panel_Dark` | 78,78,82 | 0.60 | 0.042 | 1 panel |
| `SLAB_Knob_Black` | 42,42,44 | 0.30 | 0.058 | 196 = 20 knobs + 3 lg pointers + 173 ticks |
| `SLAB_Knob_Orange` | 252,108,64 | 0.34 | 0.050 | 4 = 3 lg knobs + dividers |
| `SLAB_LED_Emissive` | 255,122,48 | 0.26 | 0.050 | 11 = 10 pads + power LED |
| `SLAB_Print_Ink` | 58,58,62 | 0.70 | 0.035 | 50 graphics |
| `SLAB_Pointer_White` | 212,212,212 | 0.50 | 0.045 | 20 sm pointers |
| `SLAB_Toggle_Gray` | 200,200,200 | 0.35 | 0.050 | 1 toggle |
| `SLAB_Tick_Print` | 92,46,22 | 0.62 | 0.040 | **0 — defined, deliberately unused** |

`SLAB_LED_Emissive` also: `opaque_emission = True`, `opaque_luminance = **150.0**`,
`opaque_luminance_modifier = (255,140,70)` (DEC-C6).

Two components split by position, not by name:
`SLAB_Knob_Pointers` — the **only pointers below Y = 0** are the three large-knob
inlays (-> `SLAB_Knob_Black`); the other 20 are `SLAB_Pointer_White`.
`SLAB_Power_Switch` — toggle -> `SLAB_Toggle_Gray`, LED -> `SLAB_LED_Emissive`.

> End state: **11 appearances** (ten `SLAB_*` + the library source), zero
> duplicates, zero bodies without an appearance, zero stray face overrides

This pass touches every face of 289 bodies and **can exceed the request timeout
while completing normally** — re-query the tally, do not retry.

---

## 6 · Decisions closed — do not re-raise

| | Ruling |
|---|---|
| **DEC-C1** | Long axis **Y** (340), short **X** (195), +Y away from operator |
| **DEC-C2** | **20 pots (4 x 5)** governs; 16 is superseded |
| **DEC-C3** | **No bezel.** The 17.180 mm shortfall is met by a transport cover. Report the arithmetic, do not flag it as blocking |
| **DEC-C4** | **No connector aperture crosses the Z 23.0 parting line** |
| **DEC-C5** | Power toggle **Y = +130.0** |
| **DEC-C6** | The 10 pads are **lit buttons**, not printed ink |
| **DEC-C7** | Divider verticals run **downward**, Y +4 -> -43 |

**DEC-C4 tell:** in the two housing components, cylindrical faces with axis
(0,-1,0) touching Y ~ +/-170 must be **zero**. Mass will not catch it — removing
the offending cuts moved the whole model by 38.973 g and the body count not at all.

---

## 7 · Still open

**TBD-14 — zero named user parameters.** Hard-modelled throughout. Also: no
shaft holes in the panel (dia unstated; volume implies ~ dia 8.3, TBD-15); rear
I/O plate and bay not built (TBD-13); the waveform graphic not itemised in the
PRD (TBD-17); orange panel speckle and in-panel legend text not modelled; draft
analysis not run; boss positions predate the axis correction (TBD-16).
