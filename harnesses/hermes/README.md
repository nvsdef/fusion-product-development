# Hermes harness

Wiring for running this workspace under [Hermes Agent](https://hermes-agent.nousresearch.com).
Hermes supports MCP and the open [agentskills.io](https://agentskills.io) skill
format natively, so the plug-in and the six skills in
`agents/cad-engineer/skills/` transfer unchanged.

## Files

| File | Purpose |
|---|---|
| `runtime.sh` | Entry point — exports the environment and launches the agent |
| `render-config.py` | Renders `cad-agent.yaml` + `plugins/*/plugin.yaml` into the harness config |
| `registry-patch.py` | Registers the MCP server and applies the `tools.include` filter |
| `model-default.py` | Resolves the default model when onboarding has not pinned one |

## One agent, four gates

There is **one** agent — `cad-engineer` — and it passes an ordered sequence of
gates. This is not a pipeline of agents handing off to each other; an earlier
three-agent split was retired because the run is one long dependent chain in
which every stage needs the measurements the previous stage produced, and a
handoff is where that state gets dropped.

| # | Gate | Cleared when |
|---|---|---|
| 1 | `geometry-signoff` | 289 bodies, 12 components, timeline clean, every stage volume met |
| 2 | `cmf-signoff` | 11 appearances, 0 mismatches, 0 unnamed bodies, 0 stray face overrides |
| 3 | `render-signoff` | LED pad G:R 0.55 ± 0.03, exactly 10 pad blobs, per-channel spread ≤ 7 |
| 4 | `drawing-release` | crop-aspect error ≤ 0.11 % per view, sheet rasterised and inspected |

Every gate is numeric. The agent reports the number, not a verdict, and a gate
that cannot be evaluated is reported as unevaluated rather than passed.

## Coming from Claude Code

```bash
hermes import-agent claude-code
```

migrates the `mcpServers` block, the skills and the instructions in one command.
The `mcpServers` shape in `~/.claude.json` maps directly onto `mcp_servers` in
`~/.hermes/config.yaml`.

## Settings that must be overridden

The defaults in most harness adapters are wrong for this workload. `cad-agent.yaml`
sets them under `harnesses.hermes.limits`; if you configure Hermes directly,
set them there:

| Setting | Common default | Needs | Why |
|---|---|---|---|
| `max_tokens` | **512** | **≥ 8192** | One feature class is 150+ lines of Python in a single tool argument |
| `max_turns` | 20–50 | **≥ 150** | ~50 dependent tool calls over ~45 min |
| tool timeout | 30–60 s | **≥ 300 s** | `create_drawing` measured 47.2 s and succeeds past the default |
| reasoning effort | sometimes `none` | **medium** | The closed-form volume checksums need it |

And register **eight** MCP tools, not the ~95 the add-in publishes — the
include-list is in `cad-agent.yaml`.

## Where it has to run

**On the same machine as Fusion.** Hermes supports Docker, SSH, Daytona, Modal,
Singularity and Vercel Sandbox backends; none of them can reach a Fusion GUI.
Use the local terminal backend.
