#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Env shim sourced by install.sh and run.sh — single source of truth for
# fusion-mcp plug-in paths and runtime knobs.
#
# Every export below is `${VAR:-default}`, so anything already set wins.
# setup.sh and scripts/start-coprocesses.sh both `set -a && . ./.env`
# before doing anything, which means the repo .env (see .env_template) is
# the user-facing override surface and this file only supplies fallbacks.
#
# One variable is deliberately NOT here: FUSION_MCP_PYTHON, the venv
# interpreter that runs the stdio server. It is DERIVED from FUSION_MCP_REPO,
# and the Windows/POSIX probe lives once in scripts/setup/env-loader.sh
# (cad_env_fusion_defaults). run.sh sources that after this file; install.sh
# does not need it, because `uv sync` is what creates the venv in the first
# place.

# Where the faust-machines/fusion360-mcp-server fork is checked out on the
# host. The source pin (repo + ref) lives in plugins/fusion-mcp/plugin.yaml's
# source.{repo,ref} block; this is just where it lands on disk. The same
# checkout holds BOTH halves of the bridge: the stdio MCP server under
# src/fusion360_mcp/ and the Fusion add-in under addon/.
export FUSION_MCP_REPO="${FUSION_MCP_REPO:-${HOME}/fusion-mcp-server}"

# The add-in's socket. The stdio server connects here; the add-in then
# marshals each command onto Fusion's main thread. Must match the port the
# add-in binds (addon socket_server) and the allow rule in policy.yaml.
export FUSION_MCP_PORT="${FUSION_MCP_PORT:-9876}"

# Seconds. Applies to BOTH sides of the socket and they must agree or one
# cuts the other off — addon/server/event_bridge.py's submit(..., timeout=)
# and src/fusion360_mcp/connection.py's _TIMEOUT. Raise them with
# scripts/setup/patch_timeouts.py; the stock 30 s fails create_drawing,
# which measured 47.2 s. Changing connection.py needs a FULL client restart
# because it runs in the MCP server process, not in the add-in.
export FUSION_MCP_TIMEOUT="${FUSION_MCP_TIMEOUT:-300}"

# Fusion's per-user AddIns directory — install.sh copies the add-in here.
# Fusion requires the folder name to match the add-in entry point, so the
# install target is always <AddIns>/Fusion360MCP/.
#   Windows (Git Bash / WSL with $APPDATA visible):
#       %APPDATA%\Autodesk\Autodesk Fusion 360\API\AddIns
#   macOS:
#       ~/Library/Application Support/Autodesk/Autodesk Fusion 360/API/AddIns
# The vendor folder is still named "Autodesk Fusion 360" on 2026 installs.
# If yours differs, set FUSION_ADDINS_DIR in .env rather than editing this.
_fusion_default_addins_dir() {
    if [ -n "${APPDATA:-}" ]; then
        printf '%s' "${APPDATA}/Autodesk/Autodesk Fusion 360/API/AddIns"
    elif [ -d "${HOME}/Library/Application Support" ]; then
        printf '%s' "${HOME}/Library/Application Support/Autodesk/Autodesk Fusion 360/API/AddIns"
    else
        printf '%s' ""      # unresolved — install.sh turns this into a clear error
    fi
}
export FUSION_ADDINS_DIR="${FUSION_ADDINS_DIR:-$(_fusion_default_addins_dir)}"

# Where renders and drawing PDFs are written. This directory must EXIST
# before a render is submitted: startLocalRender fails quietly when it does
# not, and the failure looks like a render that never finishes rather than
# an error. install.sh creates it.
export FUSION_OUTPUT_DIR="${FUSION_OUTPUT_DIR:-${HOME}/fusion-renders}"
