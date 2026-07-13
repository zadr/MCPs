#!/usr/bin/env python3
"""
process-watch-tool: a tiny MCP server that reports on long-running subprocess
trees and helps unstick them.

Designed to monitor apple-tools-mcp (or any other MCP) by name. Stdlib only.

Tools:
- check: snapshot of matching MCP processes, their descendants, lock-file
  holders, and any "stalled" processes (state S, ~0% CPU, elapsed > threshold).
- sample_pid: top stack frames of a process via `sample(1)`.
- kill_pgroup: SIGTERM (and optional SIGKILL escalation) a process group by
  its pgid. Useful for unsticking wedges from within a Claude session.

Run directly:
    python3 server.py

Add to .mcp.json:
    {
      "mcpServers": {
        "process-watch": {
          "command": "python3",
          "args": ["/path/to/mcps/process-watch-tool/server.py"]
        }
      }
    }
"""

from __future__ import annotations

import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from typing import Any

SERVER_NAME = "process-watch"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"

# --- helpers ---------------------------------------------------------------


def log(msg: str) -> None:
    """stderr-only; stdout is reserved for JSON-RPC."""
    print(f"[process-watch] {msg}", file=sys.stderr, flush=True)


def run_cmd(args: list[str], timeout: float = 5.0) -> tuple[int, str, str]:
    """Run a command, return (rc, stdout, stderr). Never raises."""
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", f"timed out after {timeout}s"
    except FileNotFoundError as e:
        return -1, "", f"command not found: {e}"
    except Exception as e:
        return -1, "", f"error: {e}"


def parse_etime_to_seconds(etime: str) -> int:
    """Parse ps etime ([[dd-]hh:]mm:ss) into seconds."""
    etime = etime.strip()
    days = 0
    if "-" in etime:
        d, rest = etime.split("-", 1)
        days = int(d)
        etime = rest
    parts = etime.split(":")
    parts = [int(p) for p in parts]
    if len(parts) == 3:
        h, m, s = parts
    elif len(parts) == 2:
        h = 0
        m, s = parts
    else:
        return 0
    return days * 86400 + h * 3600 + m * 60 + s


def list_processes_matching(pattern: str) -> list[int]:
    """Return PIDs whose command line matches the pattern (substring)."""
    rc, out, _ = run_cmd(["pgrep", "-f", pattern])
    if rc != 0:
        return []
    return [int(line) for line in out.strip().split("\n") if line.strip().isdigit()]


def proc_info(pid: int) -> dict[str, Any] | None:
    """Return ps info for a pid: ppid, pgid, etime_seconds, stat, pcpu, command."""
    rc, out, _ = run_cmd(
        [
            "ps",
            "-o",
            "ppid=,pgid=,etime=,stat=,pcpu=,command=",
            "-p",
            str(pid),
        ]
    )
    if rc != 0 or not out.strip():
        return None
    line = out.strip()
    # Split into at most 6 fields (command may contain spaces).
    parts = line.split(None, 5)
    if len(parts) < 6:
        return None
    ppid, pgid, etime, stat, pcpu, command = parts
    return {
        "pid": pid,
        "ppid": int(ppid),
        "pgid": int(pgid),
        "etime_seconds": parse_etime_to_seconds(etime),
        "etime": etime,
        "stat": stat,
        "pcpu": float(pcpu),
        "command": command,
    }


def list_descendants(root_pid: int) -> list[int]:
    """Return descendant PIDs (transitive children) of root_pid using pgrep -P."""
    visited: set[int] = set()
    to_visit = [root_pid]
    descendants: list[int] = []
    while to_visit:
        parent = to_visit.pop()
        if parent in visited:
            continue
        visited.add(parent)
        rc, out, _ = run_cmd(["pgrep", "-P", str(parent)])
        if rc != 0:
            continue
        for line in out.strip().split("\n"):
            line = line.strip()
            if line.isdigit():
                cpid = int(line)
                if cpid not in visited:
                    descendants.append(cpid)
                    to_visit.append(cpid)
    return descendants


