# Fusion Product Development

An autonomous product-design workspace for **Autodesk Fusion 360**: one agent
takes a written brief to a verified parametric model, a calibrated photoreal
render, and a dimensioned A3 general arrangement drawing — in one session,
against a live Fusion GUI.

Built on the NeMoClaw / Hermes autonomous-AI-engineer blueprint. Same shape:
`cad-agent.yaml` + `policy.yaml` + `plugins/` + `agents/` + `setup.sh`.

**Reference workload:** SLAB, a portable 6-channel production mixer.
289 bodies, 12 components. Cold build to delivered drawing, **~45 minutes**.

---

## The one thing to know first

**Fusion is a GUI application on the host, and the agent drives it live.**

There is no headless mode, no containerised solver, no remote path. The agent
must run on the same machine as Fusion. A remote terminal backend — Daytona,
Modal, SSH, Vercel Sandbox — cannot reach it, and this is the most common way a
first run fails.

---

## Quick start

**Follow [`SETUP.md`](SETUP.md).** About 30 minutes: clone the MCP server, raise
both timeouts to 300 s, install and enable the Fusion add-in, register the server
and these skills with Hermes, and check for shadow skills.

> `setup.sh` is **incomplete in this distribution** and exits immediately — it
> calls four helper scripts that are not included. `SETUP.md` is the working
> path.

Then, with Fusion open on a **Design** document:

```bash
hermes                                    # or your harness of choice
```

and paste `examples/01_slab_mixer/prompt.md`.

### If the agent ignores these skills, look for a shadow skill first

Hermes resolves skills from `~/.hermes/skills/` **and** from
`skills.external_dirs` in `~/.hermes/config.yaml`. Installed skills are listed to
the agent at session start, so **an installed skill whose description also matches
"build SLAB" will win over the ones in this folder** - and you will see a run that
reads the brief correctly and then ignores the procedure entirely.

That happened during development and cost a day. Three installed skills were
competing: one told the agent *not to read the `agents/` directory at all*, and
another contradicted this folder on scene brightness and on which albedo property
the renderer reads. Editing files here changed nothing until they were removed.

**Before your first run:**

```bash
hermes skills list            # anything matching CAD, Fusion, render, or SLAB?
```

Move anything that overlaps out of `~/.hermes/skills/` rather than deleting it.
Then point Hermes at this folder:

```yaml
# ~/.hermes/config.yaml
skills:
  external_dirs:
    - /path/to/Fusion Product Development/agents/cad-engineer/skills
```

`~/.hermes/SOUL.md` is also read every turn and is **not** the same file as
`agents/cad-engineer/SOUL.md`. Copy this one over it, or the operating rules
never reach the model.

**Symptom to watch for:** the run invents its own appearance names
(`SLAB_Housing_Matte_Grey` instead of `SLAB_Gray_Flat`) or tunes `brightness` in
single digits instead of setting 1700. Both mean it is following something else.

### Already using Claude Code?

```bash
hermes import-agent claude-code
```

migrates the `mcpServers` block, the skills and the instructions in one command.
The `mcpServers` shape in `~/.claude.json` maps directly to `mcp_servers` in
`~/.hermes/config.yaml`.

---

## Layout

```
AGENTS.md                  the tool surface — start here
BUILD_STATE.json           resume checkpoint (template; status=pending = cold build)
cad-agent.yaml             one harness, one agent, four gates
policy.yaml                sandbox egress overlay
setup.sh                   host install + add-in + timeout patch

agents/cad-engineer/
  SOUL.md                  who the agent is and how it judges its own work
  TOOLS.md                 exact signatures and return shapes for the eight tools
  skills/                  the six procedure skills — THE SPEC
    slab-run/                 the whole procedure, in order          <- entry point
    slab-product-spec/        every dimension, with its regression tell
    fusion-scratch-build/     cold-build batching, budgets, checksums
    fusion-mcp-driving/       call signatures, cameras, appearances
    fusion-photoreal-render/  exposure, cameras, the two-part accept test
    fusion-2d-drawings/       line art, the composed sheet, the terminal call

plugins/fusion-mcp/        stdio bridge to the Fusion360MCP add-in (127.0.0.1:9876)
harnesses/hermes/          harness wiring
scripts/                   host-side helpers (composite, views, sheet, measurement)
docs/                      the human record — PRD Rev C, decisions, verification report
drawings/                  SLAB_GA_RevC.pdf — the released sheet
renders/                   slab_hero.png, slab_top.png — the accepted baseline
examples/01_slab_mixer/    prompt, expected values, reference imagery
```

