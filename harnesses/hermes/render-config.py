#!/usr/bin/env python3
"""Render Hermes Agent configuration artifacts from cad-agent.yaml.

Hermes reads:
  * $HERMES_HOME/config.yaml for MCP servers and runtime config.
  * $HERMES_HOME/SOUL.md for the primary agent identity.
  * /sandbox/workspace/AGENTS.md for project-specific instructions.

This helper emits the Hermes-specific pieces that setup.sh uploads through
harnesses/hermes/runtime.sh.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts" / "setup"))
HARNESS = "hermes"
os.environ["CAD_HARNESS"] = HARNESS
import cad_agent  # noqa: E402
import plugins  # noqa: E402


def render_markdown(source: str) -> str:
    """Translate the shared canonical Markdown for Hermes runtime prompts."""

    def mcp_name(match: re.Match[str]) -> str:
        server = match.group(1).replace("-", "_")
        tool = match.group(2)
        return f"mcp_{server}_{tool}"

    def delegate_call(match: re.Match[str]) -> str:
        agent = match.group(1)
        task = match.group(2)
        role_card = f"/sandbox/workspace/.hermes/agents/{agent}.md"
        return (
            "delegate_task(\n"
            f"  goal=\"{task}\",\n"
            f"  context=\"Read {role_card} first. Include the role card, campaign brief, inputs, output paths, and acceptance criteria.\",\n"
            '  toolsets=["terminal", "file"]\n'
            ")"
        )

    text = source
    text = re.sub(
        r'sessions_spawn\(agentId="([^"]+)", task="([^"]*)"\)',
        delegate_call,
        text,
    )
    text = text.replace("`sessions_spawn`", "`delegate_task`")
    text = text.replace("sessions_spawn", "delegate_task")
    text = text.replace("`runTimeoutSeconds: 0`", "a long-running `delegate_task` brief with explicit status/output paths")
    text = text.replace("runTimeoutSeconds: 0", "a long-running delegate_task brief with explicit status/output paths")
    text = text.replace("non-blocking spawns", "long-running delegations")
    text = text.replace("non-blocking-spawn", "long-running-delegation")
    # `fusion360__export` in the prose becomes `mcp_fusion360_export`, the
    # runtime-native tool name Hermes exposes for a registered MCP server.
    text = re.sub(
        r"(?<![A-Za-z0-9_])([A-Za-z][A-Za-z0-9-]*)__([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])",
        mcp_name,
        text,
    )
    text = text.replace("*__review_plan", "mcp_*_review_plan")
    text = text.replace("`__review_plan`", "`_review_plan`")
    return text


def render_mcp() -> str:
    """Return a config.yaml fragment containing Hermes `mcp_servers:`.

    The CAE reference emitted `{transport, url}` because all of its plug-ins
    were streamable-http. fusion-mcp is stdio: there is no URL, the client
    spawns the server and speaks MCP over its stdin/stdout, so the entry
    carries `command` + `args` (+ `env`) instead.

    NOTE / TODO(verify): the command and args are HOST paths — see
    plugins/fusion-mcp/README.md, where the documented client registration is
    a host-side `mcpServers` entry pointing at the fusion-mcp-server venv
    interpreter. Confirm that whichever client actually spawns the process can
    resolve ${FUSION_MCP_PYTHON}; a Hermes process inside the sandbox cannot
    see the host filesystem.
    """
    servers: dict[str, dict[str, Any]] = {}
    for entry in plugins.iter_mcp_servers():
        name = entry["name"]
        transport = entry["transport"]
        if transport != "stdio":
            sys.exit(
                f"ERROR: plug-in '{name}' mcp_server.transport must be "
                f"'stdio' for this example (got {transport!r})"
            )
        server: dict[str, Any] = {
            "transport": transport,
            "command": entry["command"],
            "args": entry.get("args", []),
            "enabled": True,
        }
        if entry.get("env"):
            server["env"] = entry["env"]
        servers[name] = server
    return yaml.safe_dump({"mcp_servers": servers}, sort_keys=False)


def _agent_entry(role: str, cfg: dict) -> dict[str, Any]:
    """Return the flattened view of one agent used by the role card."""
    entry = cad_agent.agent_entry(role, cfg)
    return {
        "name": role,
        "description": entry.get("description") or "",
        "soul": cad_agent.agent_soul(role, cfg),
        "tools_md": cad_agent.agent_tools_md(role, cfg),
        "skills": cad_agent.agent_skill_names(role, cfg),
        "plugins": cad_agent.agent_plugins(role, cfg),
        "stage": cad_agent.stage_number(role, cfg),
        "gate": cad_agent.gate_for(role, cfg),
    }


def _read_repo_file(rel: str) -> str:
    if not rel:
        return ""
    path = REPO_ROOT / rel
    return path.read_text() if path.is_file() else ""


def render_role_card(role: str) -> str:
    """Return a stage role card the operator (or delegate_task) can hand over.

    Unlike the reference — where role cards existed only for sub-agents and
    `main` was rejected — every agent here is a pipeline stage and gets one.
    """
    cfg = cad_agent.load(HARNESS)
    entry = _agent_entry(role, cfg)
    stages = cad_agent.pipeline(cfg)
    stage_no = entry["stage"]
    total = len(stages)
    prev_stage = next((s for s in stages if s["stage"] == (stage_no or 0) - 1), None)
    next_stage = next((s for s in stages if s["stage"] == (stage_no or 0) + 1), None)

    body_parts = [
        _read_repo_file(entry["soul"]).rstrip(),
        _read_repo_file(entry["tools_md"]).rstrip(),
    ]
    body = "\n\n".join(part for part in body_parts if part).rstrip()

    lines = [
        f"# {role} — stage {stage_no} of {total}",
        "",
        f"Description: {entry['description']}",
        f"Exit gate: `{entry['gate'] or '(none)'}`",
        f"Skills: {', '.join(entry['skills']) or '(none declared)'}",
        f"Plug-ins: {', '.join(entry['plugins']) or '(none declared)'}",
        "",
        "## Pipeline Position",
        "",
    ]
    if prev_stage:
        lines += [
            f"You may not start until stage {prev_stage['stage']} "
            f"(`{prev_stage['agent']}`) has cleared its gate "
            f"`{prev_stage['gate']}`. Verify that before your first tool call.",
        ]
    else:
        lines += [
            "You are the first stage. Nothing gates your start, and everything "
            "downstream is blocked until you clear your own gate.",
        ]
    lines.append("")
    if next_stage:
        lines += [
            f"When `{entry['gate']}` is signed off, hand off to stage "
            f"{next_stage['stage']} (`{next_stage['agent']}`). Until then, "
            f"nobody downstream starts.",
            "",
        ]
    else:
        lines += [
            f"You are the last stage. `{entry['gate']}` is the release gate for "
            f"the whole run.",
            "",
        ]

    # The one rule that only applies downstream of geometry.
    if stage_no and stage_no > 1:
        owner = stages[0]["agent"]
        lines += [
            "## You Do Not Edit Geometry",
            "",
            f"Geometry has exactly one owner: `{owner}` (stage 1). You hold "
            "`execute_code` and *could* change the model. Do not.",
            "",
            "If you find a geometric defect — a see-through aperture, a missing "
            f"feature, a collision — report it to `{owner}` with the measurement "
            "that proves it, and stop. Fixing it here makes your output disagree "
            "with the model, voids stage 1's regression volumes, and leaves the "
            "defect unrecorded so it returns on the next rebuild.",
            "",
        ]

    lines += [
        "## Delegation Contract",
        "",
        "When the orchestrator delegates to this stage, it must include this",
        "role card in the `delegate_task` context because Hermes children start",
        "with fresh context and do not inherit the parent conversation.",
        "",
        "## Stage Instructions",
        "",
        body,
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("mcp", help="render Hermes mcp_servers config fragment")
    sub.add_parser("markdown", help="translate shared Markdown for Hermes")
    role = sub.add_parser("role-card", help="render one stage role card")
    role.add_argument("role")
    args = parser.parse_args()

    # Parse once so YAML errors fail before partial setup writes.
    cad_agent.load(HARNESS)

    if args.cmd == "mcp":
        sys.stdout.write(render_mcp())
    elif args.cmd == "markdown":
        sys.stdout.write(render_markdown(sys.stdin.read()))
    else:
        sys.stdout.write(render_role_card(args.role))
    return 0


if __name__ == "__main__":
    sys.exit(main())