def lock_holders(lock_path: str) -> list[dict[str, Any]]:
    """Return lsof rows for the given lock file: [{pid, command, fd}]."""
    rc, out, _ = run_cmd(["lsof", "-Fpcft", lock_path])
    if rc != 0:
        return []
    holders: list[dict[str, Any]] = []
    cur: dict[str, Any] = {}
    for line in out.splitlines():
        if not line:
            continue
        kind, val = line[0], line[1:]
        if kind == "p":
            if cur:
                holders.append(cur)
            cur = {"pid": int(val)}
        elif kind == "c":
            cur["command"] = val
        elif kind == "f":
            cur["fd"] = val
        elif kind == "t":
            cur["type"] = val
    if cur:
        holders.append(cur)
    return holders


def is_stalled(info: dict[str, Any], min_elapsed: int) -> bool:
    """Stalled = state S (sleeping), ~0% CPU, alive longer than threshold."""
    return (
        info["stat"].startswith("S")
        and info["pcpu"] < 0.1
        and info["etime_seconds"] >= min_elapsed
    )


# --- event log derivation -------------------------------------------------


def read_log_lines(log_path: str) -> list[dict[str, Any]]:
    """Read every line of the JSONL log, return parsed records (skip junk)."""
    if not os.path.exists(log_path):
        return []
    out: list[dict[str, Any]] = []
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError:
        pass
    return out


def pid_is_alive(pid: int) -> bool:
    """True if a process with this pid currently exists."""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we can't signal it. Still counts as alive.
        return True


def derive_inflight_calls(log_path: str) -> dict[int, dict[str, Any]]:
    """Walk the event log. Return {child_pid: shell_start_record} for any
    shell_start whose owning MCP is still alive and whose call has no
    matching shell_exit/shell_timeout.

    Events whose owning MCP pid is dead are ignored: the call died with
    its server, so they're not actionable (whether or not the child
    process itself is still around).
    """
    events = read_log_lines(log_path)
    starts: dict[int, dict[str, Any]] = {}
    for ev in events:
        kind = ev.get("event")
        if kind == "shell_start":
            cpid = ev.get("child_pid")
            if isinstance(cpid, int):
                starts[cpid] = ev
        elif kind in ("shell_exit", "shell_timeout"):
            cpid = ev.get("child_pid")
            if isinstance(cpid, int) and cpid in starts:
                del starts[cpid]
    # Drop entries whose owning MCP is no longer alive.
    return {
        cpid: ev
        for cpid, ev in starts.items()
        if pid_is_alive(int(ev.get("pid", 0)))
    }


def derive_signal(pattern: str, log_path: str, stall_threshold: int) -> dict[str, Any]:
    """Return actionable signal. Empty (ok=True) means nothing to report.

    Detects:
      - Stalled in-flight calls: shell_start logged, child still alive and
        idle past stall_threshold (or past its own timeout, whichever is less).
      - Self-unhealthy MCP: server process in state R with no descendants
        and high CPU (likely internal spin) for sustained time. This is the
        failure mode where the MCP server itself is broken but no subprocess
        wedge exists to detect.
    """
    inflight = derive_inflight_calls(log_path)
    stalls: list[dict[str, Any]] = []
    unhealthy_mcps: list[dict[str, Any]] = []
    now = time.time()

    for child_pid, ev in inflight.items():
        info = proc_info(child_pid)
        start_ts = float(ev.get("ts", 0))
        elapsed = int(now - start_ts) if start_ts else 0
        timeout_seconds = ev.get("timeout_seconds")
        effective_threshold = stall_threshold
        if isinstance(timeout_seconds, (int, float)) and timeout_seconds > 0:
            effective_threshold = min(stall_threshold, int(timeout_seconds))

        if info is None:
            # Child vanished from ps. Could mean: (a) it exited normally and
            # we just haven't read shell_exit from disk yet, (b) it crashed,
            # (c) it was killed. None of these are actionable from outside
            # — only the MCP itself can disambiguate. Skip.
            continue

        if elapsed >= effective_threshold and is_stalled(info, effective_threshold):
            stalls.append({
                "child_pid": child_pid,
                "executable": ev.get("executable"),
                "started_at": start_ts,
                "elapsed_since_start": elapsed,
                "mcp_pid": ev.get("pid"),
                "child_pgid": info.get("pgid"),
                "child_stat": info["stat"],
                "child_pcpu": info["pcpu"],
                "timeout_seconds": timeout_seconds,
                "effective_threshold_seconds": effective_threshold,
            })

    # MCP self-health: high CPU with no children and no in-flight calls is
    # the "server spinning internally" failure mode.
    mcp_pids = list_processes_matching(pattern)
    for mcp_pid in mcp_pids:
        info = proc_info(mcp_pid)
        if info is None:
            continue
        # Skip MCPs that have in-flight work — their CPU can legitimately
        # be high while running tools.
        has_inflight = any(ev.get("pid") == mcp_pid for ev in inflight.values())
        if has_inflight:
            continue
        descendants = list_descendants(mcp_pid)
        if descendants:
            continue
        # No work, no children. High CPU sustained = bug.
        # Threshold: 25% CPU for a server with no work is unambiguous.
        # 60s alive minimum so we don't false-positive on startup.
        if info["pcpu"] >= 25.0 and info["etime_seconds"] >= 60:
            unhealthy_mcps.append({
                "mcp_pid": mcp_pid,
                "etime": info["etime"],
                "etime_seconds": info["etime_seconds"],
                "stat": info["stat"],
                "pcpu": info["pcpu"],
                "reason": "high CPU with no descendants and no in-flight tool calls",
            })

    ok = not stalls and not unhealthy_mcps
    return {
        "ok": ok,
        "pattern": pattern,
        "log_path": log_path,
        "log_exists": os.path.exists(log_path),
        "inflight_count": len(inflight),
        "stalls": stalls,
        "unhealthy_mcps": unhealthy_mcps,
        "checked_at": int(now),
    }


