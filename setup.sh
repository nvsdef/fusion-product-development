#!/usr/bin/env bash
# ============================================================================
#  DO NOT RUN THIS SCRIPT - IT IS INCOMPLETE IN THIS DISTRIBUTION.
#
#  It calls four helpers that are not present in this repository:
#      scripts/setup/cad_agent.py          (line ~74, fails immediately)
#      scripts/setup/plugins.py
#      scripts/setup/patch_timeouts.py
#      scripts/setup/sync_shared_skills.py
#
#  Follow SETUP.md instead. It documents the manual path that was actually
#  used to produce a complete run, and takes about 30 minutes.
#
#  The rest of this file is retained for reference only - the MANUAL STEPS
#  block at the end is accurate and SETUP.md is derived from it.
# ============================================================================
exit 1
# Fusion Autonomous CAD Engineer Community Example (NemoClaw + Hermes) — one-shot setup.
#
# Onboards a single NemoClaw/Hermes sandbox and wires three agents behind an
# one agent (cad-engineer) passing an ordered sequence of gates:
# geometry-signoff -> cmf-signoff -> render-signoff -> drawing-release.
#
# There is NO custom image and no Dockerfile. Fusion is a host GUI application,
# nothing solves in the sandbox, so onboarding is stock and the sandbox holds
# only the agents.
#
# What runs where:
#   sandbox       : the three Hermes agents
#   host          : Fusion 2026 GUI, the Fusion360MCP add-in (TCP 9876), and
#                   the fusion-mcp stdio bridge the client spawns
#
# Usage:
#   ./setup.sh                    # preflight + onboard + wire skills/MCP/policy
#   ./setup.sh --no-plugins       # skip host plug-in install + MCP wiring
#   ./setup.sh --reset-sandbox    # destroy + re-onboard the sandbox first
#   ./setup.sh --gpu              # request GPU passthrough into the sandbox
#   ./setup.sh --no-gpu           # onboard without GPU passthrough (default)
#   ./setup.sh --wipe-agent-memory # clear Hermes sessions/memories/cache
#   ./setup.sh --wipe-everything  # the above + render/drawing/export artifacts
#   ./setup.sh -h                 # help
#
# One entrypoint. Idempotent — safe to re-run. Skips steps already done.
#
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Permissive umask: restrictive umasks (e.g. 0027 on NVIDIA-domain hosts) make
# files under ~/.nemoclaw/source/ unreadable to the sandbox build user.
umask 0022
if [ -d "${HOME}/.nemoclaw/source" ]; then
    chmod -R o+rX "${HOME}/.nemoclaw/source" 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

cad_setup_python() {
    bash "${SCRIPT_DIR}/scripts/setup/python.sh" "$@"
}

# Auto-source .env (defaults only — already-exported vars win), then fill in
# the .env_template defaults for anything still unset. Template: .env_template.
# shellcheck source=scripts/setup/env-loader.sh
. "${SCRIPT_DIR}/scripts/setup/env-loader.sh"
cad_env_load_defaults "${SCRIPT_DIR}/.env"
cad_env_load_defaults "${HOME}/.env"
cad_env_fusion_defaults

FUSION_MCP_REPO="${FUSION_MCP_REPO:-}"
FUSION_MCP_TIMEOUT="${FUSION_MCP_TIMEOUT:-300}"

# This example ships a single harness: Hermes via NemoClaw.
HARNESS="hermes"
export CAD_HARNESS="${HARNESS}"

# Source the Hermes harness shim (defines harness_* hooks: sandbox onboarding,
# runtime install, MCP registration, agent emission, inference config +
# optional override).
# shellcheck source=harnesses/hermes/runtime.sh
source "${SCRIPT_DIR}/harnesses/hermes/runtime.sh"

# Load cad-agent.yaml values as CA_* shell vars. cad_agent.py also validates
# the agent roster and the pipeline gates here, so a bad gate name fails now
# rather than after the sandbox has been rebuilt. On a fresh clone it may warn
# about skills that step 1 below has not fanned out yet; those clear on the
# next run.
CAD_AGENT_SHELL="$(cad_setup_python "${SCRIPT_DIR}/scripts/setup/cad_agent.py" --harness "${HARNESS}" --shell)" || {
    echo "ERROR: could not load cad-agent.yaml" >&2
    exit 1
}
eval "${CAD_AGENT_SHELL}"
unset CAD_AGENT_SHELL

