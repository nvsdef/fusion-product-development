# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Defaults-only .env loader. Sourced by:
#   - setup.sh
#   - scripts/start-coprocesses.sh
#
# Why a custom loader instead of `set -a; . .env; set +a`:
# the standard pattern unconditionally overwrites already-exported
# vars (the sourced `KEY=value` line is a plain assignment). We want
# the inverse — the parent shell's exports win — so that
# `KEY=val ./setup.sh` works as a one-off override without the user
# editing their .env, and so that explicit env on a tmux window
# survives a subsequent re-source. Bash-specific (uses `${!key+x}`
# indirect expansion).
#
# Format expected: a sequence of `KEY=value` lines, optionally with
# surrounding single or double quotes around value. Lines starting with
# `#` or blank are skipped. Lines without a valid identifier= prefix
# are skipped silently (so `# inline note` etc. don't blow up).

cad_env_load_defaults() {
    local f="$1" line key val
    [ -f "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip leading whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        # Skip comments and blanks.
        case "$line" in ''|\#*) continue ;; esac
        # Must look like KEY=…  (POSIX identifier on the left side).
        case "$line" in [A-Za-z_][A-Za-z0-9_]*=*) ;; *) continue ;; esac
        key="${line%%=*}"
        val="${line#*=}"
        # Skip if the parent shell already set this key — even to empty.
        [ -n "${!key+x}" ] && continue
        # Strip exactly one layer of surrounding quotes if present.
        case "$val" in
            \'*\') val="${val#\'}"; val="${val%\'}" ;;
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
        esac
        export "$key=$val"
    done < "$f"
}


# ── cad_env_fusion_defaults ─────────────────────────────────
# Apply the .env_template defaults for anything the operator did not set.
# Same precedence rule as above: an already-exported value always wins, so
# this only fills gaps. Call it AFTER cad_env_load_defaults so a real .env
# beats these.
#
# The template ships Windows-shaped example paths (`C:/Users/<you>/...`,
# `%APPDATA%/...`) because Fusion 2026 is a Windows/macOS desktop app. Those
# are placeholders, not defaults — a POSIX-side fallback is derived here where
# one exists and left empty where it does not, so a missing value fails with a
# named variable instead of a half-expanded path.
cad_env_fusion_defaults() {
    # Where the fusion-mcp-server checkout lives on the host. No sane default:
    # setup.sh step 3 skips the timeout patch and tells the operator to set it.
    export FUSION_MCP_REPO="${FUSION_MCP_REPO:-}"

    # Add-in socket. Must match event_bridge/socket_server and the egress rule
    # scripts/setup/plugins.py synthesises from plugins/fusion-mcp/plugin.yaml.
    export FUSION_MCP_PORT="${FUSION_MCP_PORT:-9876}"

    # Both timeouts, seconds. create_drawing measured 47.2 s and fails at the
    # stock 30 s, so 300 is the floor, not a safety margin.
    export FUSION_MCP_TIMEOUT="${FUSION_MCP_TIMEOUT:-300}"

    # Fusion add-in install target. %APPDATA% only exists on Windows; leave the
    # value empty elsewhere rather than inventing a path the operator would
    # then have to notice was wrong.
    if [ -z "${FUSION_ADDINS_DIR:-}" ] && [ -n "${APPDATA:-}" ]; then
        FUSION_ADDINS_DIR="${APPDATA}/Autodesk/Autodesk Fusion 360/API/AddIns"
    fi
    export FUSION_ADDINS_DIR="${FUSION_ADDINS_DIR:-}"

    # Where renders and drawings are written. The template's
    # C:/Users/<you>/Documents/fusion-renders is per-user, so the fallback is
    # HOME-relative.
    export FUSION_OUTPUT_DIR="${FUSION_OUTPUT_DIR:-${HOME}/fusion-renders}"

    # NOTE: derived, not in .env_template. plugins/fusion-mcp/plugin.yaml
    # registers the stdio server as `command: ${FUSION_MCP_PYTHON}`, and
    # plugins/fusion-mcp/README.md calls the checkout's venv interpreter
    # directly to keep `uv` out of the runtime path. Windows and POSIX venvs
    # put it in different places, so probe both and fall back to the Windows
    # form the README documents. Override in .env for a non-venv interpreter.
    if [ -z "${FUSION_MCP_PYTHON:-}" ] && [ -n "${FUSION_MCP_REPO}" ]; then
        if [ -x "${FUSION_MCP_REPO}/.venv/Scripts/python.exe" ]; then
            FUSION_MCP_PYTHON="${FUSION_MCP_REPO}/.venv/Scripts/python.exe"
        elif [ -x "${FUSION_MCP_REPO}/.venv/bin/python" ]; then
            FUSION_MCP_PYTHON="${FUSION_MCP_REPO}/.venv/bin/python"
        else
            FUSION_MCP_PYTHON="${FUSION_MCP_REPO}/.venv/Scripts/python.exe"
        fi
    fi
    export FUSION_MCP_PYTHON="${FUSION_MCP_PYTHON:-}"
}
