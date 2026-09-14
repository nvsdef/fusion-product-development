# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Host-side job manager — non-blocking render dispatch for plug-in MCP
servers (fusion-mcp, future host GUI plug-ins).

Why this exists: the agent runtime's MCP request timeout is short, and both
sides of the Fusion socket are capped at FUSION_MCP_TIMEOUT (300 s). Real
photoreal renders run past that — and worse, `Rendering.startLocalRender`
returns a `RenderFuture` immediately while Autodesk queues renders to run
ONE AT A TIME, so a second submission can sit queued for minutes before it
starts. A blocking tool returns a timeout for those calls and leaves the
render running unobserved inside Fusion. The pattern that works is
fire-and-poll: submit via `start_render`, get a job id back immediately,
poll `get_render_status` on a heartbeat.

How this differs from the CAE example's version. There the manager owned
host SUBPROCESSES: it spawned them, held the Popen handle, and killed the
process group on timeout. Here it owns nothing. The render lives inside the
Fusion process, its id is minted by the add-in, and the only handle we have
is a string. So:

  * `spawn()` becomes `submit()` — it registers a job id that `start_render`
    already returned, it does not start anything;
  * liveness comes from a caller-supplied `status_fn` (wired to the
    `get_render_status` tool), not from `kill(pid, 0)`;
  * `cancel()` stops LOCAL tracking only. The bridge exposes no cancel tool,
    and a queued render cannot be pulled back out of Fusion's queue from
    outside it. The returned dict says so rather than pretending.

Persistence: every submit writes a small JSON sidecar under
`<state_dir>/<job_id>.json`, so a server restart no longer turns running
renders into 'unknown'. Reattached jobs are resolved on the next `status()`
call, because unlike a PID a Fusion job id cannot be probed locally. The
disk file is removed on reap.

