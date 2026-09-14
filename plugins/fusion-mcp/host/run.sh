#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Foreground-run the Fusion stdio MCP server.
#
# A stdio server is normally launched BY THE CLIENT — it speaks JSON-RPC on
# its own stdin/stdout and there is nothing to daemonise. Running it by hand
# gives you a server nobody is talking to. This script exists for two
# narrower jobs:
#   * scripts/start-coprocesses.sh, which needs one uniform run_script per
#     plug-in even when the plug-in has nothing to background; and
#   * manual smoke-testing — "does the server start, and can it reach the
#     add-in?" — before handing the session to an agent.
# For the client-side registration (the path that actually gets used), see
# plugins/fusion-mcp/README.md.
#
# Assumes host/install.sh has been run AND Fusion is running with the
# Fusion360MCP add-in Run and the Scripts and Add-Ins dialog CLOSED.
#
# Usage:
#   ./run.sh                              # probe, then foreground the server
#   FUSION_MCP_PORT=9877 ./run.sh         # non-default add-in socket

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=./env.sh
. "${SCRIPT_DIR}/env.sh"

# FUSION_MCP_PYTHON — the checkout's venv interpreter — is derived from
# FUSION_MCP_REPO by the repo-level loader, which probes the Windows and POSIX
# venv layouts. Source it rather than repeating the probe here.
# shellcheck source=../../../scripts/setup/env-loader.sh
. "${REPO_ROOT}/scripts/setup/env-loader.sh"
cad_env_fusion_defaults

echo "=== Fusion MCP (stdio) ===" >&2
echo "  server:       ${FUSION_MCP_REPO}" >&2
echo "  interpreter:  ${FUSION_MCP_PYTHON:-<unset>}" >&2
echo "  addin socket: 127.0.0.1:${FUSION_MCP_PORT}" >&2
echo "  timeout:      ${FUSION_MCP_TIMEOUT}s (both sides)" >&2
echo "  output dir:   ${FUSION_OUTPUT_DIR}" >&2
echo "" >&2

if [ ! -d "${FUSION_MCP_REPO}" ]; then
    echo "ERROR: ${FUSION_MCP_REPO} not found. Run host/install.sh first." >&2
    exit 1
fi

if [ -z "${FUSION_MCP_PYTHON}" ] || [ ! -x "${FUSION_MCP_PYTHON}" ]; then
    echo "ERROR: no venv interpreter at '${FUSION_MCP_PYTHON:-<unset>}'." >&2
    echo "       host/install.sh runs 'uv sync' in ${FUSION_MCP_REPO}, which" >&2
    echo "       creates it. Or set FUSION_MCP_PYTHON in .env." >&2
    exit 1
fi

# Preflight. host/fusion_mcp.py connects to the add-in socket and issues
# get_scene_info — a command that MUST be marshalled onto Fusion's main
# thread — so it distinguishes the two ways this bridge is dead:
#   * nothing listening        -> the add-in was never Run;
#   * listening but no answer  -> the Scripts and Add-Ins dialog is still
#                                 open. It is modal, it holds the main
#                                 thread, and 'ping' would happily answer
#                                 from the socket thread while every real
#                                 call times out.
# Starting the server on a wedged main thread just moves the failure to the
# agent's first tool call, minutes later, where it reads as a model problem.
if ! python3 "${SCRIPT_DIR}/fusion_mcp.py" --probe; then
    echo "" >&2
    echo "ERROR: the Fusion360MCP add-in did not answer get_scene_info." >&2
    echo "       Fix Fusion before starting the server:" >&2
    echo "         1. UTILITIES > Scripts and Add-Ins > Add-Ins > Fusion360MCP > Run" >&2
    echo "         2. CLOSE that dialog — it is modal and blocks the main thread" >&2
    echo "         3. Have a design document open and active" >&2
    echo "       Add-in log: \$HOME/fusion360mcp.log" >&2
    exit 1
fi

echo "" >&2
echo "Main thread responsive. Foregrounding the stdio server — it will sit" >&2
echo "waiting for JSON-RPC on stdin. Ctrl-C to stop." >&2
echo "" >&2

# SINGLE SOURCE OF TRUTH for the invocation: the "Client registration" block
# in plugins/fusion-mcp/README.md — the checkout's venv interpreter plus
# `-m fusion360_mcp --mode socket`. ../plugin.yaml's `mcp_server:` block is
# the same form (${FUSION_MCP_PYTHON} + the same args), and this line is the
# third copy. Calling the interpreter directly rather than `uv run` keeps uv
# out of the runtime path, exactly as the README says, and means the smoke
# test exercises the same process the client will spawn.
exec "${FUSION_MCP_PYTHON}" -m fusion360_mcp --mode socket
