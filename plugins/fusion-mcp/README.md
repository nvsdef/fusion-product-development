# plugins/fusion-mcp

Host MCP that bridges an agent to a running Autodesk Fusion session.

## Architecture

```
agent (sandbox)
   │ stdio
   ▼
fusion360-mcp-server  (host, launched by the client)
   │ TCP 127.0.0.1:9876
   ▼
Fusion360MCP add-in   (in-process Fusion Python)
   │ custom event -> MAIN THREAD
   ▼
adsk.core / adsk.fusion
```

The main-thread hop is not optional. Calling `adsk.*` off-thread crashes
Fusion; every working Fusion MCP implementation arrives at the same custom
event queue independently.

## Why stdio and not the Autodesk endpoint

Autodesk ships its own Fusion MCP at `http://127.0.0.1:27182/mcp`. It works
— it returns a valid handshake — but reaching it requires the client's
**custom connector** path, which enterprise policy commonly disables. That
block is on the client side, not the network: the server is localhost-only
and unauthenticated, so there is nothing for a firewall to stop.

This example therefore uses the **stdio** bridge, which is configured from a
local file and is not governed by connector policy. `policy.yaml`
deliberately excludes 27182.

## Client registration (Windows)

**This block is the single source of truth for how the server is invoked.**
`plugins/fusion-mcp/plugin.yaml` (`mcp_server.command`/`args`) and
`plugins/fusion-mcp/host/run.sh` both reproduce it; change it here first and
propagate.

```json
{
  "mcpServers": {
    "fusion360": {
      "command": "C:\\path\\to\\fusion-mcp-server\\.venv\\Scripts\\python.exe",
      "args": ["-m", "fusion360_mcp", "--mode", "socket"]
    }
  }
}
```

Calling the venv interpreter directly avoids putting `uv` in the runtime
path. `scripts/setup/env-loader.sh` derives that interpreter path into
`FUSION_MCP_PYTHON` from `FUSION_MCP_REPO`, probing `.venv/Scripts/python.exe`
(Windows) and `.venv/bin/python` (POSIX), so the two consumers above never
hardcode a platform.

## Tool surface

~95 tools. Notable, and documented in `fusion-mcp-core`:

- `execute_code` is the workhorse — full API in one round-trip
- `get_scene_info` is the health check; **`ping` is not**
- `create_box_parametric` is **broken** (10× undersized) — do not use
- `export_drawing_pdf` **freezes Fusion** — do not use
- `create_drawing` **fails on this build** (`3 : Failed to create drawing
  document.`) — do not use, and do not re-probe it
- `get_render_status(include_image=True)` overflows the tool-result budget
  (138,453 characters for one 1136×640 frame) — **never pass it**; `Read` the
  PNG off disk instead
- `start_render` ignores `width`; the frame comes from
  `sceneSettings.aspectRatio` plus `height`
- `delete_all` needs the patched build; upstream deletes nothing

## Known patches applied to upstream

Forked from `faust-machines/fusion360-mcp-server` (MIT).

| Fix | Why |
|---|---|
| `delete_all` verifies and reports | upstream returned `deleted: True` having removed nothing; `TimelineObject` has no `deleteMe` |
| Both timeouts 30 → 300 s | the raytraced passes need it — 1000 px q90 ≈ 98 s, the 1100 px q92 hero ≈ 130 s, 1200 px q95 ~143 s. (`create_drawing` measured 47.2 s when it was still being probed; it fails on this build now and must not be called) |
| Added `start_render` / `get_render_status` | no public Fusion MCP had photoreal rendering |
| Added `create_drawing` / `fetch_api_doc` | no public Fusion MCP had drawing automation. `fetch_api_doc` is the one that survived — **`create_drawing` fails on this build and is never to be called**; the deliverable is the composed GA sheet |
| Error hints for `DESIGN_NOT_SAVED`, `RENDER_UNAVAILABLE` | actionable messages instead of tracebacks |
