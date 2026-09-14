#!/usr/bin/env bash
# Idempotent host-side install for the fusion-mcp plug-in.
# Clones the faust-machines/fusion360-mcp-server fork on the host, resolves
# its Python deps with uv, and drops the Fusion360MCP add-in into the user's
# Fusion AddIns directory. Both halves of the bridge come from that one
# checkout — the stdio MCP server and the in-process add-in it talks to.
#
# Host prerequisites: Autodesk Fusion 2026 installed and launchable, plus
# `git` and `uv` on PATH. Fusion is a GUI application with no headless mode,
# so the user launches it by hand; this script cannot do that, and cannot do
# the four in-Fusion steps it prints at the end either. Read them.
#
# Usage:
#   ./install.sh                          # clone + uv sync + install add-in
#   FUSION_MCP_REPO=/path ./install.sh    # non-default checkout location
#
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=./env.sh
. "${SCRIPT_DIR}/env.sh"

# Mirrors source.{repo,ref} in ../plugin.yaml. scripts/setup/python.sh could
# read the manifest, but it requires uv to be on PATH before the prerequisite
# check below has run, so the pin is duplicated here instead and the script
# stays runnable stand-alone. Keep the two in sync; override per-run with the
# env vars for ad-hoc swaps.
UPSTREAM_REPO="${FUSION_MCP_UPSTREAM_REPO:-https://github.com/faust-machines/fusion360-mcp-server.git}"
UPSTREAM_REF="${FUSION_MCP_UPSTREAM_REF:-main}"

echo "=== fusion-mcp host install ==="
echo "  source repo:  ${UPSTREAM_REPO}"
echo "  source ref:   ${UPSTREAM_REF}"
echo "  checkout:     ${FUSION_MCP_REPO}"
echo "  AddIns dir:   ${FUSION_ADDINS_DIR:-<undetected>}"
echo "  output dir:   ${FUSION_OUTPUT_DIR}"
echo "  addin socket: 127.0.0.1:${FUSION_MCP_PORT}"
echo ""

# 1. Prerequisites. Fail loudly and early — a half-installed bridge fails
#    later as a mysterious socket timeout, which is far more expensive to
#    diagnose than a missing binary here.
if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git not found on PATH." >&2
    echo "       Install git and re-run." >&2
    exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is required for Python dependencies." >&2
    echo "       Install it from https://docs.astral.sh/uv/getting-started/installation/ and re-run." >&2
    exit 1
fi

if [ -z "${FUSION_ADDINS_DIR}" ]; then
    echo "ERROR: could not detect Fusion's AddIns directory." >&2
    echo "       Looked for \$APPDATA (Windows) and ~/Library/Application Support (macOS)." >&2
    echo "       Set FUSION_ADDINS_DIR in .env — see .env_template — e.g." >&2
    echo "         Windows: %APPDATA%/Autodesk/Autodesk Fusion 360/API/AddIns" >&2
    echo "         macOS:   ~/Library/Application Support/Autodesk/Autodesk Fusion 360/API/AddIns" >&2
    exit 1
fi

# 2. Clone or refresh the fork. Idempotent: an existing checkout is fetched
#    and fast-forwarded, never clobbered — local patches to the add-in are a
#    normal part of working on this plug-in and must survive a re-run.
if [ -d "${FUSION_MCP_REPO}/.git" ]; then
    CURRENT_REF="$(git -C "${FUSION_MCP_REPO}" rev-parse --abbrev-ref HEAD)"
    echo "[OK] Existing checkout (branch ${CURRENT_REF})"
    echo "--- Fetching ${UPSTREAM_REF} ---"
    git -C "${FUSION_MCP_REPO}" fetch --tags origin
    if git -C "${FUSION_MCP_REPO}" diff --quiet && git -C "${FUSION_MCP_REPO}" diff --cached --quiet; then
        git -C "${FUSION_MCP_REPO}" checkout "${UPSTREAM_REF}"
        git -C "${FUSION_MCP_REPO}" pull --ff-only || \
            echo "[WARN] fast-forward declined — checkout has diverged; leaving it alone" >&2
    else
        echo "[WARN] local modifications present — skipping checkout/pull" >&2
        echo "       (expected if you are iterating on the add-in; commit or stash to refresh)" >&2
    fi
else
    echo "--- Cloning ${UPSTREAM_REPO} @ ${UPSTREAM_REF} ---"
    git clone --branch "${UPSTREAM_REF}" --single-branch \
        "${UPSTREAM_REPO}" "${FUSION_MCP_REPO}"
fi