SANDBOX_NAME="${SANDBOX_NAME:-${CA_SANDBOX_NAME}}"

# Harness-specific paths (SHARED_DIR, GATEWAY_NAME, ...). There is no baked
# tool env to point at — every CAD operation leaves the sandbox over the
# fusion-mcp stdio bridge.
harness_paths
export OPENSHELL_GATEWAY="${GATEWAY_NAME}"

# Pipeline roster from cad-agent.yaml. All five arrays are emitted in pipeline
# order and are positionally parallel — AGENT_NAMES[i] clears GATE_NAMES[i],
# and its SOUL/TOOLS/skills are at index i of the other three.
IFS=' ' read -ra AGENT_NAMES     <<< "${CA_AGENTS}"
IFS=' ' read -ra GATE_NAMES      <<< "${CA_GATES}"
IFS=' ' read -ra SKILL_DIRS_RAW  <<< "${CA_SKILL_DIRS}"
SKILL_DIRS=()
for REL in "${SKILL_DIRS_RAW[@]}"; do SKILL_DIRS+=("${SCRIPT_DIR}/${REL}"); done
IFS=' ' read -ra SOUL_PATHS_RAW  <<< "${CA_SOUL_PATHS:-}"
IFS=' ' read -ra TOOLS_PATHS_RAW <<< "${CA_TOOLS_PATHS:-}"

# Flags. (There are no in-sandbox tool installs to skip — nothing is baked in
# and nothing installs at runtime.)
SKIP_PLUGINS=false
RESET_SANDBOX=false
WIPE_AGENT_MEMORY=false
WIPE_EVERYTHING=false
# Default off, unlike the CAE example: nothing in this sandbox uses a GPU.
# Fusion's raytracer runs on the host GPU inside Fusion itself.
USE_GPU_REQUEST="${CAD_USE_GPU:-false}"
USE_GPU=false

# Inference is selected during NemoClaw/OpenShell onboarding. The Hermes harness
# mirrors that gateway route into config.yaml; it does not create providers
# unless the optional cad-agent.yaml `inference:` block + a credential are
# present, in which case harness_validate_env sets INFERENCE_OVERRIDE=true and
# harness_apply_inference_override re-pins the route below.
HERMES_GATEWAY_MODEL=""
INFERENCE_OVERRIDE=false
INFERENCE_PROVIDER=""
INFERENCE_MODEL=""
INFERENCE_TIMEOUT=""
harness_validate_env

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-plugins)        SKIP_PLUGINS=true; shift ;;
        --reset-sandbox)     RESET_SANDBOX=true; shift ;;
        --gpu)               USE_GPU_REQUEST=true; shift ;;
        --no-gpu)            USE_GPU_REQUEST=false; shift ;;
        --wipe-agent-memory) WIPE_AGENT_MEMORY=true; shift ;;
        --wipe-everything)   WIPE_AGENT_MEMORY=true; WIPE_EVERYTHING=true; shift ;;
        -h|--help)
            sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1 (use -h for help)" >&2; exit 1 ;;
    esac
done

host_has_nvidia_gpu() {
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1
}

HOST_HAS_NVIDIA_GPU=false
host_has_nvidia_gpu && HOST_HAS_NVIDIA_GPU=true

case "${USE_GPU_REQUEST}" in
    auto|"")
        USE_GPU="${HOST_HAS_NVIDIA_GPU}"
        ;;
    true|1|yes|on)
        if [ "${HOST_HAS_NVIDIA_GPU}" = true ]; then
            USE_GPU=true
        else
            echo "[WARN] GPU passthrough requested, but no NVIDIA GPU was detected on the host; onboarding without it." >&2
            USE_GPU=false
        fi
        ;;
    false|0|no|off)
        USE_GPU=false
        ;;
    *)
        echo "ERROR: CAD_USE_GPU must be auto, true, or false (got '${USE_GPU_REQUEST}')." >&2
        exit 1
        ;;
esac

# ── Sandbox IO helpers (used here and by harnesses/hermes/runtime.sh hooks) ──
sandbox_run_script() {
    local tmp_script; tmp_script=$(mktemp)
    echo "$1" > "$tmp_script"
    openshell sandbox upload "${SANDBOX_NAME}" "$tmp_script" "/tmp/_setup_script.sh"
    openshell sandbox exec -n "${SANDBOX_NAME}" -- bash /tmp/_setup_script.sh
    rm -f "$tmp_script"
}

