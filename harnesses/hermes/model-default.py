#!/usr/bin/env python3
"""Pin Hermes's model.default to the configured inference model.

Runs inside the sandbox and rewrites the model section of the managed Hermes
config (/sandbox/.hermes/config.yaml — the HERMES_HOME this example uses),
keeping base_url pointed at the OpenShell gateway's inference.local route so
inference still flows through the managed provider.

argv: inference_model
"""
from pathlib import Path
import sys

import yaml

model = sys.argv[1]

path = Path("/sandbox/.hermes/config.yaml")
config = {}
if path.exists() and path.read_text().strip():
    config = yaml.safe_load(path.read_text()) or {}
config["model"] = {
    "default": model,
    "provider": "custom",
    "base_url": "https://inference.local/v1",
}
try:
    path.parent.mkdir(parents=True, exist_ok=True)
    original_mode = path.stat().st_mode if path.exists() else None
    if original_mode is not None:
        path.chmod(original_mode | 0o200)
    try:
        path.write_text(yaml.safe_dump(config, sort_keys=False))
    finally:
        if original_mode is not None:
            path.chmod(original_mode)
except PermissionError:
    print(
        "[WARN] Hermes config /sandbox/.hermes/config.yaml is not writable; "
        "model.default not pinned",
        file=sys.stderr,
    )