# 3. Resolve the server's own dependencies from its pyproject. This is what
#    creates ${FUSION_MCP_REPO}/.venv — the interpreter that both host/run.sh
#    and the client's stdio launch invoke as
#    `<venv>/python -m fusion360_mcp --mode socket` (the form recorded in
#    plugins/fusion-mcp/README.md) — without a second dependency list here.
echo "--- uv sync ---"
( cd "${FUSION_MCP_REPO}" && uv sync )
echo "[OK] Python deps resolved in ${FUSION_MCP_REPO}/.venv"

# 4. Install the add-in. Fusion loads an add-in from a directory whose name
#    matches its entry point, so the target is always <AddIns>/Fusion360MCP/.
#
#    TODO(verify): the fork's add-in source layout. Two shapes are in play
#    and this script accepts either without guessing:
#      a) addon/Fusion360MCP/  — already a Fusion-shaped add-in directory;
#         copied across as-is.
#      b) addon/               — the add-in files at the top of addon/,
#         which is what setup.sh's manual step ("Copy addon\* to
#         ...\AddIns\Fusion360MCP\") and scripts/setup/patch_timeouts.py
#         (addon/server/event_bridge.py) both describe; contents are copied
#         into a Fusion360MCP directory we create.
#    Confirm against the checkout and drop the branch that does not apply.
ADDON_DIR="${FUSION_ADDINS_DIR}/Fusion360MCP"
if [ -d "${FUSION_MCP_REPO}/addon/Fusion360MCP" ]; then
    ADDON_SRC="${FUSION_MCP_REPO}/addon/Fusion360MCP"
elif [ -d "${FUSION_MCP_REPO}/addon" ]; then
    ADDON_SRC="${FUSION_MCP_REPO}/addon"
else
    echo "ERROR: no add-in source found in ${FUSION_MCP_REPO}." >&2
    echo "       Expected addon/Fusion360MCP/ or addon/ — upstream layout changed?" >&2
    exit 1
fi

echo "--- Installing Fusion360MCP add-in ---"
echo "  from: ${ADDON_SRC}"
echo "  to:   ${ADDON_DIR}"
mkdir -p "${FUSION_ADDINS_DIR}"
# Idempotent overwrite so re-running picks up add-in changes. Fusion caches
# Python modules per process: a fresh copy is NOT live until the add-in is
# Stopped and Run again, and submodule edits may need a full Fusion restart.
rm -rf "${ADDON_DIR}"
mkdir -p "${ADDON_DIR}"
cp -R "${ADDON_SRC}/." "${ADDON_DIR}/"
echo "[OK] Add-in installed at ${ADDON_DIR}"

# 5. The render/drawing output directory must exist before anything is
#    submitted — startLocalRender fails QUIETLY when it does not, and the
#    symptom is a render that simply never finishes.
mkdir -p "${FUSION_OUTPUT_DIR}"
echo "[OK] Output dir ${FUSION_OUTPUT_DIR}"

# 6. Timeouts. Both sides must agree; the stock 30 s fails create_drawing.
echo "--- Timeouts ---"
python3 "${REPO_ROOT}/scripts/setup/patch_timeouts.py" \
        "${FUSION_MCP_REPO}" "${FUSION_MCP_TIMEOUT}" || \
    echo "[WARN] patch_timeouts.py failed — run it by hand before any raytraced render (the 1100 px q92 hero takes ~130 s)" >&2

cat <<MANUAL

=== fusion-mcp install complete — NOW THE PART THIS SCRIPT CANNOT DO ===

Fusion is a GUI application. Four steps have to happen in front of the
screen, in this order. Skipping any one of them produces a bridge that
looks installed and answers nothing.

  a. In Fusion: UTILITIES > Scripts and Add-Ins > Add-Ins tab
       Fusion360MCP > Run, and tick "Run on Startup".

  b. *** CLOSE THE SCRIPTS AND ADD-INS DIALOG. ***
     It is modal and holds Fusion's main thread. Every API call times out
     while it is open — and 'ping' still answers, because it never enters
     the API. That is exactly why 'ping' is not the health check.

  c. Restart the client from the SYSTEM TRAY, not just its window.
     src/fusion360_mcp/connection.py runs in the MCP server process, so a
     timeout change (step 6 above) is not live until that process restarts.

  d. Verify the add-in socket:
       PowerShell:  Test-NetConnection 127.0.0.1 -Port ${FUSION_MCP_PORT}
       expect       TcpTestSucceeded : True

     Then verify the MAIN THREAD, which the socket check cannot see:
       python3 ${SCRIPT_DIR}/fusion_mcp.py --probe

Add-in log: \$HOME/fusion360mcp.log — read it first when anything fails.
MANUAL