sandbox_exec() {
    if [ "$#" -eq 3 ] && [ "$2" = "-c" ] && { [ "$1" = "sh" ] || [ "$1" = "bash" ]; }; then
        printf '%s' "$3" | openshell sandbox exec -n "${SANDBOX_NAME}" --no-tty -- "$1"
    else
        openshell sandbox exec -n "${SANDBOX_NAME}" --no-tty -- "$@"
    fi
}

sandbox_write() {
    openshell sandbox exec -n "${SANDBOX_NAME}" --no-tty -- tee "$1" >/dev/null
}

sandbox_write_file() {
    local src="$1" dest="$2"
    [ -f "${src}" ] || { echo "ERROR: sandbox_write_file: ${src} not found" >&2; return 1; }
    sandbox_exec rm -rf "${dest}" 2>/dev/null || true
    sandbox_write "${dest}" < "${src}"
}

# Substitute the few sandbox-path placeholders in skill / SOUL / TOOLS prose.
sub_paths() {
    sed -e "s|\${SHARED_DIR}|${SHARED_DIR}|g" \
        -e "s|\${SCRIPTS_DIR}|${SCRIPTS_DIR}|g" \
        -e "s|\${AGENTS_DIR}|${AGENTS_DIR}|g"
}

transform_markdown() {
    if declare -F harness_transform_markdown >/dev/null; then
        harness_transform_markdown
    else
        cat
    fi
}

install_host_plugins() {
    [ "${SKIP_PLUGINS}" = false ] || return 0

    for PLUGIN in ${PLUGIN_NAMES}; do
        MANIFEST_JSON=$(cad_setup_python "${SCRIPT_DIR}/scripts/setup/plugins.py" manifest "${PLUGIN}")
        GPU_REQ=$(echo "${MANIFEST_JSON}" | cad_setup_python -c "import json,sys;print(json.load(sys.stdin).get('runtime',{}).get('gpu_required',False))")
        INSTALL_SCRIPT=$(echo "${MANIFEST_JSON}" | cad_setup_python -c "import json,sys;print(json.load(sys.stdin).get('endpoint',{}).get('install_script',''))")
        # fusion-mcp DOES declare one (host/install.sh: clone the fork, uv sync,
        # copy the add-in, patch the timeouts). It cannot finish the job — the
        # stdio server is spawned by the client and the add-in has to be enabled
        # by hand in Fusion's GUI, which is the MANUAL STEPS block at the end of
        # this script. A plug-in with nothing to install omits the key.
        [ -z "${INSTALL_SCRIPT}" ] && { echo "[SKIP] plug-in ${PLUGIN}: no install_script (nothing to daemonise)"; continue; }
        if [ "${GPU_REQ}" = "True" ] && [ "${HOST_HAS_NVIDIA_GPU}" = false ]; then
            echo "[WARN] plug-in ${PLUGIN} needs a host GPU (nvidia-smi absent) — skipping host install; MCP unreachable."
            continue
        fi
        FULL_PATH="${SCRIPT_DIR}/plugins/${PLUGIN}/${INSTALL_SCRIPT}"
        [ -f "${FULL_PATH}" ] || { echo "[WARN] plug-in ${PLUGIN}: install_script missing at ${FULL_PATH}"; continue; }
        echo "--- Plug-in ${PLUGIN}: host install ---"
        bash "${FULL_PATH}" || echo "[WARN] plug-in ${PLUGIN} host install failed — re-run plugins/${PLUGIN}/${INSTALL_SCRIPT}"
        echo ""
    done
}

# Discover host plug-ins.
if [ "${SKIP_PLUGINS}" = false ]; then
    PLUGIN_NAMES=$(cad_setup_python "${SCRIPT_DIR}/scripts/setup/plugins.py" list | tr '\n' ' ')
else
    PLUGIN_NAMES=""
fi

