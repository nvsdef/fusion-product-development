# Setup — manual, ~30 minutes

> **`setup.sh` does not work in this copy.** It calls four helper scripts
> (`cad_agent.py`, `plugins.py`, `patch_timeouts.py`, `sync_shared_skills.py`)
> that are not in the repository, and fails at line 74 before doing anything.
> Follow this file instead. Every step below was performed by hand on a working
> installation; the steps are the ones that actually produced a complete run.

You need: **Windows**, **Autodesk Fusion 360**, **Python 3.11+**, **git**, and
**Hermes Agent**. The agent must run on the *same machine* as Fusion.

---

## 1 · Install the MCP server

```bash
git clone https://github.com/faust-machines/fusion360-mcp-server.git
cd fusion360-mcp-server
python -m venv .venv
.venv\Scripts\pip install -e .        # or: uv sync
```

Note the path to `.venv\Scripts\python.exe` — step 4 needs it.

---

## 2 · Raise both timeouts to 300 s

**Do not skip this.** The stock 30 s is shorter than several operations that
succeed: `create_drawing` measures ~47 s, and a quality-95 render runs 135–435 s.
At 30 s they time out *while completing*, which is the single most confusing
failure in this pipeline.

Two places, both in the checkout from step 1:

- `src/fusion360_mcp/connection.py` — the client-side request timeout
- `addon/server/event_bridge.py` — the add-in side

Search each for the timeout value and set it to `300`. They must agree.

---

## 3 · Install and enable the Fusion add-in

Copy the add-in into Fusion's AddIns directory. The source is either
`addon/Fusion360MCP/` or `addon/` depending on the fork's layout:

```
%APPDATA%\Autodesk\Autodesk Fusion 360\API\AddIns\Fusion360MCP\
```

The target directory name must be exactly `Fusion360MCP`.

Then, in Fusion — **this part cannot be scripted**:

1. **UTILITIES → Scripts and Add-Ins → Add-Ins tab**
2. Select **Fusion360MCP → Run**, and tick **Run on Startup**
3. **Close the Scripts and Add-Ins dialog.** It is modal and holds Fusion's main
   thread. While it is open every API call times out — and `ping` still answers,
   because `ping` never enters the API. That is why `ping` is not the health
   check.

Verify the socket:

```powershell
Test-NetConnection 127.0.0.1 -Port 9876     # expect TcpTestSucceeded : True
```

---

## 4 · Register the MCP with Hermes

In `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  fusion360:
    transport: stdio
    command: C:/path/to/fusion360-mcp-server/.venv/Scripts/python.exe
    args: ["-m", "fusion360_mcp", "--mode", "socket"]
    env:
      FUSION_MCP_PORT: "9876"
      FUSION_MCP_TIMEOUT: "300"
```

Restart the client **from the system tray**, not just its window — the server
runs in that process and will not pick up the change otherwise.

---

## 5 · Point Hermes at these skills

Same file:

```yaml
skills:
  external_dirs:
    - C:/path/to/Fusion Product Development - Share/agents/cad-engineer/skills
```

Then copy the operating rules into place — **`~/.hermes/SOUL.md` is a different
file** from the one in this repo, and it is the one Hermes reads every turn:

```bash
cp "agents/cad-engineer/SOUL.md" ~/.hermes/SOUL.md
```

---

## 6 · Check for shadow skills — do not skip this

Hermes lists every installed skill to the agent at session start. **An installed
skill whose description also matches "build SLAB" or "Fusion" will outrank the
ones in this folder**, and you will get a run that reads the brief correctly and
then ignores the procedure.

```bash
hermes skills list        # anything matching CAD, Fusion, render, or SLAB?
```

Move overlapping skills out of `~/.hermes/skills/` (rename the directory rather
than deleting it). During development three competing skills were installed — one
instructed the agent **not to read the `agents/` directory at all**. Editing files
here changed nothing until they were moved.

---

## 7 · Run it

Fusion open, on an **empty Design document**. Then start a **new** Hermes session
— installed-skill changes only take effect in a fresh session — and paste:

> Build SLAB — a portable 6-channel production mixer and USB-C audio interface —
> in Fusion 360 from the attached product design brief and concept mockups. Take
> it all the way: parametric geometry, materials, calibrated renders, and a
> dimensioned general arrangement drawing.

Attach `docs/SLAB_PRD_RevC.pdf` and both images from
`examples/01_slab_mixer/reference/`.

Expect **~45 minutes** cold.

---

## 8 · Is it working?

Four lines, in this order. Each one confirms a stage that has failed in the past:

```
STAGE 1 · SLAB_TOP_vN · data_file=True · PASS
Class 1 · SLAB_Housing_Upper · 1 body · vol=219.091 cm3 · PASS
STAGE 4 · 10 SLAB_* appearances · 289 bodies assigned · PASS
STAGE 6 · workspace FusionRenderEnvironment · brightness 1700.0 · cameraExposure 9.5
```

- **219.091** on class 1 means units and utilities are right; the rest follows.
- **Ten `SLAB_*` names** matching the spec table. Invented names such as
  `SLAB_Housing_Matte_Grey` mean a shadow skill — go back to step 6.
- **brightness 1700.0.** Single digits mean the scene was never configured, and
  every render will come out black against a correctly-lit background.

`examples/01_slab_mixer/expected.md` is the full acceptance baseline. Read it
**after** a run.

---

## If something fails

`HANDOFF.md` lists the known open items and the two API calls that kill the MCP
server. The add-in's own log is at `$HOME/fusion360mcp.log` — read it first.