# --- tool implementations --------------------------------------------------


def tool_check(args: dict[str, Any]) -> dict[str, Any]:
    """Report only actionable signal: stalled in-flight calls, lost children,
    rapid server respawn. Empty {ok: true} when there's nothing to act on.
    Cross-references /tmp/apple-tools-mcp.jsonl with live ps state.
    """
    pattern = args.get("pattern", "apple-tools-mcp")
    log_path = args.get("logPath", "/tmp/apple-tools-mcp.jsonl")
    stall_threshold = int(args.get("stallThresholdSeconds", 60))
    return derive_signal(pattern, log_path, stall_threshold)


def tool_poll(args: dict[str, Any]) -> dict[str, Any]:
    """Sleep/check loop. Returns as soon as derive_signal reports anything
    actionable OR after `iterations` cycles. Does NOT truncate the log —
    derive_inflight_calls already filters out events whose owning MCP is
    dead, so stale entries don't cause false positives, and keeping the
    log around lets the next poll see in-flight calls that started before
    this poll was invoked.
    """
    pattern = args.get("pattern", "apple-tools-mcp")
    log_path = args.get("logPath", "/tmp/apple-tools-mcp.jsonl")
    interval = float(args.get("intervalSeconds", 30.0))
    iterations = int(args.get("iterations", 20))
    stall_threshold = int(args.get("stallThresholdSeconds", 60))
    return_on_signal = bool(args.get("returnOnStall", True))

    started = time.time()
    for i in range(iterations):
        signal = derive_signal(pattern, log_path, stall_threshold)
        if not signal["ok"] and return_on_signal:
            signal["iterations_run"] = i + 1
            signal["elapsed_seconds"] = int(time.time() - started)
            signal["returned_early"] = True
            return signal
        if i < iterations - 1:
            time.sleep(interval)

    final = derive_signal(pattern, log_path, stall_threshold)
    final["iterations_run"] = iterations
    final["elapsed_seconds"] = int(time.time() - started)
    final["returned_early"] = False
    return final


def tool_read_log(args: dict[str, Any]) -> dict[str, Any]:
    """Read JSONL events from apple-tools-mcp's event log.

    Events: server_started, server_shutdown, shell_start, shell_exit,
    shell_timeout. Each line has ts, event, pid plus event-specific fields.
    """
    path = args.get("path", "/tmp/apple-tools-mcp.jsonl")
    since_ts = args.get("sinceTs")  # epoch seconds; include events with ts >= sinceTs
    pid_filter = args.get("pid")
    event_filter = args.get("event")
    limit = int(args.get("limit", 200))
    tail = bool(args.get("tail", True))  # if true, return last `limit` matching

    if not os.path.exists(path):
        return {"path": path, "exists": False, "events": []}

    events: list[dict[str, Any]] = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if since_ts is not None and rec.get("ts", 0) < since_ts:
                    continue
                if pid_filter is not None and rec.get("pid") != pid_filter:
                    continue
                if event_filter is not None and rec.get("event") != event_filter:
                    continue
                events.append(rec)
    except OSError as e:
        return {"path": path, "exists": True, "error": str(e), "events": []}

    if tail and len(events) > limit:
        events = events[-limit:]
    elif not tail and len(events) > limit:
        events = events[:limit]

    return {
        "path": path,
        "exists": True,
        "event_count": len(events),
        "events": events,
    }