echo "=============================================="
echo "  Fusion Autonomous CAD Engineer — setup"
echo "  Sandbox:   ${SANDBOX_NAME}"
echo "  GPU:       ${USE_GPU} (sandbox only; Fusion renders on the host GPU)"
echo "  Plug-ins:  ${PLUGIN_NAMES:-(none / disabled)}"
for I in "${!AGENT_NAMES[@]}"; do
    printf "  Stage %s:   %-18s gate: %s\n" \
        "$((I + 1))" "${AGENT_NAMES[$I]}" "${GATE_NAMES[$I]:-(none)}"
done
if [ "${INFERENCE_OVERRIDE}" = true ]; then
    echo "  Inference: override (${INFERENCE_PROVIDER} / ${INFERENCE_MODEL})"
else
    echo "  Inference: OpenShell gateway route (onboarded default)"
fi
echo "=============================================="
echo ""

# ════════════════════════════════════════════════════════════
#  Host preflight — steps 1 to 3 need neither a sandbox nor Fusion
# ════════════════════════════════════════════════════════════

echo "== 1. syncing shared skills into each agent =="
python3 scripts/setup/sync_shared_skills.py

echo
echo "== 2. validating SLAB layout (no Fusion required) =="
python3 scripts/setup/verify_layout.py

echo
echo "== 3. patching Fusion MCP timeouts =="
if [ -n "$FUSION_MCP_REPO" ] && [ -d "$FUSION_MCP_REPO" ]; then
  python3 scripts/setup/patch_timeouts.py "$FUSION_MCP_REPO" "$FUSION_MCP_TIMEOUT"
else
  echo "  SKIPPED - set FUSION_MCP_REPO in .env (see .env_template)"
  echo "  Both timeouts MUST be raised: create_drawing takes ~47 s and"
  echo "  fails at the stock 30 s."
fi

# ════════════════════════════════════════════════════════════
#  Sandbox onboarding
# ════════════════════════════════════════════════════════════
echo
echo "== 4. onboarding the workspace =="
harness_setup_sandbox
echo ""
harness_install_runtime

# ════════════════════════════════════════════════════════════
#  Host plug-in install
#
#  Runs before skill deployment so any external skills living in upstream
#  checkouts exist when plugins.py resolves them. fusion-mcp has none today.
# ════════════════════════════════════════════════════════════
install_host_plugins

# ════════════════════════════════════════════════════════════
#  Phase 1 — config (skills, shared dirs, MCP wiring, agent identity)
# ════════════════════════════════════════════════════════════

# ── Deploy skills ─────────────────────────────────────────
# One flat skills dir per sandbox, fed from all three agents' trees. The shared
# fusion-mcp-core is byte-identical in each after step 1, so the repeated
# upload is a no-op rather than a conflict.
echo "--- Deploying skills ---"
sandbox_exec mkdir -p "${SKILLS_PATH}"

