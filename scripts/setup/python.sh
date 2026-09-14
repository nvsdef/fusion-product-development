#!/usr/bin/env bash
# Run Python helpers with dependencies supplied by uv.
#
# Default mode supplies PyYAML for setup-time YAML readers:
#   scripts/setup/python.sh scripts/setup/cad_agent.py --shell
#   scripts/setup/python.sh scripts/setup/plugins.py mcp-servers
#
# Helpers that need more can pass a requirements file or a single package:
#   scripts/setup/python.sh --with-requirements <requirements.txt> script.py
#   scripts/setup/python.sh --with <package> script.py
#
# The stdlib-only setup scripts (verify_layout.py,
# patch_timeouts.py) do NOT need this wrapper — setup.sh calls them with plain
# python3.
#
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is required for Python dependencies." >&2
    echo "       Install it from https://docs.astral.sh/uv/getting-started/installation/ and re-run." >&2
    exit 1
fi

UV_RUN_ARGS=(--quiet --no-project)
case "${1:-}" in
    --with-requirements)
        [ "$#" -ge 3 ] || { echo "ERROR: --with-requirements needs a file and command." >&2; exit 2; }
        UV_RUN_ARGS+=(--with-requirements "$2")
        shift 2
        ;;
    --with)
        [ "$#" -ge 3 ] || { echo "ERROR: --with needs a package and command." >&2; exit 2; }
        UV_RUN_ARGS+=(--with "$2")
        shift 2
        ;;
    *)
        UV_RUN_ARGS+=(--with "PyYAML>=6.0")
        ;;
esac

exec uv run "${UV_RUN_ARGS[@]}" python "$@"
