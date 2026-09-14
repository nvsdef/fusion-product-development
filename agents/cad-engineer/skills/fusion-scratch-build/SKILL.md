---
name: "fusion-scratch-build"
description: "How to build a model from an EMPTY Fusion 360 document - the profile rules that cannot fail to close, absolute-Z placement, one feature class per call, and a HALT protocol that stops the run on a missed checksum instead of carrying the defect forward. Use whenever the design is empty or a whole component must be built from nothing."
---

# Building a Fusion model from an empty document

The cold-build procedure. **Read §1 and §2 before writing any geometry** — they
are the two places every observed failure has come from.

**Confirm you are in a cold build**: `list_components` returning a single unsaved
root, or `NO_ACTIVE_DESIGN`. There is nothing to audit yet.

---

> **Naming:** §1 of `slab-product-spec` binds `comp` to a *function*
> (`comp('SLAB_Housing_Upper')` gets or makes a component). The component
> object it returns is bound to **`c`** in every snippet here. `comp.sketches`
> raises `AttributeError: 'function' object has no attribute 'sketches'`.

## 1 · The HALT protocol — this is not advice

After **every** feature class, in this order, in the same call that built it:

1. Measure the class: body count, the body's **bounding box in mm**, and its
   **volume**.
2. Compare against the stage's stated values.
3. **If any one of them misses, do not build the next class.** Reset the
   component with `reset_component()` and rebuild that class - **at most twice.**
   If it misses a third time, HALT: report what you built, what you measured,
   what was expected, and the difference, and stop the run.

   Rebuilding without resetting is what produced four identical housing bodies
   in one run. Reset first, every time.

A checksum you measure and then ignore is worse than no checksum, because it
puts a wrong number in the transcript and the run continues on a broken base.
A base moulding that lands at Z −5.0…20.0 instead of 3.5…23.0 does not get
better when you put knobs on it.

Return the comparison as data, so it cannot be glossed:

```python
bb = b.boundingBox
got = {'bbox_mm': [round(v*10,3) for v in (bb.minPoint.x, bb.minPoint.y, bb.minPoint.z,
                                           bb.maxPoint.x, bb.maxPoint.y, bb.maxPoint.z)],
       'volume_cm3': round(b.volume, 3),
       'bodies': c.bRepBodies.count,
       'faces': b.faces.count}
exp = {'bbox_mm': [-97.5, -170.0, 3.5, 97.5, 170.0, 23.0],
       'volume_cm3': 209.947, 'bodies': 5}     # Housing_Base: shell + 4 feet
{'got': got, 'expected': exp,
 'PASS': got['bbox_mm'] == exp['bbox_mm'] and abs(got['volume_cm3']-exp['volume_cm3']) < 0.01}
```

**`PASS: False` blocks the next class.** Reset, rebuild, re-measure - twice at
most. Still false on the third measurement ends the run.

**The bounding box is the more important half.** Volume alone cannot see a body
built in the right shape at the wrong height — and that is the most common
placement defect. Check the bbox first.

---

## 2 · Profiles that cannot fail to close

The single most common build failure is a sketch that produces **zero profiles**,
because a hand-assembled outline did not close. It presents as an extrude that
raises, or silently makes no body, and the usual reaction — retry in a new
component — leaves `MyPart (1)`, `MyPart (2)` behind and the run never recovers.

### Rule 1 — never hand-build a rounded rectangle from lines and arcs

Draw a **plain rectangle**, extrude it, then **fillet the vertical edges of the
solid**. One profile is guaranteed, and the result is geometrically identical to
a rounded-rect extrusion — same volume, same faces, same shell behaviour.

```python
sk = c.sketches.add(plane)
sk.name = 'SK_Housing_Outline'
sk.sketchCurves.sketchLines.addCenterPointRectangle(
    P3(cx, cy, 0), P3(cx + w/2.0, cy + h/2.0, 0))     # w, h in cm
assert sk.profiles.count == 1, 'rectangle did not close'

# extrude, then round the four vertical edges
edges = adsk.core.ObjectCollection.create()
for e in body.edges:
    g = e.geometry
    if g.objectType == adsk.core.Line3D.classType():
        d = g.startPoint.vectorTo(g.endPoint)
        if abs(d.x) < 1e-6 and abs(d.y) < 1e-6:        # vertical
            edges.add(e)
assert edges.count == 4, f'expected 4 vertical edges, got {edges.count}'
fi = c.features.filletFeatures.createInput()
fi.isRollingBallCorner = True
fi.addConstantRadiusEdgeSet(edges, V(R_CORNER), True)
c.features.filletFeatures.add(fi)
```

Face count goes **6 → 10**. That is the check the fillet took.

### Rule 2 — assert `sk.profiles.count` before every extrude

Every sketch, without exception:

```python
assert sk.profiles.count == EXPECTED, \
    f'{sk.name}: {sk.profiles.count} profiles, expected {EXPECTED}'
```

Zero profiles means the outline did not close. **Fix the sketch; do not retry
into a new component.**

### Rule 3 — circles and centre-point rectangles are safe; polylines are not

`addByCenterRadius` and `addCenterPointRectangle` always close. Four-point
polylines only close if the last point exactly equals the first — use them only
for genuinely non-rectangular shapes (slanted strokes, radial bars), and assert
the profile count afterwards.

---

## 3 · Place in absolute Z, and prove it with the bbox

State every class as **"Z from A to B"**, never as "extrude +H from wherever the
last plane was". Build the construction plane from the component's own XY plane
each time, so no error accumulates:

