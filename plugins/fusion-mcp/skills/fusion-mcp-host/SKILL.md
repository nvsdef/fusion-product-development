---
name: fusion-mcp-host
description: "Operating the host bridge to a live Autodesk Fusion session — the transport contract, not the CAD. Liveness with get_scene_info (never ping), the 300 s timeout on both sides, the never-retry-a-timed-out-call rule, batch caps that keep a call under the ceiling, saving before large operations, and the audit-for-duplicates recovery after a timeout. Load alongside fusion-mcp-core before any fusion360 tool call; fusion-mcp-core owns how Fusion's API behaves, this skill owns how the pipe behaves."
user_invocable: false
---

# fusion-mcp-host

`fusion-mcp-core` describes what Fusion's API does — units, sketch planes,
tools that report success while doing nothing. This skill describes the
**pipe** you reach it through, and the failure modes that belong to the pipe
rather than to the model. When a call hangs, the difference decides whether
you fix your script or fix the session.

The path, and every hop that can fail:

```
agent (sandbox)
   │ stdio                     ← launched by the client; no port, no network
   ▼
fusion360-mcp-server (host)
   │ TCP 127.0.0.1:9876        ← the add-in socket
   ▼
Fusion360MCP add-in
   │ custom event -> MAIN THREAD   ← the hop that blocks
   ▼
adsk.core / adsk.fusion
```

The main-thread hop is not optional: calling `adsk.*` off-thread crashes
Fusion. Everything below follows from the fact that Fusion has exactly one
main thread and your call has to get onto it.

## Liveness: `get_scene_info`, never `ping`

**`ping` is a misleading health check.** It is answered by the socket
handler and never enters the API, so it returns cheerfully while the main
thread is blocked and every real call times out.

Use `get_scene_info`. It has to be marshalled onto the main thread, so a
reply proves the one thing you actually care about.

| Symptom | What it means | Fix |
|---|---|---|
| socket refused on 9876 | add-in never Run, or Fusion not open | UTILITIES > Scripts and Add-Ins > Add-Ins > `Fusion360MCP` > Run |
| `ping` OK, `get_scene_info` times out | main thread blocked — almost always the **modal Scripts and Add-Ins dialog left open** | close the dialog |
| both time out | the client's server process is not running, or Fusion is mid-crash | check the add-in log, restart the client from the system tray |

Host-side diagnostics, in escalating order:

```
Test-NetConnection 127.0.0.1 -Port 9876        # socket only — cannot see the main thread
python3 plugins/fusion-mcp/host/fusion_mcp.py --probe   # get_scene_info round-trip
$HOME/fusion360mcp.log                          # the add-in's own log; read it first
```

Nothing in this list can be run from the sandbox. If the bridge is dead,
report it to the orchestrator and stop — you cannot restart Fusion, and
retrying will not make a modal dialog go away.

## Preconditions

1. Fusion 2026 open with a **design document open and active**.
2. `Fusion360MCP` add-in **Run** (tick Run on Startup so this survives).
3. **The Scripts and Add-Ins dialog CLOSED.**
4. Both timeouts at 300 s (see below).
5. `$FUSION_OUTPUT_DIR` exists — `startLocalRender` fails *quietly* without
   it, and the symptom is a render that never finishes.

## The 300 s timeout — both sides, and they must agree

Two independent timeouts guard the same call. If they disagree, the shorter
one cuts the longer one off and you get a timeout with no diagnostic:

- add-in side — `addon/server/event_bridge.py`, `submit(..., timeout=)`
- client side — `src/fusion360_mcp/connection.py`, `_TIMEOUT`

`scripts/setup/patch_timeouts.py` sets both to 300 s. The stock 30 s is not
survivable: the raytraced passes alone run **≈ 98 s** (1000 px q90), **≈ 130 s**
(the 1100 px q92 hero) and **~143 s** (1200 px q95). `create_drawing` measured
**47.2 s** back when it was still being probed — it **fails on this build** and
must not be called at all.

Changing `connection.py` requires a **full client restart from the system
tray** — it runs in the MCP server process, not in the add-in. Restarting
the add-in does nothing for it. Conversely, after editing add-in source,
**Stop then Run** the add-in and close the dialog; Python caches the module,
so copying files alone changes nothing, and submodule edits may need a full
Fusion restart.

## Never retry a call that timed out

This is the most expensive rule in the repo, and it was learned the hard
way. A single cut with **219 profiles** exceeded the client's ceiling. The
client **retried**. The add-in had never stopped working on the first
attempt, so it ran the whole thing a second and a third time: three
identical sketches, three coincident cuts, Fusion at **18 GB private
bytes**, unresponsive for ~20 minutes, force-kill required.