def tool_sample_pid(args: dict[str, Any]) -> dict[str, Any]:
    """Use sample(1) to get top stack frames of a pid."""
    pid = args.get("pid")
    if not isinstance(pid, int):
        raise ValueError("pid (integer) is required")
    duration = int(args.get("durationSeconds", 1))
    rc, out, err = run_cmd(["sample", str(pid), str(duration)], timeout=duration + 10)
    if rc != 0:
        return {"pid": pid, "error": err.strip() or "sample failed"}
    # Extract "Call graph" section (first thread block).
    lines = out.splitlines()
    call_graph_lines: list[str] = []
    in_graph = False
    for line in lines:
        if line.startswith("Call graph:"):
            in_graph = True
            call_graph_lines.append(line)
            continue
        if in_graph:
            if line.startswith("Total number in stack"):
                break
            call_graph_lines.append(line)
            if len(call_graph_lines) > 80:
                break
    return {
        "pid": pid,
        "call_graph": "\n".join(call_graph_lines) or out[:4000],
    }


def tool_kill_pgroup(args: dict[str, Any]) -> dict[str, Any]:
    """SIGTERM a process group, optionally escalating to SIGKILL after grace."""
    pgid = args.get("pgid")
    if not isinstance(pgid, int) or pgid <= 0:
        raise ValueError("pgid (positive integer) is required")
    grace = float(args.get("graceSeconds", 2.0))
    escalate = bool(args.get("escalate", True))

    sent_term = False
    try:
        os.kill(-pgid, signal.SIGTERM)
        sent_term = True
    except ProcessLookupError:
        return {"pgid": pgid, "result": "no such process group"}
    except PermissionError:
        return {"pgid": pgid, "result": "permission denied"}

    if grace > 0:
        time.sleep(grace)

    # Check if any member is still alive (we treat pgid as a pid here; in
    # practice -pgid is the leader's pid).
    still_alive = []
    rc, out, _ = run_cmd(["pgrep", "-g", str(pgid)])
    if rc == 0:
        still_alive = [int(p) for p in out.split() if p.isdigit()]

    if still_alive and escalate:
        try:
            os.kill(-pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    return {
        "pgid": pgid,
        "sent_sigterm": sent_term,
        "still_alive_after_grace": still_alive,
        "sent_sigkill": bool(still_alive and escalate),
    }


# --- MCP JSON-RPC plumbing -------------------------------------------------


TOOLS = [
    {
        "name": "check",
        "description": (
            "Report actionable signal only. Cross-references the apple-tools-mcp "
            "event log (/tmp/apple-tools-mcp.jsonl) with live ps state. Returns "
            "{ok: true, stalls: [], unhealthy_mcps: []} when nothing is wrong. "
            "Non-empty `stalls` means a shell_start was logged, the child is "
            "currently alive in state S with ~0%% CPU, past the stall threshold. "
            "Non-empty `unhealthy_mcps` means an MCP server process is burning "
            ">25%% CPU with no descendants and no in-flight tool calls (the "
            "'server spinning internally' failure mode)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Substring to match in MCP command line. Default: 'apple-tools-mcp'."},
                "logPath": {"type": "string", "description": "Path to MCP event log. Default: /tmp/apple-tools-mcp.jsonl."},
                "stallThresholdSeconds": {"type": "integer", "description": "Min seconds since shell_start before a child idle in state S counts as stalled. Default: 60."},
            },
        },
    },
    {
        "name": "poll",
        "description": (
            "Sleep/check loop. Returns as soon as `check` reports anything "
            "actionable (set returnOnStall=false to always run all iterations). "
            "Use this to monitor in the background while the user does other "
            "work; the call blocks until something interesting happens or the "
            "iteration limit is hit."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Substring to match in MCP command line. Default: 'apple-tools-mcp'."},
                "logPath": {"type": "string", "description": "Path to MCP event log. Default: /tmp/apple-tools-mcp.jsonl."},
                "intervalSeconds": {"type": "number", "description": "Seconds between checks. Default: 30."},
                "iterations": {"type": "integer", "description": "Max check cycles. Default: 20."},
                "stallThresholdSeconds": {"type": "integer", "description": "Min seconds since shell_start before idle counts as stalled. Default: 60."},
                "returnOnStall": {"type": "boolean", "description": "If true (default), return as soon as `check` finds something. If false, run all iterations."},
            },
        },
    },
    {
        "name": "read_log",
        "description": (
            "Read the apple-tools-mcp event log (/tmp/apple-tools-mcp.jsonl by "
            "default). Events: server_started, server_shutdown, shell_start, "
            "shell_exit, shell_timeout. Use this to correlate ps state with "
            "what the MCP thinks it's doing: which call started a child, when, "
            "with what timeout, and whether it returned."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Log file path. Default: /tmp/apple-tools-mcp.jsonl."},
                "sinceTs": {"type": "number", "description": "Only return events with ts >= this (epoch seconds)."},
                "pid": {"type": "integer", "description": "Only return events from this MCP pid."},
                "event": {"type": "string", "description": "Only return events of this type."},
                "limit": {"type": "integer", "description": "Max events to return. Default: 200."},
                "tail": {"type": "boolean", "description": "If true (default), return the LAST `limit` matching events; if false, the first."},
            },
        },
    },
    {
        "name": "sample_pid",
        "description": (
            "Capture top stack frames of a process via macOS `sample(1)`. "
            "Use when `check` reports a stalled process and you want to know "
            "where it's blocked."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "pid": {"type": "integer", "description": "PID to sample."},
                "durationSeconds": {
                    "type": "integer",
                    "description": "How long to sample. Default: 1.",
                },
            },
            "required": ["pid"],
        },
    },
    {
        "name": "kill_pgroup",
        "description": (
            "SIGTERM a process group (kill(-pgid, SIGTERM)), wait `graceSeconds`, "
            "then SIGKILL anything still alive (if escalate). Use when a stalled "
            "subprocess tree needs to be reaped from inside the conversation."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "pgid": {"type": "integer", "description": "Process group ID (typically the leader's PID)."},
                "graceSeconds": {"type": "number", "description": "Seconds to wait between SIGTERM and SIGKILL. Default: 2."},
                "escalate": {"type": "boolean", "description": "If true, send SIGKILL after grace. Default: true."},
            },
            "required": ["pgid"],
        },
    },
]