```python
def plane_at(comp, z_mm):
    pi = comp.constructionPlanes.createInput()
    pi.setByOffset(comp.xYConstructionPlane, V(z_mm / 10.0))   # mm -> cm
    return comp.constructionPlanes.add(pi)

sk  = c.sketches.add(plane_at(comp, 3.5))        # base plane, absolute
ext = extrude(c, allprof(sk), 23.0 - 3.5)   # component, profiles, height in MM
# then assert bbox Z reads exactly [3.5, 23.0]
```

**The API works in centimetres. Every dimension in every spec is millimetres.**
Divide by 10 at the boundary, once, in a named helper — not inline at each use.

---

## 4 · One component per name, ever

```python
def get_or_make(root, name):
    for o in root.occurrences:
        if o.component.name == name:
            return o.component          # reuse; never fork
    o = root.occurrences.addNewComponent(adsk.core.Matrix3D.create())
    o.component.name = name
    return o.component
```

A component called `SLAB_Panel_Control (1)` is the signature of a failed retry.
If you see one, the run has already gone wrong: delete the duplicate, go back to
the class that failed, and fix the sketch rather than building around it.

**To retry a class**: delete its **extrude feature** (which takes its bodies with
it), then its sketch **by name**, then rebuild in the same component.

```python
for f in list(c.features.extrudeFeatures):
    if any(b.name.startswith(PREFIX) for b in f.bodies):
        f.deleteMe()
for s in list(c.sketches):
    if s.name == SKETCH_NAME:
        s.deleteMe()
```

Never match a sketch on curve count — two sketches in one component will
eventually have the same count, and deleting the wrong one leaves a downstream
extrude on cached geometry that still reports healthy bodies.

---

## 5 · Batch by feature class — one class per call

This is the opposite of the per-change rule in `fusion-mcp-driving`, and both are
correct for their stage.

| | Editing | Cold build |
|---|---|---|
| Batch size | one operation per call | **one FEATURE CLASS per call** |
| Why | a timeout mid-edit leaves ambiguous state | 289 single-op round-trips is hours of latency |
| Verify | after every call | after every call — §1, and it halts |

"One feature class" means all 20 knobs in one sketch and one extrude; all 173
ticks in one sketch and one extrude. Each closed profile becomes its own body
under `NewBodyFeatureOperation`.

```python
sk.isComputeDeferred = True       # ~20x faster across many curves. ALWAYS for N > ~5
... add all curves ...
sk.isComputeDeferred = False      # recompute once
assert sk.profiles.count == N_EXPECTED
```

Name every body as you create it — new bodies come back as `Body1..N`.

### Filtering profiles when a sketch encloses regions

Crossing bars offer more profiles than there are bars: the bars split at their
intersections, and each enclosed cell is a profile too. Two filters, and **the
choice is per sketch, not global**:

- **Orthogonal bar grids** — keep profiles whose **minimum bbox dimension** is
  within the bar width. Works because every real element is a thin bar and every
  unwanted profile is a cell several mm across.
- **Slanted strokes — letterforms, chevrons, diagonals** — use a
  **centroid-in-region** test for the known enclosed area instead. A diagonal
  stroke's bbox is much wider than the stroke, so a min-dimension filter deletes
  it: an "R" built that way loses its leg and prints as a **"P"** while the body
  count still comes out right.

Report kept and rejected counts per sketch. A filter that rejects zero has not
proved anything.

---

## 6 · Build order

**housing → panel → controls → graphics → appearances.**

- **Cut pockets from a face that still exists.** After shelling a box and
  removing its bottom face, the top face remains, so recesses cut from the top
  downward with no ordering problem. A sketch on a *datum plane* over an
  already-shelled body sits in mid-air and Fusion returns "No target body found
  to cut" — an error that reads like a selection bug and is an ordering bug.
- **One cut class per call, each with its own sketch.** A recess, a set of
  notches and a set of strip cuts are three classes, not one sketch of thirteen
  profiles. Each has its own volume delta to check, and merging them means a
  wrong total with no way to localise it.
- **Select faces by geometry, never by index** — indices shift with topology:
  ```python
  for f in b.faces:
      g = f.geometry
      if g.objectType == adsk.core.Plane.classType() and abs(g.normal.z) > 0.99 \
         and abs(g.origin.z - Z_TARGET) < 1e-4:
          faces.add(f)
  ```
- **Appearances last.** Applying materials before the body count is final means
  re-applying them, and it is where face-level overrides get orphaned.

---

## 7 · Save and verify after every class

```python
app.activeDocument.save('<class> complete')
```

Also confirm the running body total against the budget, and at the end that the
whole timeline is clean:

```python
[(i, des.timeline.item(i).name)
 for i in range(des.timeline.count)
 if des.timeline.item(i).entity is not None
 and int(des.timeline.item(i).entity.healthState) != 0]        # expect []
```

`healthState 1` with "Profile reference is lost… using cached geometry" means a
feature outlived its sketch. Bodies still exist and the count still looks right,
so only this check finds it.

---

## 8 · Gate 0 → 1

- Every class's bbox **and** volume met, each verified in the call that built it
- Body count per class within the declared budget
- Every timeline entity `healthState` clean
- No component name ending in ` (1)`
- Document **saved** under its final name
- **One `render_view(view='top', fit=True)` capture, looked at.** It costs a
  second and catches what no count can: a filled region, a missing class, a
  letterform built wrong, a body at the wrong Z.

---

## Budget

**~20 min** for a ~300-body deck across ~12 classes, plus ~3 min for appearances.
Overrunning by 50 % means the class batching is not being followed — stop and
check rather than pushing on.