A timeout means *"the client stopped waiting"*. It does **not** mean the
work stopped. The add-in is still holding the main thread and will finish —
and your retry queues a second identical mutation behind it.

**After any timeout: do not retry. Diagnose.**

## Batch caps

Two independent ceilings, and they fail differently:

| Ceiling | Limit | Failure mode |
|---|---|---|
| Runtime (main thread held too long) | **~30–40 sketch profiles per call** | timeout, then the duplication cascade above |
| Script size (independent of runtime) | **~40–60 lines per `execute_code`** | bare `Tool execution failed`, no traceback, while `ping` and `get_scene_info` still work |

A ~150-line script hit the second ceiling with no useful error at all. Split
long work into short calls rather than discovering where the edge is.

Practical shape: one operation per call. A pattern, a boolean, a fillet
pass, an export — each on its own. `execute_code` is the workhorse, but a
big `execute_code` is the single most reliable way to wedge the session.

## Save before large operations

Ask the human to **save the design before any large operation** — a big
pattern, a multi-profile cut, a boolean over many bodies, an export. If the
call wedges Fusion and needs a force-kill, the save is the only thing
standing between you and rebuilding the whole model. Fusion cannot be saved
from a blocked main thread, so it has to happen beforehand.

## Recovery after a timeout

In order. Do not skip step 2 — it is what stops one timeout becoming a
corrupted timeline.

1. **Wait.** The add-in is still working. Give the operation the time it
   actually needs before touching anything.

2. **Probe with something trivial.** `execute_code` with `1 + 1`.
   - It succeeds → the connection is *fine*. Your payload was too big.
     Nothing is wrong with the bridge; make the call smaller.
   - It times out → the main thread is still held (or the dialog is open).
     Do not send more work. Escalate to the human.

3. **Audit before you build anything else.** The timed-out call probably
   *completed* — possibly more than once. Enumerate features and sketches
   and look for duplicates, which show up as auto-uniquified names
   (`SK_Name (1)`, `SK_Name (2)`) and coincident features:

   ```python
   for s in comp.sketches:
       print(s.name, s.profiles.count)
   for f in comp.features:
       print(f.name, "SUP" if f.timelineObject.isSuppressed else "ACTIVE")
   ```

   Read `fusion-mcp-core` for the full enumeration idiom — matching on
   `profile.item(0)` alone silently misses features, so match on name too.

4. **Suppress the duplicates, do not delete them.** `TimelineObject` has no
   `deleteMe`; `feature.timelineObject.isSuppressed = True` works and is
   reversible.

5. **Re-measure.** `get_physical_properties` and `get_bounding_box` against
   what you expected before the timeout. A return value is not evidence; a
   second, independent measurement is.

## Long-running work: submit and poll, never block

`start_render` returns a job id immediately and Autodesk queues renders to
run **one at a time** — a second submission can sit queued for minutes
before it even starts. Poll `get_render_status(job_id)` through
`queued | processing | finished | failed` — **with the `get_render_status`
tool, never with a `time.sleep` loop inside `execute_code`**, which returns
`Error: Request timed out` past ~100 s on a render that is fine.

**Never pass `include_image`, not even on the final poll.** It returned
**138,453 characters** of base64 for one 1136×640 frame: it overflows the
tool-result budget, spills to a temp file, and you still have not seen the
image. Poll for state only, then `Read` the PNG off disk.

Two consequences that bite:

- A blocking wait on a render hits the socket timeout even though the render
  is perfectly healthy. Poll instead.
- Renders live inside the Fusion process and **die with it**. A job id does
  not survive a Fusion restart. The host-side helper
  `plugins/_shared/host_job_manager.py` models exactly this: it tracks
  submitted ids, enforces a local timeout, and reports `lost` rather than
  hanging when Fusion has restarted underneath it. Note that it stops
  *watching* on timeout — nothing outside Fusion can cancel a running
  render.

`render_view` is the opposite tool: an unlit viewport capture, effectively
instant. Use it constantly while iterating and save `start_render` for
deliverables.

## What this skill does NOT do

- It does not own Fusion API behaviour — units, sketch-plane axis negation,
  tools that report success while doing nothing, feature auditing. That is
  `fusion-mcp-core`, and it is required reading before any tool call.
- It does not own render recipes (resolutions, scene settings, appearances)
  or drawing recipes. Those are the fusion-photoreal-render and fusion-2d-drawings
  skills.
- It does not decide which tools are safe. `create_box_parametric` (10×
  undersized), `export_drawing_pdf` (freezes Fusion) and `create_drawing`
  (fails outright on this build) are recorded under "Do not use" in the
  agents' `TOOLS.md`.
- It cannot start, restart or unblock Fusion. Every recovery step that
  touches the GUI belongs to the human at the host.
