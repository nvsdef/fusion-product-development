#!/usr/bin/env python3
"""Pin a sandbox's provider/model in ~/.nemoclaw/sandboxes.json.

Without this, `nemoclaw connect` rewrites the gateway-side inference route on
each connect, undoing `openshell inference set --system`. Runs on the host.

argv: sandbox_name  provider  model  registry_path
"""
import json
import sys

name, provider, model, path = sys.argv[1:5]

with open(path) as fh:
    c = json.load(fh)

sb = c.get("sandboxes", {}).get(name)
if not sb:
    sys.exit(0)

if sb.get("provider") == provider and sb.get("model") == model:
    print(f"[OK] nemoclaw registry already points at {provider}/{model}")
    sys.exit(0)

sb["provider"] = provider
sb["model"] = model
with open(path, "w") as fh:
    fh.write(json.dumps(c, indent=4) + "\n")
print(f"[OK] nemoclaw registry → {provider}/{model} (prevents `nemoclaw connect` reversion)")
