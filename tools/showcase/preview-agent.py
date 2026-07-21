#!/usr/bin/env python3
"""
preview-agent.py - persistent preview manager for the standalone showcase.

Keeps the local showcase preview usable during unattended development:
- verifies/restarts the standalone showcase server
- refreshes the file-bridged chat-agent heartbeat
- publishes a deduped custom card to the showcase
- emits best-effort IPC frames for the UPM/showcase surface

Stdlib-only so launchd can run it without a virtualenv.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
STATE = Path.home() / ".ccem" / "state"
LOGS = Path.home() / ".ccem" / "logs"
IPC = Path.home() / ".ccem" / "bin" / "ccem-ipc.sh"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def project_slug(project: str) -> str:
    import re

    return re.sub(r"[^a-z0-9]+", "-", project.lower()).strip("-") or "project"


def get_json(url: str, timeout: float = 2.0) -> tuple[bool, dict[str, Any]]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            data = json.loads(raw) if raw.strip() else {}
            return 200 <= resp.status < 300, data
    except Exception as exc:
        return False, {"error": str(exc)}


def post_json(url: str, payload: dict[str, Any], timeout: float = 2.0) -> tuple[bool, str]:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return 200 <= resp.status < 300, raw[:300]
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        return False, f"HTTP {exc.code}: {raw[:240]}"
    except Exception as exc:
        return False, str(exc)[:300]


def emit_ipc(kind: str, payload: dict[str, Any]) -> None:
    if not IPC.exists():
        return
    try:
        subprocess.Popen(
            ["bash", str(IPC), kind, json.dumps(payload, separators=(",", ":"))],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def ensure_showcase(args: argparse.Namespace) -> tuple[bool, str]:
    ok, data = get_json(f"http://127.0.0.1:{args.port}/api/health")
    if ok and data.get("ok"):
        return True, "online"

    cmd = [
        str(HERE / "serve.sh"),
        "--port",
        str(args.port),
        "--root",
        str(args.root),
        "--project",
        args.project,
        "--bind",
        args.bind,
    ]
    if args.sources:
        cmd.extend(["--sources", args.sources])

    try:
        proc = subprocess.run(
            cmd,
            cwd=args.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
        )
    except Exception as exc:
        return False, f"restart failed: {exc}"

    ok, data = get_json(f"http://127.0.0.1:{args.port}/api/health")
    if ok and data.get("ok"):
        return True, "restarted"

    detail = (proc.stderr or proc.stdout or "health check still failed").strip()
    return False, detail[:220]


def beat_chat_agent(args: argparse.Namespace) -> bool:
    env = os.environ.copy()
    env["SHOWCASE_PROJECT"] = args.project
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(HERE / "chat-agent.py"),
                "beat",
                args.agent_id,
                args.session,
            ],
            cwd=args.root,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=4,
        )
        return proc.returncode == 0
    except Exception:
        return False


def write_status(args: argparse.Namespace, healthy: bool, detail: str) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    status_file = STATE / f"{project_slug(args.project)}-preview-agent.json"
    status_file.write_text(
        json.dumps(
            {
                "ts": now_iso(),
                "project": args.project,
                "port": args.port,
                "agent_id": args.agent_id,
                "session": args.session,
                "healthy": healthy,
                "detail": detail,
                "pid": os.getpid(),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def post_preview_card(args: argparse.Namespace, healthy: bool, detail: str) -> bool:
    card = {
        "id": "preview-bridge",
        "kind": "metric",
        "accent": "green" if healthy else "rust",
        "title": "Preview Build Bridge",
        "subtitle": f"http://127.0.0.1:{args.port} · {args.project}",
        "metrics": [
            {"label": "showcase", "value": "online" if healthy else "repairing"},
            {"label": "heartbeat", "value": "active"},
            {"label": "manager", "value": args.agent_id},
        ],
        "meta": f"{now_iso()} · {detail}",
        "info": "Persistent launchd-backed bridge for live preview, chat presence, IPC, and UPM/showcase progress.",
    }
    ok, _ = post_json(f"http://127.0.0.1:{args.port}/api/cards", card)
    return ok


def tick(args: argparse.Namespace, force_card: bool = False) -> bool:
    healthy, detail = ensure_showcase(args)
    heartbeat = beat_chat_agent(args)
    detail = detail if heartbeat else f"{detail}; chat heartbeat failed"
    write_status(args, healthy, detail)

    payload = {
        "project": args.project,
        "session": args.session,
        "agent_id": args.agent_id,
        "port": args.port,
        "healthy": healthy,
        "detail": detail,
    }
    emit_ipc(f"{project_slug(args.project)}.preview.tick", payload)

    should_card = force_card or (int(time.time()) % max(args.card_interval, 1) < args.interval)
    if should_card:
        post_preview_card(args, healthy, detail)
    return healthy


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Persistent preview bridge for SFA showcase.")
    parser.add_argument("--project", default=os.environ.get("SHOWCASE_PROJECT", "sfa-macos"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("SHOWCASE_PORT", "4511")))
    parser.add_argument("--bind", default=os.environ.get("SHOWCASE_BIND", "127.0.0.1"))
    parser.add_argument("--root", default=os.environ.get("SHOWCASE_ROOT", str(ROOT)))
    parser.add_argument("--sources", default=os.environ.get("SHOWCASE_SOURCES", ""))
    parser.add_argument("--session", default=os.environ.get("SFA_PREVIEW_SESSION", "codex-sfa-live-development"))
    parser.add_argument("--agent-id", default=os.environ.get("SFA_PREVIEW_AGENT_ID", "sfa-preview-bridge"))
    parser.add_argument("--interval", type=int, default=int(os.environ.get("SFA_PREVIEW_INTERVAL", "15")))
    parser.add_argument("--card-interval", type=int, default=int(os.environ.get("SFA_PREVIEW_CARD_INTERVAL", "60")))
    parser.add_argument("--once", action="store_true", help="Run one health/heartbeat/card tick and exit.")
    args = parser.parse_args()
    args.root = str(Path(args.root).expanduser().resolve())
    return args


def main() -> int:
    args = parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)

    if args.once:
        ok = tick(args, force_card=True)
        print(json.dumps({"ok": ok, "project": args.project, "port": args.port, "ts": now_iso()}))
        return 0 if ok else 1

    while True:
        tick(args)
        time.sleep(max(args.interval, 5))


if __name__ == "__main__":
    raise SystemExit(main())
