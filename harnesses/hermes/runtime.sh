#!/usr/bin/env bash
# CAD Agent — Hermes harness shim.
#
# Sourced by root setup.sh after cad_agent.py --shell loads CA_* vars. Defines
# the harness_* hook contract setup.sh calls, on top of NemoClaw's first-class
# Hermes onboarding path.
#
# Differences from the CAE reference harness (harnesses/hermes/runtime.sh
# there), all forced by Fusion being a host GUI application:
#   * No Dockerfile, so no build context to stage, no base image to pull and
#     no docker-storage precheck. Onboarding is a plain `nemoclaw onboard` /
#     `nemohermes onboard` with no `--from`.
#   * No baked tool env under /sandbox/cae: nothing solves in-sandbox.
#   * Three agents behind an ordered pipeline of gates, not one agent with
#     optional sub-agents — see harness_emit_agents.
#
# SPDX-License-Identifier: Apache-2.0


# ── harness_paths ───────────────────────────────────────────
# NemoClaw starts and recovers Hermes with HERMES_HOME=/sandbox/.hermes.
# Keep the managed CAD config in that same home so `nemohermes connect`,
# `hermes gateway run`, and manual `hermes chat` all see the same provider,
# tools, skills, and SOUL.
harness_paths() {
    MAIN_WORKSPACE="/sandbox/workspace"
    AGENTS_DIR="${MAIN_WORKSPACE}/.hermes"
    AGENT_CONFIG_DIR="/sandbox/.hermes"
    HERMES_HOME_DIR="${AGENT_CONFIG_DIR}"
    CONFIG_YAML_PATH="${AGENT_CONFIG_DIR}/config.yaml"
    SKILLS_PATH="${AGENTS_DIR}/skills"
    STATE_ROOT="${MAIN_WORKSPACE}"
    SHARED_DIR="${MAIN_WORKSPACE}/shared"
    SCRIPTS_DIR="${AGENTS_DIR}/scripts"
    SUBAGENT_DIR="${AGENTS_DIR}/agents"
    # There is no in-sandbox tool env. Every CAD, render and drawing operation
    # goes out over the fusion-mcp stdio bridge to the host Fusion session; the
    # agents' own notes and reports live under ${SHARED_DIR}.
    GATEWAY_NAME="${CA_GATEWAY:-nemoclaw}"
}


hermes_setup_python() {
    cad_setup_python "$@"
}


harness_landlock_dirs() {
    echo "/sandbox/workspace"
}


harness_transform_markdown() {
    hermes_setup_python "${SCRIPT_DIR}/harnesses/hermes/render-config.py" markdown
}


hermes_root_exec() {
    # Run a command as root inside the Hermes sandbox container.
    command -v docker >/dev/null 2>&1 || return 1
    local container
    container="$(docker ps --filter "label=openshell.ai/sandbox-name=${SANDBOX_NAME}" \
        --format '{{.Names}}' 2>/dev/null | head -n1)"
    if [ -z "${container}" ]; then
        container="$(docker ps --format '{{.Names}}' 2>/dev/null \
            | grep -m1 "^openshell-${SANDBOX_NAME}-" || true)"
    fi
    [ -n "${container}" ] || return 1
    docker exec -u 0 "${container}" "$@"
}