def jsonrpc_response(req_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def jsonrpc_error(req_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def handle_request(req: dict[str, Any]) -> dict[str, Any] | None:
    method = req.get("method")
    req_id = req.get("id")
    params = req.get("params") or {}

    # Notifications (no id) require no response.
    is_notification = "id" not in req

    if method == "initialize":
        return jsonrpc_response(req_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })

    if method == "notifications/initialized":
        return None

    if method == "tools/list":
        return jsonrpc_response(req_id, {"tools": TOOLS})

    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") or {}
        try:
            if name == "check":
                result = tool_check(arguments)
            elif name == "poll":
                result = tool_poll(arguments)
            elif name == "read_log":
                result = tool_read_log(arguments)
            elif name == "sample_pid":
                result = tool_sample_pid(arguments)
            elif name == "kill_pgroup":
                result = tool_kill_pgroup(arguments)
            else:
                return jsonrpc_error(req_id, -32601, f"Unknown tool: {name}")
        except ValueError as e:
            return jsonrpc_error(req_id, -32602, str(e))
        except Exception as e:
            log(f"tool {name} failed: {e}")
            return jsonrpc_error(req_id, -32603, f"Tool error: {e}")
        return jsonrpc_response(req_id, {
            "content": [{"type": "text", "text": json.dumps(result, indent=2)}],
        })

    if is_notification:
        return None
    return jsonrpc_error(req_id, -32601, f"Unknown method: {method}")


def main() -> None:
    log(f"{SERVER_NAME} {SERVER_VERSION} starting")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            log(f"invalid JSON: {e}")
            continue
        try:
            resp = handle_request(req)
        except Exception as e:
            log(f"handler crashed: {e}")
            resp = jsonrpc_error(req.get("id"), -32603, f"Internal error: {e}")
        if resp is not None:
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
