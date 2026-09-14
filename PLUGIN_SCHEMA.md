# Plugin schema

A plugin is declared in two places. `cad-agent.yaml` says it is active and
who may use it; `plugins/<name>/plugin.yaml` is the manifest the setup
scripts read.

## The `cad-agent.yaml` entry

Host MCPs declared in `cad-agent.yaml` under `plugins:`.

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | referenced from each agent's `plugins:` list |
| `path` | yes | repo-relative directory holding the plugin manifest, README and host scripts |
| `runs_on` | yes | `host` or `sandbox` |
| `transport` | yes | `stdio` or `http`. Only `stdio` is wired today — `scripts/setup/plugins.py` and `harnesses/hermes/render-config.py` both exit on anything else rather than register something the client cannot spawn |
| `description` | yes | one paragraph; state *why* this transport |

## The `plugins/<name>/plugin.yaml` manifest

Read by `scripts/setup/plugins.py`. `plugins/fusion-mcp/plugin.yaml` is the
worked example and is commented block by block; the blocks are `source:`
(upstream repo, ref, env var, on-disk default), `runtime:` (`location`,
`gpu_required`), `endpoint:` (`kind`, `transport`, `host`, `port`,
`install_script`, `run_script`), `skills:` (plug-in-owned skills, each with an
`owner_agent`) and `mcp_server:` (`transport`, `command`, `args`, `env` —
`${...}` expanded from the environment at setup time).

`endpoint.host` + `endpoint.port` is what the sandbox egress lane is
synthesised from, so a plugin that declares no port contributes no rule.

## This example

```yaml
plugins:
  - name: fusion-mcp
    path: plugins/fusion-mcp
    runs_on: host
    transport: stdio
```

`runs_on: host` because Fusion is a desktop GUI application — there is no
headless mode to run in the sandbox, which is the main structural difference
from the CAE example where the solver runs in-sandbox.

`transport: stdio` is a deliberate choice, not a default. Autodesk publishes
an HTTP MCP at `127.0.0.1:27182`, and it works — but reaching it requires
the client's **custom connector** path, which enterprise policy commonly
disables. The stdio bridge is configured from a local file and is not
governed by connector policy.

`policy.yaml` therefore excludes 27182 explicitly, with a comment saying why.

## Adding a plugin

1. Create `plugins/<name>/README.md` documenting the architecture, the tool
   surface, and any tools that must **not** be used.
2. Create `plugins/<name>/plugin.yaml` — the manifest above. If the client
   spawns the server, the README's registration block is the single source of
   truth for the invocation and `mcp_server:` reproduces it.
3. Add the entry to `cad-agent.yaml`.
4. Add the egress rule to `policy.yaml` — default is deny.
5. List it in the `plugins:` array of every agent that needs it.
6. Document broken or dangerous tools in `TOOLS.md` under "Do not use", with
   the reason. A tool that freezes the host application belongs there.
