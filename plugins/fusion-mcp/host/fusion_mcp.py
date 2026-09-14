#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
"""Liveness probe for the Fusion360MCP add-in socket — NOT an MCP server.

The MCP server for this plug-in is the upstream fork
(faust-machines/fusion360-mcp-server), launched over stdio by the client and
by host/run.sh. This module re-implements none of it. It answers exactly one
question, before an agent is handed the session:

    Is Fusion's MAIN THREAD able to run API code right now?

Why `ping` is not that answer. The add-in's ping handler replies from the
socket thread and never enters `adsk.*`. Fusion's Scripts and Add-Ins dialog
is modal and holds the main thread, so with it left open `ping` returns
happily while every real tool call blocks until FUSION_MCP_TIMEOUT (300 s).
Only a command that must be marshalled onto the main thread through the
add-in's custom-event bridge tells the two states apart. `get_scene_info` is
the cheapest such command, so it is the only liveness check made here.

Three outcomes, three different fixes:
    socket refused  -> the add-in was never Run (or Fusion is not open)
    socket, no reply-> the modal dialog is open; the main thread is blocked
    reply           -> the bridge is live

Usage:
    python3 fusion_mcp.py --probe
    python3 fusion_mcp.py --probe --port 9876 --timeout 15

Exit status: 0 when the main thread answered, 1 otherwise.

Env:
    FUSION_MCP_PORT   add-in socket port (default: 9876)
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys

HOST = "127.0.0.1"          # host-local by construction; see policy.yaml
PORT = int(os.environ.get("FUSION_MCP_PORT", "9876"))

# Deliberately NOT FUSION_MCP_TIMEOUT (300 s). That budget exists for real
# work — create_drawing measured 47.2 s. A liveness check that waits five
# minutes is not a liveness check: a responsive main thread answers
# get_scene_info well inside a second, and anything slower is a finding.
PROBE_TIMEOUT_S = 15.0

# TODO(verify): confirm the request envelope against the fork's add-in socket
# server. This mirrors the {"type", "params"} shape used by the add-in
# bridges this server descends from. If the fork keys the command as
# "command" instead, change this constant and nothing else.
_COMMAND_KEY = "type"


def _send(command: str, params: dict | None = None,
          host: str = HOST, port: int = PORT,
          timeout: float = PROBE_TIMEOUT_S) -> dict:
    """One request/response round-trip on a fresh socket.

    Fresh per call on purpose: the add-in serves one connection at a time,
    and a half-open socket left behind by a timed-out call is the quickest
    way to wedge it for everyone else.
    """
    payload = json.dumps({_COMMAND_KEY: command, "params": params or {}}) + "\n"
    chunks: list[bytes] = []
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload.encode("utf-8"))
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
            try:
                # The add-in may write the reply in several frames; parse
                # optimistically and keep reading while it is incomplete.
                return json.loads(b"".join(chunks).decode("utf-8"))
            except ValueError:
                continue
    raw = b"".join(chunks).decode("utf-8", errors="replace")
    raise RuntimeError(
        f"add-in closed the connection without a complete JSON reply: {raw[:200]!r}"
    )


def probe(host: str = HOST, port: int = PORT,
          timeout: float = PROBE_TIMEOUT_S) -> dict:
    """Ask the main thread for get_scene_info.

    Returns {ok, stage, detail, reply} where `stage` is one of:
        "closed"      nothing listening on the socket
        "blocked"     socket answered, main thread did not
        "live"        main thread answered
    Never raises — the caller is usually a shell script.
    """
    try:
        reply = _send("get_scene_info", host=host, port=port, timeout=timeout)
    except socket.timeout:
        return {"ok": False, "stage": "blocked", "reply": None, "detail": (
            f"connected to {host}:{port} but get_scene_info did not answer in "
            f"{timeout:g}s. Fusion's main thread is blocked — almost always the "
            "modal Scripts and Add-Ins dialog left open. Close it. (A long "
            "modelling operation or an open Fusion dialog does the same thing.) "
            "Note that 'ping' would have answered: it never enters the API.")}
    except ConnectionRefusedError:
        return {"ok": False, "stage": "closed", "reply": None, "detail": (
            f"nothing listening on {host}:{port}. Open Fusion, then "
            "UTILITIES > Scripts and Add-Ins > Add-Ins > Fusion360MCP > Run "
            "(and CLOSE the dialog afterwards).")}
    except OSError as e:
        return {"ok": False, "stage": "closed", "reply": None,
                "detail": f"socket error reaching {host}:{port}: "
                          f"{type(e).__name__}: {e}"}
    except RuntimeError as e:
        return {"ok": False, "stage": "blocked", "reply": None, "detail": str(e)}

    # A reply is not automatically a healthy reply — the add-in reports its
    # own errors in-band. Treat an explicit failure flag as not-live.
    if isinstance(reply, dict) and reply.get("success") is False:
        return {"ok": False, "stage": "blocked", "reply": reply,
                "detail": f"add-in returned an error: "
                          f"{reply.get('error') or reply}"}
    return {"ok": True, "stage": "live", "reply": reply,
            "detail": "main thread answered get_scene_info"}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--probe", action="store_true",
                    help="check that Fusion's main thread is responsive")
    ap.add_argument("--host", default=HOST)
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--timeout", type=float, default=PROBE_TIMEOUT_S)
    args = ap.parse_args(argv)
    if not args.probe:
        ap.print_help()
        return 2

    result = probe(args.host, args.port, args.timeout)
    marker = "[OK]" if result["ok"] else "[FAIL]"
    print(f"{marker} fusion-mcp addin {args.host}:{args.port} "
          f"({result['stage']}): {result['detail']}",
          file=sys.stdout if result["ok"] else sys.stderr)
    if result["ok"] and result["reply"] is not None:
        print(f"      {json.dumps(result['reply'])[:400]}")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