hermes_nemoclaw_source_dir() {
    local candidates=()
    [ -n "${NEMOCLAW_SOURCE_DIR:-}" ] && candidates+=("${NEMOCLAW_SOURCE_DIR}")
    candidates+=("${HOME}/.nemoclaw/source")
    if command -v npm >/dev/null 2>&1; then
        local npm_root
        npm_root="$(npm root -g 2>/dev/null || true)"
        [ -n "${npm_root}" ] && candidates+=("${npm_root}/nemoclaw")
    fi
    candidates+=(
        "/opt/homebrew/lib/node_modules/nemoclaw"
        "/usr/local/lib/node_modules/nemoclaw"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        [ -n "${candidate}" ] || continue
        if [ -f "${candidate}/agents/hermes/start.sh" ] \
           && [ -f "${candidate}/scripts/lib/sandbox-init.sh" ] \
           && [ -d "${candidate}/agents/hermes/config" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    echo "ERROR: could not find NemoClaw Hermes runtime files." >&2
    echo "       Expected agents/hermes/start.sh under ~/.nemoclaw/source or the installed nemoclaw package." >&2
    return 1
}

# NOTE: the CAE reference defined harness_prepare_docker_context,
# hermes_dockerfile_base_image, hermes_pull_base_image and
# hermes_check_docker_storage here. All four are deleted: this example ships
# no Dockerfile because nothing is baked into the sandbox, so there is no
# build context to stage, no ARG BASE_IMAGE to read, and no ~12 GiB image
# build to make room for. hermes_nemoclaw_source_dir is kept — it is still
# how the harness proves a usable NemoClaw install is present.


hermes_refresh_config_hash() {
    hermes_root_exec sh -lc '
        set -e
        config_dir=/sandbox/.hermes
        [ -f "$config_dir/config.yaml" ] && [ -f "$config_dir/.env" ] || exit 0
        mkdir -p /etc/nemoclaw
        sha256sum "$config_dir/config.yaml" "$config_dir/.env" > /etc/nemoclaw/hermes.config-hash
        chown root:root /etc/nemoclaw/hermes.config-hash 2>/dev/null || true
        chmod 444 /etc/nemoclaw/hermes.config-hash 2>/dev/null || true
        sha256sum "$config_dir/config.yaml" "$config_dir/.env" > "$config_dir/.config-hash"
        chown sandbox:sandbox "$config_dir/.config-hash" 2>/dev/null || true
        chmod 600 "$config_dir/.config-hash" 2>/dev/null || true
    ' || true
}


hermes_ensure_cli_path() {
    if hermes_root_exec sh -lc '
        set -e
        if [ -x /usr/local/bin/hermes ] && /usr/local/bin/hermes --version >/dev/null 2>&1; then
            exit 0
        fi

        hermes_python=
        for candidate in /opt/hermes/.venv/bin/python /opt/hermes/.venv/bin/python3; do
            if [ -x "$candidate" ]; then
                hermes_python="$candidate"
                break
            fi
        done

        if [ -x /opt/hermes/.venv/bin/hermes ] \
            && /opt/hermes/.venv/bin/hermes --version >/dev/null 2>&1; then
            ln -sf /opt/hermes/.venv/bin/hermes /usr/local/bin/hermes
        elif [ -n "$hermes_python" ] \
            && "$hermes_python" -c "import hermes_cli.main" >/dev/null 2>&1; then
            printf "%s\n" \
                "#!/usr/bin/env sh" \
                "exec ${hermes_python} -m hermes_cli.main \"\$@\"" \
                > /usr/local/bin/hermes
            chmod 755 /usr/local/bin/hermes
        else
            echo "Hermes CLI not found in /usr/local/bin or /opt/hermes/.venv" >&2
            ls -la /usr/local/bin/hermes /opt/hermes/.venv/bin/hermes /opt/hermes/.venv/bin/python /opt/hermes/.venv/bin/python3 2>/dev/null || true
            exit 1
        fi

        /usr/local/bin/hermes --version >/dev/null
    '; then
        echo "[OK] Hermes CLI -> /usr/local/bin/hermes"
    else
        echo "[ERROR] Could not ensure /usr/local/bin/hermes; recreate the sandbox after refreshing the Hermes base image." >&2
        return 1
    fi
}


# ── harness_validate_env ─────────────────────────────────────
# Inference is configured by NemoClaw/OpenShell onboarding; this harness mirrors
# the selected gateway model into Hermes config.yaml (see
# harness_configure_inference) so `hermes chat` does not prompt for setup.
#
# The optional cad-agent.yaml `inference:` block is an override on top of that:
# when provider_name, provider_type, model, AND a credential are all present,
# harness_apply_inference_override creates/updates an OpenShell provider from
# INFERENCE_API_KEY, pins both user and system routes, updates NemoClaw's
# sandbox registry, and rewrites Hermes's model.default — keeping base_url at
# inference.local. Empty fields (the yaml default) leave INFERENCE_OVERRIDE
# false and the onboarded route untouched.
harness_validate_env() {
    HERMES_GATEWAY_MODEL=""
    INFERENCE_PROVIDER="${CA_INFERENCE_PROVIDER_NAME:-}"
    INFERENCE_PROVIDER_TYPE="${CA_INFERENCE_PROVIDER_TYPE:-}"
    INFERENCE_MODEL="${CA_INFERENCE_MODEL:-}"
    INFERENCE_BASE_URL="${CA_INFERENCE_BASE_URL:-}"
    INFERENCE_TIMEOUT="${CA_INFERENCE_TIMEOUT_S:-300}"
    INFERENCE_API_KEY_VALUE="${INFERENCE_API_KEY:-${CA_INFERENCE_API_KEY:-}}"
    INFERENCE_OVERRIDE=false
    if [ -n "${INFERENCE_PROVIDER}" ] && [ -n "${INFERENCE_PROVIDER_TYPE}" ] \
        && [ -n "${INFERENCE_MODEL}" ] && [ -n "${INFERENCE_API_KEY_VALUE}" ]; then
        INFERENCE_OVERRIDE=true
    fi
    # Re-export the resolved credential under the canonical name so
    # `openshell provider create --credential INFERENCE_API_KEY` finds it
    # whether it came from the env or an inline yaml api_key.
    [ -n "${INFERENCE_API_KEY_VALUE}" ] && export INFERENCE_API_KEY="${INFERENCE_API_KEY_VALUE}"
    # Expose for scripts/setup/plugins.py (its Python process can't see CA_* shell
    # vars) in case a policy fragment renderer wants the inference egress base.
    [ -n "${INFERENCE_BASE_URL}" ] && export CA_INFERENCE_BASE_URL="${INFERENCE_BASE_URL}"
    return 0
}


# ── harness_apply_inference_override ─────────────────────────
# No-op unless the optional cad-agent.yaml `inference:` block + a credential are
# present (INFERENCE_OVERRIDE=true). Runs before harness_configure_inference so
# the mirror step reads back the freshly-pinned gateway model.
harness_apply_inference_override() {
    [ "${INFERENCE_OVERRIDE}" = true ] || return 0
    echo "--- Hermes inference override ---"

    local INFERENCE_BASE_URL_KEY="$(echo "${INFERENCE_PROVIDER_TYPE}" | tr '[:lower:]' '[:upper:]')_BASE_URL"
    local PROVIDER_CONFIG_ARGS=()
    [ -n "${INFERENCE_BASE_URL}" ] && PROVIDER_CONFIG_ARGS+=(--config "${INFERENCE_BASE_URL_KEY}=${INFERENCE_BASE_URL}")

    if ! openshell provider create \
        --name "${INFERENCE_PROVIDER}" --type "${INFERENCE_PROVIDER_TYPE}" \
        --credential INFERENCE_API_KEY \
        "${PROVIDER_CONFIG_ARGS[@]}" 2>/dev/null; then
        openshell provider update "${INFERENCE_PROVIDER}" \
            --credential INFERENCE_API_KEY \
            "${PROVIDER_CONFIG_ARGS[@]}" 2>/dev/null || true
    fi

    if openshell inference set \
        --provider "${INFERENCE_PROVIDER}" \
        --model "${INFERENCE_MODEL}" \
        --timeout "${INFERENCE_TIMEOUT}" \
        --no-verify >/dev/null 2>&1; then
        echo "[OK] Gateway inference route → ${INFERENCE_PROVIDER} / ${INFERENCE_MODEL} (${INFERENCE_TIMEOUT}s)"
    else
        echo "[WARN] openshell inference set (user) failed — inspect 'openshell inference get'"
    fi

    if openshell inference set --system \
        --provider "${INFERENCE_PROVIDER}" \
        --model "${INFERENCE_MODEL}" \
        --timeout "${INFERENCE_TIMEOUT}" \
        --no-verify >/dev/null 2>&1; then
        echo "[OK] System inference route  → ${INFERENCE_PROVIDER} / ${INFERENCE_MODEL} (${INFERENCE_TIMEOUT}s)"
    else
        echo "[WARN] openshell inference set --system failed — inspect 'openshell inference get'"
    fi

    local REG_PATH="${HOME}/.nemoclaw/sandboxes.json"
    if [ -f "${REG_PATH}" ]; then
        hermes_setup_python "${SCRIPT_DIR}/harnesses/hermes/registry-patch.py" \
            "${SANDBOX_NAME}" "${INFERENCE_PROVIDER}" "${INFERENCE_MODEL}" "${REG_PATH}"
    fi

    sandbox_write_file "${SCRIPT_DIR}/harnesses/hermes/model-default.py" "/tmp/hermes-model-default.py"
    sandbox_exec python3 "/tmp/hermes-model-default.py" "${INFERENCE_MODEL}"
    sandbox_exec rm -f "/tmp/hermes-model-default.py"
    hermes_refresh_config_hash
    echo "[OK] Hermes model.default → ${INFERENCE_MODEL} via inference.local"
    return 0
}


# ── harness_setup_sandbox ───────────────────────────────────
harness_setup_sandbox() {
    if ! command -v nemoclaw &>/dev/null; then
        echo "--- Installing NemoClaw CLI ---"
        curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash || true
        export PATH="$HOME/.local/bin:$PATH"
        command -v nemoclaw &>/dev/null || {
            echo "  nemoclaw not found. Install:"
            echo "    curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash"
            echo "  Then reload the shell: source ~/.bashrc && ./setup.sh"
            exit 0
        }
    fi
    echo "[OK] NemoClaw $(nemoclaw --version 2>/dev/null || echo 'installed')"

    if [ "${RESET_SANDBOX}" = true ] && openshell sandbox get "${SANDBOX_NAME}" &>/dev/null; then
        echo "--- Resetting Hermes sandbox ${SANDBOX_NAME} ---"
        nemoclaw "${SANDBOX_NAME}" destroy --yes >/dev/null 2>&1 \
            || openshell sandbox delete "${SANDBOX_NAME}" || true
    fi

    if openshell sandbox get "${SANDBOX_NAME}" &>/dev/null; then
        echo "[OK] Hermes sandbox already exists"
    else
        echo "--- NemoClaw Hermes onboarding (${SANDBOX_NAME}) ---"
        # Stock onboarding — no `--from <dockerfile>`. There is no custom image
        # for this example: Fusion is a host GUI app, nothing solves in the
        # sandbox, and the sandbox therefore holds only the agents.
        #
        # NOTE: the previous entrypoint ran `nemoclaw onboard --config
        # cad-agent.yaml`. The sandbox identity still comes from that same
        # file — cad_agent.py reads `sandbox.name` into CA_SANDBOX_NAME and it
        # is passed here as --name — but the harness uses the onboarding flags
        # the reference harness uses so the reset/GPU/non-interactive paths
        # behave identically.
        local gpu_value=0
        [ "${USE_GPU}" = true ] && gpu_value=1
        local onboard_status=0
        local sandbox_gpu_flag="--no-sandbox-gpu"
        [ "${USE_GPU}" = true ] && sandbox_gpu_flag="--sandbox-gpu"
        local interactive_onboard=false
        if [ -t 0 ] && [ -t 1 ] && [ -z "${NEMOCLAW_NON_INTERACTIVE:-}" ]; then
            interactive_onboard=true
        fi
        local onboard_args=(
            onboard
            --fresh
            --yes-i-accept-third-party-software
            --name "${SANDBOX_NAME}"
            "${sandbox_gpu_flag}"
        )
        if [ "${interactive_onboard}" = false ]; then
            onboard_args+=(--non-interactive --yes)
        fi
        if command -v nemohermes &>/dev/null; then
            if [ "${interactive_onboard}" = true ]; then
                NEMOCLAW_SANDBOX_NAME="${SANDBOX_NAME}" \
                NEMOCLAW_SANDBOX_GPU="${gpu_value}" \
                    nemohermes "${onboard_args[@]}" || onboard_status=$?
            else
                NEMOCLAW_NON_INTERACTIVE=1 \
                NEMOCLAW_PROVIDER="${NEMOCLAW_PROVIDER:-build}" \
                NEMOCLAW_MODEL="${NEMOCLAW_MODEL:-nvidia/nemotron-3-super-120b-a12b}" \
                NEMOCLAW_SANDBOX_NAME="${SANDBOX_NAME}" \
                NEMOCLAW_SANDBOX_GPU="${gpu_value}" \
                    nemohermes "${onboard_args[@]}" || onboard_status=$?
            fi
        else
            if [ "${interactive_onboard}" = true ]; then
                NEMOCLAW_SANDBOX_NAME="${SANDBOX_NAME}" \
                NEMOCLAW_SANDBOX_GPU="${gpu_value}" \
                    nemoclaw "${onboard_args[@]}" --agent hermes || onboard_status=$?
            else
                NEMOCLAW_NON_INTERACTIVE=1 \
                NEMOCLAW_PROVIDER="${NEMOCLAW_PROVIDER:-build}" \
                NEMOCLAW_MODEL="${NEMOCLAW_MODEL:-nvidia/nemotron-3-super-120b-a12b}" \
                NEMOCLAW_SANDBOX_NAME="${SANDBOX_NAME}" \
                NEMOCLAW_SANDBOX_GPU="${gpu_value}" \
                    nemoclaw "${onboard_args[@]}" --agent hermes || onboard_status=$?
            fi
        fi
        if [ "${onboard_status}" -ne 0 ]; then
            echo "[ERROR] NemoClaw Hermes onboarding failed with status ${onboard_status}." >&2
            if [ "${interactive_onboard}" = false ]; then
                echo "        Non-interactive NVIDIA onboarding needs NVIDIA_API_KEY or NEMOCLAW_PROVIDER_KEY in the environment." >&2
            fi
            return "${onboard_status}"
        fi
    fi
    return 0
}


# ── harness_install_runtime ──────────────────────────────────
harness_install_runtime() {
    sandbox_exec mkdir -p "${AGENT_CONFIG_DIR}" "${MAIN_WORKSPACE}" "${SCRIPTS_DIR}" "${SUBAGENT_DIR}"
    sandbox_exec sh -c "
        python3 - <<'PY'
from pathlib import Path

env_path = Path('${AGENT_CONFIG_DIR}/.env')
env_path.parent.mkdir(parents=True, exist_ok=True)
lines = env_path.read_text().splitlines() if env_path.exists() else []
updates = {
    'API_SERVER_PORT': '18642',
    'API_SERVER_HOST': '127.0.0.1',
    'HERMES_HOME': '${HERMES_HOME_DIR}',
    'HERMES_YOLO_MODE': '1',
    'GATEWAY_ALLOW_ALL_USERS': 'true',
}
seen = set()
out = []
for line in lines:
    stripped = line.strip()
    key = stripped.split('=', 1)[0].removeprefix('export ').strip() if '=' in stripped else ''
    if key in updates:
        out.append(f'{key}={updates[key]}')
        seen.add(key)
    elif stripped:
        out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f'{key}={value}')
env_path.write_text('\\n'.join(out) + '\\n')
PY
    "
    sandbox_exec chmod 600 "${AGENT_CONFIG_DIR}/.env"
    echo "[OK] Hermes env -> ${AGENT_CONFIG_DIR}/.env"
    sandbox_exec sh -c "
        if [ -f /sandbox/.local/bin/hermes ] \
           && grep -q 'Managed by CAD Hermes harness' /sandbox/.local/bin/hermes 2>/dev/null; then
            rm -f /sandbox/.local/bin/hermes
        fi
        rm -f ${SCRIPTS_DIR}/hermes-env.sh
    " || true
    hermes_ensure_cli_path

    # Probe with the Hermes venv python directly: that's what /usr/local/bin/hermes
    # actually imports from, and it has include-system-site-packages=false plus
    # enable_user_site=False, so --user installs are invisible to it. Install
    # straight into the venv as root via hermes_root_exec.
    #
    # The reference probed the streamable-http client because all its plug-ins
    # were HTTP. fusion-mcp is stdio, so the stdio client is what has to import.
    if ! sandbox_exec /opt/hermes/.venv/bin/python3 -c 'from mcp.client.stdio import stdio_client' 2>/dev/null; then
        echo "--- Installing Hermes stdio MCP client dependency ---"
        if ! hermes_root_exec sh -lc '
            set -e
            if ! /opt/hermes/.venv/bin/python3 -m pip --version >/dev/null 2>&1; then
                /opt/hermes/.venv/bin/python3 -m ensurepip --upgrade >/dev/null
            fi
            /opt/hermes/.venv/bin/python3 -m pip install --upgrade --quiet mcp
        '; then
            echo "[WARN] Could not install mcp into /opt/hermes/.venv; the fusion-mcp stdio path may fail." >&2
            echo "       Manual fix: docker exec -u 0 \$(docker ps --filter label=openshell.ai/sandbox-name=${SANDBOX_NAME} --format '{{.Names}}') /opt/hermes/.venv/bin/python3 -m ensurepip && ... -m pip install mcp" >&2
        fi
    fi
    if sandbox_exec sh -c "command -v hermes >/dev/null 2>&1"; then
        local version
        version="$(sandbox_exec sh -c "HERMES_HOME=${HERMES_HOME_DIR} hermes --version 2>/dev/null || HERMES_HOME=${HERMES_HOME_DIR} hermes version 2>/dev/null || true" | tr -d '\r')"
        echo "[OK] Hermes runtime ${version:-available}"
    else
        echo "[WARN] Hermes binary not found in sandbox PATH; NemoClaw Hermes onboarding may be incomplete."
    fi
    hermes_refresh_config_hash
    return 0
}


# ── harness_wipe_state ──────────────────────────────────────
harness_wipe_state() {
    if [ "${WIPE_AGENT_MEMORY}" = true ]; then
        echo "--- Wiping Hermes sessions, memories, and cache ---"
        sandbox_exec sh -c "
            rm -rf ${AGENT_CONFIG_DIR}/sessions/* \
                   ${AGENT_CONFIG_DIR}/memories/* \
                   ${AGENT_CONFIG_DIR}/cache/* 2>/dev/null || true
        " || true
        echo "[OK] Hermes session memory wiped"
    fi

    if [ "${WIPE_EVERYTHING}" = true ]; then
        echo "--- Wiping run artifacts (sandbox + host output dir) ---"
        # Fusion artifact dirs, not the reference's mesh/cfd/cfd_results:
        # renders and drawings are what these three stages produce.
        sandbox_exec sh -c "
            for D in renders drawings exports status reports; do
                rm -rf ${SHARED_DIR}/\${D}/* 2>/dev/null || true
            done
        " || true
        local FS_ROOT="${FUSION_OUTPUT_DIR:-${HOME}/fusion-renders}"
        if [ -d "${FS_ROOT}" ]; then
            local D
            for D in renders drawings exports status reports; do
                rm -rf "${FS_ROOT:?}/${D}"/* 2>/dev/null || true
            done
        fi
        echo "[OK] Run artifacts wiped — sandbox + ${FS_ROOT}"
    fi
    return 0
}


# ── harness_configure_inference ─────────────────────────────
harness_configure_inference() {
    echo "--- Hermes inference route ---"

    HERMES_GATEWAY_MODEL="$(openshell inference get 2>/dev/null | hermes_setup_python -c '
import re
import sys

text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", sys.stdin.read())
section = text.split("Gateway inference:", 1)[-1].split("System inference:", 1)[0]
match = re.search(r"Model:\s*([^\s]+)", section)
if not match:
    sys.exit(1)
print(match.group(1))
' || true)"
    if [ -n "${HERMES_GATEWAY_MODEL}" ] && [ "${HERMES_GATEWAY_MODEL}" != "Not" ]; then
        echo "[OK] OpenShell inference model: ${HERMES_GATEWAY_MODEL}"
    else
        HERMES_GATEWAY_MODEL=""
        echo "[WARN] Could not read an OpenShell inference model; Hermes may prompt for setup."
    fi
    return 0
}


# ── harness_register_mcps ───────────────────────────────────
harness_register_mcps() {
    sandbox_exec mkdir -p "${AGENT_CONFIG_DIR}"

    # NOTE: the reference let a render failure abort setup, because its plug-in
    # URLs were static. Here the stdio command line is resolved from the
    # operator's .env (FUSION_MCP_REPO -> FUSION_MCP_PYTHON), which the repo
    # deliberately treats as optional — setup.sh already SKIPs the timeout
    # patch when it is unset. So a render failure is reported and skipped
    # instead: the skills, policy and agent identity still land, and a second
    # ./setup.sh after editing .env completes the wiring.
    local MCP_FRAGMENT
    if ! MCP_FRAGMENT="$(hermes_setup_python \
            "${SCRIPT_DIR}/harnesses/hermes/render-config.py" mcp 2>&1)"; then
        echo "[ERROR] Could not render the fusion-mcp server entry:" >&2
        printf '%s\n' "${MCP_FRAGMENT}" | sed 's/^/        /' >&2
        echo "[WARN] Skipping MCP registration — Hermes will start with no Fusion tools." >&2
        return 0
    fi
    printf '%s' "${MCP_FRAGMENT}" | sandbox_write "/tmp/hermes-mcp.yaml"

    local MERGE_SCRIPT
    MERGE_SCRIPT="$(mktemp)"
    cat > "${MERGE_SCRIPT}" <<'PY'
#!/usr/bin/env python3
from pathlib import Path
import sys
import yaml

config_path = Path(sys.argv[1])
fragment_path = Path(sys.argv[2])
base_arg = sys.argv[3] if len(sys.argv) > 3 else ""
base_path = Path(base_arg) if base_arg else None
skills_path = sys.argv[4] if len(sys.argv) > 4 else None
model = sys.argv[5] if len(sys.argv) > 5 else ""
config = {}
if base_path and base_path.exists() and base_path.read_text().strip():
    config = yaml.safe_load(base_path.read_text()) or {}
if config_path.exists() and config_path.read_text().strip():
    existing = yaml.safe_load(config_path.read_text()) or {}
    if isinstance(config, dict) and isinstance(existing, dict):
        config.update(existing)
    else:
        config = existing
fragment = yaml.safe_load(fragment_path.read_text()) or {}
config["mcp_servers"] = fragment.get("mcp_servers", {})
approvals = config.get("approvals")
if not isinstance(approvals, dict):
    approvals = {}
approvals["mode"] = "off"
config["approvals"] = approvals
if skills_path:
    skills = config.get("skills")
    if not isinstance(skills, dict):
        skills = {}
    external_dirs = [
        p for p in skills.get("external_dirs", [])
        if isinstance(p, str) and p and p != "/sandbox/workspace/.hermes/home/skills"
    ]
    if skills_path not in external_dirs:
        external_dirs.insert(0, skills_path)
    skills["external_dirs"] = external_dirs
    config["skills"] = skills
if model:
    config["model"] = {
        "default": model,
        "provider": "custom",
        "base_url": "https://inference.local/v1",
    }
config_path.parent.mkdir(parents=True, exist_ok=True)
try:
    original_mode = config_path.stat().st_mode if config_path.exists() else None
    if original_mode is not None:
        config_path.chmod(original_mode | 0o200)
    try:
        config_path.write_text(yaml.safe_dump(config, sort_keys=False))
    finally:
        if original_mode is not None:
            config_path.chmod(original_mode)
except PermissionError:
    if str(config_path) == "/sandbox/.hermes/config.yaml":
        print("[WARN] Hermes config is not writable at /sandbox/.hermes/config.yaml", file=sys.stderr)
    else:
        raise
PY
    sandbox_write_file "${MERGE_SCRIPT}" "/tmp/hermes-merge-mcp.py"
    rm -f "${MERGE_SCRIPT}"
    sandbox_exec python3 "/tmp/hermes-merge-mcp.py" "${CONFIG_YAML_PATH}" "/tmp/hermes-mcp.yaml" "" "${SKILLS_PATH}" "${HERMES_GATEWAY_MODEL:-}"
    sandbox_exec rm -f "/tmp/hermes-merge-mcp.py" "/tmp/hermes-mcp.yaml"
    hermes_refresh_config_hash

    echo "[OK] Hermes config.yaml mcp_servers + skills path merged for ${SANDBOX_NAME}"
    return 0
}


# ── harness_emit_agents ─────────────────────────────────────
# The reference wrote one SOUL.md (agents.main) plus worker role cards only
# when sub_agents existed. Here there are three peers in a strictly ordered
# pipeline, so this writes:
#
#   ${AGENT_CONFIG_DIR}/SOUL.md          stage-1 SOUL — Hermes has exactly one
#                                        boot identity and stage 1 owns the
#                                        session; later stages are entered
#                                        through their role card.
#   ${SUBAGENT_DIR}/<agent>/SOUL.md      every agent's SOUL, verbatim
#   ${SUBAGENT_DIR}/<agent>/TOOLS.md     every agent's TOOLS, verbatim
#   ${SUBAGENT_DIR}/<agent>.md           rendered role card (stage no., gate,
#                                        skills, no-edit rule)
#   ${MAIN_WORKSPACE}/AGENTS.md          the pipeline itself + the gate contract
#   ${MAIN_WORKSPACE}/TOOLS.md           stage-1 TOOLS, matching SOUL.md
harness_emit_agents() {
    sandbox_exec mkdir -p "${MAIN_WORKSPACE}" "${AGENT_CONFIG_DIR}" "${SUBAGENT_DIR}"

    if ! sandbox_exec test -d "${MAIN_WORKSPACE}/.git" 2>/dev/null; then
        sandbox_exec sh -c \
            "cd ${MAIN_WORKSPACE} && git init -q && git config user.email 'cad@local' && git config user.name 'CAD Agent'"
    fi

    local AGENTS_ARR=() GATES_ARR=()
    read -ra AGENTS_ARR <<< "${CA_AGENTS:-}"
    read -ra GATES_ARR  <<< "${CA_GATES:-}"
    local agent_count="${#AGENTS_ARR[@]}"
    if [ "${agent_count}" -eq 0 ]; then
        echo "[ERROR] cad-agent.yaml declared no agents; nothing to emit." >&2
        return 1
    fi

    # ── Per-agent SOUL.md / TOOLS.md ──────────────────────
    local IDX AGENT SOUL_REL TOOLS_REL
    for IDX in "${!AGENTS_ARR[@]}"; do
        AGENT="${AGENTS_ARR[$IDX]}"
        SOUL_REL="${SOUL_PATHS_RAW[$IDX]:-}"
        TOOLS_REL="${TOOLS_PATHS_RAW[$IDX]:-}"
        sandbox_exec mkdir -p "${SUBAGENT_DIR}/${AGENT}"
        if [ -n "${SOUL_REL}" ] && [ -f "${SCRIPT_DIR}/${SOUL_REL}" ]; then
            sub_paths < "${SCRIPT_DIR}/${SOUL_REL}" \
                | transform_markdown \
                | sandbox_write "${SUBAGENT_DIR}/${AGENT}/SOUL.md"
        else
            echo "[WARN] agent '${AGENT}' has no SOUL.md (${SOUL_REL:-unset}); its role card will be thin" >&2
        fi
        if [ -n "${TOOLS_REL}" ] && [ -f "${SCRIPT_DIR}/${TOOLS_REL}" ]; then
            sub_paths < "${SCRIPT_DIR}/${TOOLS_REL}" \
                | transform_markdown \
                | sandbox_write "${SUBAGENT_DIR}/${AGENT}/TOOLS.md"
        else
            echo "[WARN] agent '${AGENT}' has no TOOLS.md (${TOOLS_REL:-unset})" >&2
        fi
    done

    # ── Boot identity: stage 1 ────────────────────────────
    local FIRST_AGENT="${AGENTS_ARR[0]}"
    local FIRST_SOUL="${SOUL_PATHS_RAW[0]:-}"
    local FIRST_TOOLS="${TOOLS_PATHS_RAW[0]:-}"
    if [ -n "${FIRST_SOUL}" ] && [ -f "${SCRIPT_DIR}/${FIRST_SOUL}" ]; then
        sub_paths < "${SCRIPT_DIR}/${FIRST_SOUL}" \
            | transform_markdown \
            | sandbox_write "${AGENT_CONFIG_DIR}/SOUL.md"
    else
        echo "[WARN] stage-1 agent '${FIRST_AGENT}' SOUL.md missing or file not found (${FIRST_SOUL}); Hermes has no custom SOUL.md" >&2
    fi
    if [ -n "${FIRST_TOOLS}" ] && [ -f "${SCRIPT_DIR}/${FIRST_TOOLS}" ]; then
        sub_paths < "${SCRIPT_DIR}/${FIRST_TOOLS}" \
            | transform_markdown \
            | sandbox_write "${MAIN_WORKSPACE}/TOOLS.md"
    fi

    # ── AGENTS.md: the pipeline and the gate contract ─────
    {
        printf '%s\n\n' "# CAD Pipeline — ${CA_WORKSPACE_NAME:-cad}"
        printf '%s\n' "Three agents, one live Autodesk Fusion session, strictly ordered."
        printf '%s\n\n' "Geometry flows one way."
        printf '%s\n' "| Stage | Agent | Exit gate | Role card |"
        printf '%s\n' "|---|---|---|---|"
        for IDX in "${!AGENTS_ARR[@]}"; do
            printf '| %s | `%s` | `%s` | %s |\n' \
                "$((IDX + 1))" \
                "${AGENTS_ARR[$IDX]}" \
                "${GATES_ARR[$IDX]:-(none)}" \
                "${SUBAGENT_DIR}/${AGENTS_ARR[$IDX]}.md"
        done
        echo
        printf '%s\n\n' "## Gate contract"
        printf '%s\n' "1. A stage may not begin until the PREVIOUS stage's gate is cleared."
        printf '%s\n' "   The gate checklist lives in that stage's SOUL.md and every box"
        printf '%s\n' "   must hold. The run is single-prompt: YOU hold the gate. Report the"
        printf '%s\n' "   evidence as you cross it and go on; stop AT a gate only when a box"
        printf '%s\n' "   cannot be met, and say which box failed and what you measured."
        printf '%s\n' "2. Geometry has exactly one owner: stage 1"
        printf '%s\n' "   (\`${FIRST_AGENT}\`). Every later stage holds \`execute_code\` and"
        printf '%s\n' "   *could* change geometry. They must not."
        printf '%s\n' "3. A downstream agent that finds a geometric defect — a see-through"
        printf '%s\n' "   aperture, a missing feature, a collision — REPORTS IT UPSTREAM AND"
        printf '%s\n' "   STOPS. It does not edit. A silent downstream fix makes the render"
        printf '%s\n' "   and the drawing disagree with the model, voids stage 1's"
        printf '%s\n' "   regression volumes, and leaves the defect unrecorded so it returns"
        printf '%s\n' "   on the next rebuild."
        printf '%s\n' "4. Re-entering an earlier stage re-opens its gate: every later gate"
        printf '%s\n' "   must be signed off again against the changed geometry."
        echo
        printf '%s\n\n' "## Stage role cards"
        printf '%s\n' "Read the matching card before starting a stage — each one carries the"
        printf '%s\n' "stage's SOUL, its tool surface, its skills and its exit gate:"
        for IDX in "${!AGENTS_ARR[@]}"; do
            printf -- '- %s: %s\n' "${AGENTS_ARR[$IDX]}" "${SUBAGENT_DIR}/${AGENTS_ARR[$IDX]}.md"
        done
        echo
        printf '%s\n\n' "## Session preconditions (all stages)"
        printf '%s\n' "1. Fusion open, \`Fusion360MCP\` add-in running"
        printf '%s\n' "2. Scripts and Add-Ins dialog CLOSED — it is modal and blocks Fusion's"
        printf '%s\n' "   main thread; every API call times out while it is open"
        printf '%s\n' "3. Both MCP timeouts at ${FUSION_MCP_TIMEOUT:-300} s"
        printf '%s\n' "4. \`get_scene_info\` succeeds — never \`ping\`, which answers even when"
        printf '%s\n' "   the main thread is blocked"
        echo
        printf '%s\n\n' "## Shared output"
        printf '%s\n' "Write run artifacts under ${SHARED_DIR}/{renders,drawings,exports,status,reports}."
    } | sub_paths | transform_markdown | sandbox_write "${MAIN_WORKSPACE}/AGENTS.md"

    # ── Role cards ────────────────────────────────────────
    for AGENT in "${AGENTS_ARR[@]}"; do
        hermes_setup_python "${SCRIPT_DIR}/harnesses/hermes/render-config.py" role-card "${AGENT}" \
            | sub_paths \
            | transform_markdown \
            | sandbox_write "${SUBAGENT_DIR}/${AGENT}.md"
    done

    echo "[OK] Hermes SOUL.md + AGENTS.md + ${agent_count} stage role cards written"
    return 0
}