Renders die with Fusion. The add-in's job registry is module-level state in
the Fusion process; if Fusion restarts, every id we hold is gone. That
surfaces as `lost`, not as a hang.
"""
from __future__ import annotations

import json
import os
import pathlib
import threading
import time

# The add-in writes here. It is the only log this manager can read: there is
# no per-job log file, because there is no per-job process.
ADDIN_LOG = os.environ.get(
    "FUSION_MCP_LOG", os.path.join(os.path.expanduser("~"), "fusion360mcp.log")
)

# Statuses the add-in reports for a render job. Anything outside this set is
# treated as unknown rather than silently mapped onto a terminal state.
_RUNNING_STATES = ("queued", "processing")
_DONE_STATES = ("finished",)
_FAILED_STATES = ("failed",)


def _read_log_tail(log_path: str | pathlib.Path, max_bytes: int = 4000) -> str:
    try:
        with open(log_path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - max_bytes))
            return f.read().decode("utf-8", errors="replace")
    except OSError:
        return ""


class JobManager:
    """Per-MCP-server render-job registry. Thread-safe.

    `state_dir` is a host-only directory holding one JSON sidecar per live
    job. Use `/tmp/<plugin>-jobs` or similar — DO NOT put it under
    $FUSION_OUTPUT_DIR, which is where deliverables go and what the user
    browses.

    `status_fn(job_id) -> dict` is the caller's binding to the bridge's
    `get_render_status` tool. It must return the add-in's reply as-is; this
    class does the interpreting. Raising is fine — a raise is read as "the
    bridge could not tell us", never as failure of the render itself.
    """

    # Sentinel states we own (the add-in only ever reports the states above).
    ST_TIMEOUT = "timeout"
    ST_CANCELLED = "cancelled"
    ST_LOST = "lost"        # Fusion restarted while we were down; id is gone

    def __init__(self, state_dir: str | pathlib.Path, status_fn=None):
        self._state_dir = pathlib.Path(state_dir)
        self._state_dir.mkdir(parents=True, exist_ok=True)
        self._status_fn = status_fn
        self._jobs: dict[str, dict] = {}
        self._lock = threading.Lock()
        self._reattach_existing()

    # ── Persistence ─────────────────────────────────────────────────────

    def _sidecar_path(self, job_id: str) -> pathlib.Path:
        return self._state_dir / f"{job_id}.json"

    def _persist(self, job_id: str, job: dict) -> None:
        meta = {
            "job_id": job_id,
            "output_path": job["output_path"],
            "submitted_at": job["submitted_at"],
            "timeout_s": job["timeout_s"],
            "params": job.get("params", {}),
        }
        try:
            self._sidecar_path(job_id).write_text(json.dumps(meta))
        except OSError:
            pass

    def _delete_sidecar(self, job_id: str) -> None:
        try:
            self._sidecar_path(job_id).unlink()
        except OSError:
            pass

    def _reattach_existing(self) -> None:
        """Called from __init__. Scan state_dir and re-register what we find.

        There is no local probe for a Fusion job id — the add-in owns that
        state — so nothing is resolved here. Every reattached job is marked
        `reattached` and left pending; the first `status()` call asks the
        bridge and either recovers it or reports `lost`.
        """
        for sidecar in self._state_dir.glob("*.json"):
            try:
                meta = json.loads(sidecar.read_text())
            except (OSError, json.JSONDecodeError):
                try: sidecar.unlink()
                except OSError: pass
                continue
            job_id = meta.get("job_id") or sidecar.stem
            self._jobs[job_id] = {
                "output_path": meta.get("output_path", ""),
                "submitted_at": meta.get("submitted_at", time.time()),
                "timeout_s": meta.get("timeout_s", 600),
                "params": meta.get("params", {}),
                "last_status": None,
                "final_status": None,
                "finished_at": None,
                "reattached": True,
            }

    # ── Public API ──────────────────────────────────────────────────────

    def submit(self, job_id: str, output_path: str,
               timeout_s: int = 600,
               params: dict | None = None) -> dict:
        """Register a job id that `start_render` has already returned.

        job_id:       the id minted by the add-in. We do not generate it —
                      the render exists in Fusion before we hear about it.
        output_path:  host path the render will be written to. Its PARENT
                      DIRECTORY MUST ALREADY EXIST: startLocalRender fails
                      quietly otherwise, and the symptom is a job that never
                      leaves 'queued' rather than an error.
        timeout_s:    give up on the next poll past this elapsed time. Queue
                      time counts: Autodesk runs renders one at a time, so a
                      second submission's clock starts while it waits.
        params:       whatever the caller wants echoed back on status
                      (resolution, quality, camera) — carried, never read.

        Always returns a dict — never raises.
        """
        if not job_id:
            return {"ok": False, "error": "start_render returned no job id"}

        out_dir = os.path.dirname(output_path)
        if out_dir and not os.path.isdir(out_dir):
            return {"ok": False,
                    "error": f"output directory does not exist: {out_dir} — "
                             "startLocalRender fails quietly without it"}

        job = {
            "output_path": output_path,
            "submitted_at": time.time(),
            "timeout_s": timeout_s,
            "params": dict(params or {}),
            "last_status": "queued",
            "final_status": None,
            "finished_at": None,
            "reattached": False,
        }
        with self._lock:
            self._jobs[job_id] = job
        self._persist(job_id, job)

        return {
            "ok": True,
            "job_id": job_id,
            "output_path": output_path,
            "submitted_at": job["submitted_at"],
            "status": "queued",
            "timeout_s": timeout_s,
        }

    def status(self, job_id: str, log_tail_bytes: int = 4000) -> dict:
        """Poll a job. Lazy-enforces the per-job timeout; reaps on completion.

        Returns:
            {ok, status: queued|processing|finished|failed|timeout|cancelled|
                         lost|unknown,
             elapsed_s, output_path, log_tail, addin_status (raw)}
        """
        with self._lock:
            job = self._jobs.get(job_id)
        if not job:
            return {"ok": False, "status": "unknown",
                    "error": f"unknown job_id: {job_id}"}

        elapsed = time.time() - job["submitted_at"]
        log_tail = _read_log_tail(ADDIN_LOG, log_tail_bytes)

        # Already terminal — answer from the registry, do not re-ask Fusion.
        if job["final_status"] is not None:
            return {"ok": job["final_status"] in _DONE_STATES,
                    "status": job["final_status"],
                    "elapsed_s": round(job["finished_at"] - job["submitted_at"], 1),
                    "output_path": job["output_path"],
                    "addin_status": job["last_status"], "log_tail": log_tail}

        if self._status_fn is None:
            return {"ok": False, "status": "unknown",
                    "error": "no status_fn bound — wire get_render_status",
                    "elapsed_s": round(elapsed, 1),
                    "output_path": job["output_path"], "log_tail": log_tail}

        try:
            reply = self._status_fn(job_id)
        except Exception as e:
            # The bridge could not tell us. That is NOT the render failing —
            # unless we were reattaching, in which case the id is gone with
            # the Fusion process that minted it.
            if job.get("reattached"):
                self._finish(job_id, job, self.ST_LOST)
                return {"ok": False, "status": self.ST_LOST,
                        "error": f"job id not known to Fusion after restart: {e}",
                        "elapsed_s": round(elapsed, 1),
                        "output_path": job["output_path"], "log_tail": log_tail}
            return {"ok": False, "status": "unknown",
                    "error": f"get_render_status unreachable: "
                             f"{type(e).__name__}: {e}",
                    "elapsed_s": round(elapsed, 1),
                    "output_path": job["output_path"], "log_tail": log_tail}

        with self._lock:
            job["reattached"] = False
        raw = (reply or {}).get("status") if isinstance(reply, dict) else None
        with self._lock:
            job["last_status"] = raw

        if raw in _DONE_STATES:
            self._finish(job_id, job, "finished")
            return {"ok": True, "status": "finished",
                    "elapsed_s": round(elapsed, 1),
                    "output_path": job["output_path"],
                    "addin_status": raw, "log_tail": log_tail}

        if raw in _FAILED_STATES:
            self._finish(job_id, job, "failed")
            return {"ok": False, "status": "failed",
                    "error": (reply.get("error") if isinstance(reply, dict)
                              else None) or "render failed",
                    "elapsed_s": round(elapsed, 1),
                    "output_path": job["output_path"],
                    "addin_status": raw, "log_tail": log_tail}

        if raw in _RUNNING_STATES:
            # Still queued or rendering — enforce our own timeout. We cannot
            # kill it: nothing outside Fusion can stop a running render. We
            # stop WATCHING, and say so, so the agent does not poll forever.
            if elapsed > job["timeout_s"]:
                self._finish(job_id, job, self.ST_TIMEOUT)
                return {"ok": False, "status": self.ST_TIMEOUT,
                        "error": f"timeout after {job['timeout_s']} s — stopped "
                                 "polling. The render may still be running "
                                 "inside Fusion; it cannot be cancelled from "
                                 "here and dies with the Fusion process.",
                        "elapsed_s": round(elapsed, 1),
                        "output_path": job["output_path"],
                        "addin_status": raw, "log_tail": log_tail}
            return {"ok": True, "status": raw,
                    "elapsed_s": round(elapsed, 1),
                    "output_path": job["output_path"],
                    "addin_status": raw, "log_tail": log_tail}

        # Unrecognised state — report it verbatim rather than guessing.
        return {"ok": False, "status": "unknown",
                "error": f"unrecognised add-in status: {raw!r}",
                "elapsed_s": round(elapsed, 1),
                "output_path": job["output_path"],
                "addin_status": raw, "log_tail": log_tail}

    def cancel(self, job_id: str) -> dict:
        """Stop tracking a job. Idempotent on already-finished jobs.

        Local only — see the module docstring. Fusion keeps rendering.
        """
        with self._lock:
            job = self._jobs.get(job_id)
        if not job:
            return {"ok": False, "status": "unknown",
                    "error": f"unknown job_id: {job_id}"}
        if job.get("finished_at") is not None:
            return {"ok": True, "status": "already_finished",
                    "final_status": job.get("final_status"),
                    "output_path": job["output_path"]}
        self._finish(job_id, job, self.ST_CANCELLED)
        return {"ok": True, "status": self.ST_CANCELLED,
                "output_path": job["output_path"],
                "note": "tracking stopped; Fusion was not asked to cancel — "
                        "the bridge exposes no cancel tool"}

    def list_jobs(self) -> list[dict]:
        """Snapshot of registered jobs. Cheap; useful for diagnostics."""
        out = []
        with self._lock:
            for jid, job in self._jobs.items():
                out.append({
                    "job_id": jid,
                    "submitted_at": job["submitted_at"],
                    "finished_at": job.get("finished_at"),
                    "status": job.get("final_status") or job.get("last_status"),
                    "output_path": job["output_path"],
                })
        return out

    # ── Internals ───────────────────────────────────────────────────────

    def _finish(self, job_id: str, job: dict, final_status: str) -> None:
        """Mark terminal once and drop the sidecar. Idempotent."""
        with self._lock:
            if job["finished_at"] is not None:
                return
            job["final_status"] = final_status
            job["finished_at"] = time.time()
        self._delete_sidecar(job_id)