### What governs what

| Question | Authority |
|---|---|
| *How do I run this?* | `/skill slab-run` |
| *What are the dimensions?* | `/skill slab-product-spec` |
| *What does this tool actually do?* | `agents/cad-engineer/TOOLS.md` |
| *Is the build correct?* | the checksums in the skills; `examples/01_slab_mixer/expected.md` |
| *Why is it like this?* | `docs/SLAB_PRD_RevC.pdf`, `docs/SLAB_DECISIONS.md` |

**The skills are the spec.** `docs/` is the human record — it says the same
thing more slowly, and an agent that builds from the PDF instead of the skill is
doing it the hard way.

---

## Harness settings that matter

Defaults in most harness adapters are wrong for this workload. These four are
the difference between a run and a stall:

| Setting | Default | Needs | Why |
|---|---|---|---|
| `max_tokens` | often **512** | **≥ 8192** | One feature class is 150+ lines of Python in a single tool argument. 512 cannot emit one. |
| `max_turns` / `max_iterations` | 20–50 | **≥ 150** | ~50 dependent tool calls over ~45 min. |
| tool timeout | 30–60 s | **≥ 300 s** | `create_drawing` measured 47.2 s; the 289-body appearance pass is longer. |
| reasoning effort | sometimes `none` | **medium** | The closed-form volume checksums need it. |

And register **eight** MCP tools, not ~95 — the include-list is in
`cad-agent.yaml`. Tool-surface flooding is the quiet killer of selection
accuracy.

---

## Verifying a run

Four gates, all numeric, none a judgement call:

| Gate | Pass |
|---|---|
| geometry-signoff | 289 bodies · 12 components · timeline clean · every stage volume met |
| cmf-signoff | 11 appearances · 0 mismatches · 0 unnamed bodies · 0 stray face overrides |
| render-signoff | LED pad G:R 0.55 ± 0.03 · exactly 10 pad blobs · per-channel spread ≤ 7 |
| drawing-release | crop-aspect error ≤ 0.11 % per view · sheet rasterised and inspected |

If the model has no vision, every visual gate has a numeric substitute —
`docs/SLAB_PRD_RevC.pdf` §12.4. The one that matters most: a legend built with
the wrong profile filter renders **"P"** instead of **"R"** *and still reports
the correct body count of 3*. The discriminator is face area.

---

## Known sharp edges

- **`export_drawing_pdf` hangs the MCP server.** Never call it. It is excluded
  from the registered tool list for this reason.
- **`create_drawing` is terminal.** After it, `execute_code` no longer runs and
  only a human clicking the Design tab can recover the session. It is the last
  Fusion action of any run, by design.
- **A timeout is not a failure.** `create_drawing` and the appearance pass both
  return `Request timed out` while succeeding. Re-query state; never blind-retry.
- **`start_render` ignores your camera** unless you pass `view='current'`.
- **Exposure is document-specific**, and `brightness` is not the only control —
  `sceneSettings.cameraExposure` is a second, inverse one that
  `set_scene_environment` never writes. See `fusion-photoreal-render`.

---

## Status

Model of record **SLAB_TOP** — 289 bodies, 12 components, 78 timeline features,
**0 named user parameters** (the largest open gap, TBD-14). Built and verified
11 September 2026 on Fusion build 2705.1.11.

Open decisions: TBD-12 … TBD-19, listed in `docs/SLAB_PRD_RevC.pdf` §11.2.
DEC-C1 … DEC-C7 are **closed** — do not re-raise them.