SKILL_STAGE=$(mktemp -d)
trap 'rm -rf "${SKILL_STAGE}"' EXIT
upload_one_skill() {
    local src_dir="$1" name staged
    name="$(basename "${src_dir}")"
    staged="${SKILL_STAGE}/${name}"
    rm -rf "${staged}"; cp -R "${src_dir}" "${staged}"
    while IFS= read -r -d '' f; do
        sub_paths < "$f" | transform_markdown > "${f}.tmp" && mv "${f}.tmp" "$f"
    done < <(find "${staged}" -type f -name '*.md' -print0)
    sandbox_exec rm -rf "${SKILLS_PATH:?}/${name}"
    sandbox_exec mkdir -p "${SKILLS_PATH}"
    openshell sandbox upload "${SANDBOX_NAME}" "${staged}" "${SKILLS_PATH}/"
}
upload_skills_from() {
    local root="$1" sub
    [ -d "${root}" ] || return 0
    for sub in "${root}"/*/; do
        [ -d "${sub}" ] && upload_one_skill "${sub%/}"
    done
}

for SKILL_DIR in "${SKILL_DIRS[@]}"; do
    upload_skills_from "${SKILL_DIR}"
done
if [ "${SKIP_PLUGINS}" = false ]; then
    # FD 3 isolates the loop input from `openshell sandbox exec` (whose gRPC
    # client drains stdin) so the second read doesn't hit EOF mid-deploy.
    while IFS=$'\t' read -r _plugin _name _agent path <&3; do
        [ -d "${path}" ] && upload_one_skill "${path}"
    done 3< <(cad_setup_python "${SCRIPT_DIR}/scripts/setup/plugins.py" skills)
fi
sandbox_exec find "${SKILLS_PATH}" -name "*.py" -exec chmod +x {} \;
sandbox_exec find "${SKILLS_PATH}" -name "*.sh" -exec chmod +x {} \;
SKILL_COUNT=$(sandbox_exec bash -c "find ${SKILLS_PATH} -name SKILL.md 2>/dev/null | wc -l")
echo "[OK] ${SKILL_COUNT} skills deployed"

# Sweep orphan skills (self-healing under renames). Do not sweep when
# --no-plugins is used for a model-only/config-only rerun; otherwise existing
# plug-in skills look like orphans and get deleted.
EXPECTED_SKILLS=$(
    {
        for SKILL_DIR in "${SKILL_DIRS[@]}"; do
            [ -d "${SKILL_DIR}" ] && ls -1 "${SKILL_DIR}" 2>/dev/null
        done
        if [ "${SKIP_PLUGINS}" = false ]; then
            cad_setup_python "${SCRIPT_DIR}/scripts/setup/plugins.py" skills | awk -F'\t' '{print $2}'
        fi
        :
    } | sort -u
)
if [ "${SKIP_PLUGINS}" = false ]; then
    CURRENT_SKILLS=$(sandbox_exec sh -c "ls ${SKILLS_PATH} 2>/dev/null" | sort -u)
    ORPHAN_SKILLS=$(comm -13 <(echo "${EXPECTED_SKILLS}") <(echo "${CURRENT_SKILLS}"))
    for S in ${ORPHAN_SKILLS}; do
        [ -n "${S}" ] || continue
        sandbox_exec rm -rf "${SKILLS_PATH}/${S}"
        echo "[CLEAN] Removed orphan skill: ${S}"
    done
else
    echo "[SKIP] Orphan skill cleanup disabled with --no-plugins"
fi

LEGACY_HOME_SKILLS="/sandbox/.hermes/skills"
if [ "${SKILLS_PATH}" != "${LEGACY_HOME_SKILLS}" ] && [ "${SKIP_PLUGINS}" = false ]; then
    for S in ${EXPECTED_SKILLS}; do
        [ -n "${S}" ] || continue
        sandbox_exec rm -rf "${LEGACY_HOME_SKILLS}/${S}" 2>/dev/null || true
    done
fi
STRAYS=$(sandbox_exec sh -c "find ${SKILLS_PATH} -maxdepth 1 -type f -printf '%f\n' 2>/dev/null" | tr -d '\r' || true)
for F in ${STRAYS}; do
    [ -n "${F}" ] || continue
    sandbox_exec rm -f "${SKILLS_PATH}/${F}"
    echo "[CLEAN] Removed stray top-level file: ${F}"
done

# Optional memory wipe.
if [ "${WIPE_AGENT_MEMORY}" = true ] || [ "${WIPE_EVERYTHING}" = true ]; then
    if declare -F harness_wipe_state >/dev/null; then harness_wipe_state; fi
fi

# ── Sandbox shared directories ────────────────────────────
sandbox_run_script "mkdir -p ${SHARED_DIR}/{renders,drawings,exports,status,reports}"
echo "[OK] Shared directories under ${SHARED_DIR}"
echo ""

# ── Hermes inference config (OpenShell gateway route) ─────
# Apply the optional override (no-op unless INFERENCE_OVERRIDE=true) first, so
# the mirror step below reads back the freshly-pinned gateway model.
harness_apply_inference_override
harness_configure_inference

# ── MCP registration (Hermes config.yaml mcp_servers) ─────
echo "--- Configuring agents ---"
harness_register_mcps

# ── Plug-in egress policy fragments ───────────────────────
if [ "${SKIP_PLUGINS}" = false ]; then
    TMP_MERGED=$(mktemp "${TMPDIR:-/tmp}/cad-policy.XXXXXX.yaml")
    if openshell policy get "${SANDBOX_NAME}" --full 2>/dev/null \
         | awk '/^---$/{p=1; next} p' \
         | cad_setup_python "${SCRIPT_DIR}/scripts/setup/plugins.py" policy-fragments \
           > "${TMP_MERGED}" 2>/dev/null \
       && [ -s "${TMP_MERGED}" ]; then
        if openshell policy set --policy "${TMP_MERGED}" --wait "${SANDBOX_NAME}" >/dev/null 2>&1; then
            echo "[OK] plug-in + baseline policy fragments applied"
        else
            echo "[WARN] failed to apply plug-in egress policies — see policy.yaml"
        fi
    else
        echo "[WARN] could not merge plug-in policy fragments — see policy.yaml"
    fi
    rm -f "${TMP_MERGED}"
fi

# ── Agent identity (SOUL.md + TOOLS.md + AGENTS.md + role cards) ──
harness_emit_agents

echo "[OK] Pipeline: ${AGENT_NAMES[*]}"
echo ""

# ════════════════════════════════════════════════════════════
#  Verify (host side — Fusion need not be running yet)
# ════════════════════════════════════════════════════════════
echo "--- Verify ---"

socket_open() {
    python3 - "$1" "$2" <<'PY' >/dev/null 2>&1
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket()
s.settimeout(1.5)
sys.exit(0 if s.connect_ex((host, port)) == 0 else 1)
PY
}

if [ -n "${FUSION_MCP_REPO}" ] && [ -d "${FUSION_MCP_REPO}" ]; then
    echo "[OK] fusion-mcp-server checkout: ${FUSION_MCP_REPO}"
else
    echo "[WARN] FUSION_MCP_REPO is unset or not a directory — the stdio bridge"
    echo "       cannot be registered and step 3 could not patch the timeouts."
    echo "       Copy .env_template to .env and set it."
fi

if [ -n "${FUSION_MCP_PYTHON}" ] && [ -x "${FUSION_MCP_PYTHON}" ]; then
    echo "[OK] fusion-mcp interpreter: ${FUSION_MCP_PYTHON}"
else
    echo "[WARN] fusion-mcp interpreter not executable at '${FUSION_MCP_PYTHON:-unset}'."
    echo "       Create the checkout's venv, or set FUSION_MCP_PYTHON in .env."
fi

CONN_PY="${FUSION_MCP_REPO}/src/fusion360_mcp/connection.py"
if [ -f "${CONN_PY}" ] && grep -q "_TIMEOUT = ${FUSION_MCP_TIMEOUT%.*}" "${CONN_PY}" 2>/dev/null; then
    echo "[OK] client timeout patched to ${FUSION_MCP_TIMEOUT}s"
else
    echo "[WARN] client timeout not confirmed at ${FUSION_MCP_TIMEOUT}s in ${CONN_PY:-<unset>}."
    echo "       create_drawing measured 47.2 s and fails at the stock 30 s."
    echo "       Re-run step 3, then RESTART THE CLIENT FROM THE SYSTEM TRAY —"
    echo "       connection.py runs in the MCP server process, not the add-in."
fi

if socket_open 127.0.0.1 "${FUSION_MCP_PORT}"; then
    echo "[OK] Fusion360MCP add-in socket open on 127.0.0.1:${FUSION_MCP_PORT}"
else
    echo "[WARN] nothing listening on 127.0.0.1:${FUSION_MCP_PORT} — expected until"
    echo "       Fusion is running with the add-in. See the manual steps below."
fi

echo ""
printf "=== Setup complete (sandbox: %s) ===\n" "${SANDBOX_NAME}"

cat <<'MANUAL'

== MANUAL STEPS ON THE HOST ==

Fusion is a GUI application; unlike the CAE example there is no in-sandbox
solver. Everything CAD happens through the host MCP.

  a. Install the add-in (Windows):
       Copy addon\* to
       %APPDATA%\Autodesk\Autodesk Fusion 360\API\AddIns\Fusion360MCP\

  b. In Fusion: UTILITIES > Scripts and Add-Ins > Add-Ins tab
       Fusion360MCP > Run, tick "Run on Startup"
       *** THEN CLOSE THE DIALOG *** -- it is modal and blocks Fusion's
       main thread. Every API call times out while it is open.

  c. Restart the client from the SYSTEM TRAY (not just the window).
     connection.py runs in the MCP server process.

  d. Verify the socket:
       Test-NetConnection 127.0.0.1 -Port 9876

  e. In a new session ask for get_scene_info -- NOT ping.
     ping answers even when the main thread is blocked, so it tells you
     nothing.

Then:  nemohermes cad connect
       sandbox$ hermes chat
       > Read examples/01_slab_mixer/prompt.md and run that build.
MANUAL
