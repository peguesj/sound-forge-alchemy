#!/usr/bin/env python3
"""
Standalone GIMME-style IPC progress showcase — project-agnostic engine.

One file. One command. Serves a live status board for any project:
handoff state, /upm progress, /apm posting, the IPC event stream, and a
claude-mem timeline — rendered as dynamic AG-UI cards over SSE, plus an
IPC chat that talks to a background agent through a file-based inbox/outbox.

This is the engine behind `/showcase --standalone --ipc`. It is invoked by
tools/showcase/bootstrap.sh (project-pinned) and by the showcase skill's
engines/standalone-ipc launcher (portable).

Data sources (all read-only except the chat inbox), auto-discovered from --root:
  docs/HANDOFF*.md (newest)          handoff status (TL;DR, commits, blocker)
  prd.json                           /upm story progress (passes=true)
  ~/.ccem/logs/ipc-fallback.ndjson   IPC event stream (upm.* / apm.* emits)
  http://localhost:3032/api/*        CCEM APM health, formations, agents
  .remember/*.md + memory/MEMORY.md  claude-mem recent timeline
  ~/.ccem/state/<project>-chat-*     chat bridge to the background agent
  ~/.ccem/state/<slug>-cards.ndjson   agent-authored custom AG-UI cards (POST /api/cards)

Usage:
  python3 showcase-serve.py --port 4510 --root . --project vyynl
  python3 showcase-serve.py --port 4520 --root /path/to/other-repo

AG-UI event envelope (SSE `data:` lines on /api/events):
  {"type":"RUN_STARTED","runId":..,"threadId":..}
  {"type":"STATE_SNAPSHOT","snapshot":{..}}
  {"type":"CUSTOM","name":"card","value":{card}}
  {"type":"CUSTOM","name":"ipc_event","value":{event}}
  {"type":"CUSTOM","name":"card","value":{custom card}}   (from <slug>-cards.ndjson)
  {"type":"TEXT_MESSAGE_START|CONTENT|END",...}   (agent chat replies)

Custom cards & card kinds:
  Supported card kinds: status, progress, metric, feed, list, alert,
  diagram (raw inline SVG), lottie (lottie-web player). Plus synthesized
  server sources: decisions (IPC requests/decisions feed), upmcard
  (phase-derived /upm fallback when prd.json is absent), sdk (Claude Agent
  SDK topology/metrics). Agents push their own cards two ways, both of which
  append one JSON object per line to ~/.ccem/state/<slug>-cards.ndjson:
    - POST /api/cards  with body {"id":..,"kind":..,...}  (requires id)
    - chat-agent.py card '<json>'  helper command
  The "custom" source reads that file and emits each line as a card.

Modular card UI:
  Cards are interactive in the browser — drag-resize (size persisted to
  localStorage), right-click context menu (reset size / collapse / copy
  JSON / pin), an info-badge tooltip per card, and a Splunk-style filter
  bar over the grid (free-text search + per-kind facet chips).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# ----------------------------------------------------------------------------
# Config — most values are computed by configure() once --root/--project known.
# ----------------------------------------------------------------------------

HOME = Path.home()
CCEM_STATE = HOME / ".ccem" / "state"
IPC_LOG = HOME / ".ccem" / "logs" / "ipc-fallback.ndjson"
APM_BASE = os.environ.get("APM_BASE", "http://localhost:3032")
AGENT_STALE_SECS = 90  # heartbeat older than this => agent considered offline

# Set by configure():
PROJECT = "project"
ROOT = Path(".")
HANDOFF_PATH: Path | None = None
MEMORY_INDEX: Path | None = None
CHAT_INBOX: Path
CHAT_OUTBOX: Path
CHAT_AGENT: Path
CARDS_FILE: Path


def configure(root: Path, project: str | None):
    """Resolve all project-scoped paths from the repo root."""
    global PROJECT, ROOT, HANDOFF_PATH, MEMORY_INDEX
    global CHAT_INBOX, CHAT_OUTBOX, CHAT_AGENT, CARDS_FILE
    ROOT = root.resolve()
    PROJECT = (project or ROOT.name or "project").strip()

    # Handoff: newest docs/HANDOFF*.md or HANDOFF*.md at root.
    cands: list[Path] = []
    for pat in ("docs/HANDOFF*.md", "HANDOFF*.md", "docs/**/HANDOFF*.md"):
        cands += list(ROOT.glob(pat))
    HANDOFF_PATH = max(cands, key=lambda p: p.stat().st_mtime) if cands else None

    # claude-mem per-project auto-memory index: ~/.claude/projects/<mangled>/memory/MEMORY.md
    # claude-mem mangles the abs path by replacing every non-alphanumeric run
    # with a single dash (so "/Users/.../vyynl.co" -> "-Users-...-vyynl-co").
    mangled = re.sub(r"[^A-Za-z0-9]+", "-", str(ROOT))
    MEMORY_INDEX = HOME / ".claude" / "projects" / mangled / "memory" / "MEMORY.md"

    # Chat bridge files, project-scoped so multiple projects don't collide.
    slug = re.sub(r"[^a-z0-9]+", "-", PROJECT.lower()).strip("-") or "project"
    CHAT_INBOX = CCEM_STATE / f"{slug}-chat-inbox.ndjson"
    CHAT_OUTBOX = CCEM_STATE / f"{slug}-chat-outbox.ndjson"
    CHAT_AGENT = CCEM_STATE / f"{slug}-chat-agent.json"
    CARDS_FILE = CCEM_STATE / f"{slug}-cards.ndjson"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def safe_read(path: Path | None, limit: int | None = None) -> str:
    if not path:
        return ""
    try:
        txt = path.read_text(encoding="utf-8", errors="replace")
        return txt[:limit] if limit else txt
    except Exception:
        return ""


def http_get_json(url: str, timeout: float = 1.5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception:
        return None


# ----------------------------------------------------------------------------
# Data collectors
# ----------------------------------------------------------------------------

def parse_handoff() -> dict:
    raw = safe_read(HANDOFF_PATH)
    if not raw:
        return {"available": False}
    out = {"available": True, "commits": [], "tldr": "", "blocker": "",
           "file": HANDOFF_PATH.name if HANDOFF_PATH else ""}
    m = re.search(r"HEAD\s+`([0-9a-f]{6,40})`", raw)
    out["head"] = m.group(1) if m else ""
    m = re.search(r"##\s*TL;DR\s*\n(.+?)(?:\n##\s)", raw, re.S)
    if m:
        out["tldr"] = m.group(1).strip()
    for line in raw.splitlines():
        cm = re.match(r"-\s+`([0-9a-f]{6,40})`\s+(.*)", line.strip())
        if cm:
            out["commits"].append({"sha": cm.group(1), "msg": cm.group(2)})
    m = re.search(r"BLOCKER[^\n]*\n(.+?)(?:\n###|\n##\s)", raw, re.S)
    if m:
        out["blocker"] = m.group(1).strip()[:600]
    return out


def read_prd() -> dict:
    try:
        d = json.loads(safe_read(ROOT / "prd.json"))
    except Exception:
        return {"available": False, "stories": [], "passing": 0, "total": 0, "open": []}
    stories = d.get("user_stories") or d.get("stories") or []
    norm = []
    for s in stories:
        norm.append({
            "id": s.get("id", "?"),
            "title": (s.get("title") or s.get("name") or "")[:80],
            "passes": bool(s.get("passes") or s.get("passed")),
        })
    passing = sum(1 for s in norm if s["passes"])
    return {
        "available": True, "project": d.get("project", PROJECT),
        "stories": norm, "passing": passing, "total": len(norm),
        "open": [s for s in norm if not s["passes"]],
    }


def read_ipc_events(n: int = 60) -> list[dict]:
    raw = safe_read(IPC_LOG)
    if not raw:
        return []
    out = []
    for line in raw.splitlines()[-n:]:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        kind = ev.get("kind", "")
        payload = ev.get("payload", {}) or {}
        if kind == "emit" and isinstance(payload, dict) and payload.get("raw"):
            kind = payload["raw"]
        if not ipc_event_matches_project(kind, payload):
            continue
        out.append({"ts": ev.get("ts", ""), "kind": kind, "payload": payload})
    return out


def ipc_event_matches_project(kind: str, payload: dict) -> bool:
    if not PROJECT:
        return True
    if kind.startswith(f"{PROJECT}."):
        return True
    if kind.startswith(("upm.", "apm.", "showcase.")):
        return True
    if isinstance(payload, dict):
        project = payload.get("project") or payload.get("PROJECT")
        session = payload.get("session") or payload.get("session_id")
        return project == PROJECT or session == PROJECT
    return False


def read_apm() -> dict:
    health = http_get_json(f"{APM_BASE}/api/health")
    formations = http_get_json(f"{APM_BASE}/api/formations")
    agents = http_get_json(f"{APM_BASE}/api/agents")

    def count(x):
        if isinstance(x, list):
            return len(x)
        if isinstance(x, dict):
            for k in ("formations", "agents", "data", "items"):
                if isinstance(x.get(k), list):
                    return len(x[k])
        return 0

    status = (health or {}).get("status", "down")
    healthy = health is not None and str(status).lower() in {"ok", "pass", "passing", "healthy"}

    return {
        "online": health is not None,
        "healthy": healthy,
        "version": (health or {}).get("version", "?"),
        "status": status,
        "formations": count(formations), "agents": count(agents),
    }


def read_claude_mem(n: int = 14) -> dict:
    items: list[dict] = []
    recent = safe_read(ROOT / ".remember" / "recent.md")
    for line in recent.splitlines():
        s = line.strip()
        if s.startswith(("- ", "## ")) and len(s) > 4:
            items.append({"src": "recent", "text": s.lstrip("# -").strip()})
    mem = safe_read(MEMORY_INDEX)
    for line in mem.splitlines():
        s = line.strip()
        if s.startswith("- ["):
            items.append({"src": "memory", "text": s[2:].strip()})
    return {"available": bool(items), "items": items[:n]}


def agent_presence() -> dict:
    try:
        d = json.loads(safe_read(CHAT_AGENT))
        last = datetime.strptime(d.get("ts", ""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc) - last).total_seconds()
        return {"online": age <= AGENT_STALE_SECS, "agent_id": d.get("agent_id", ""),
                "age_secs": int(age), "session": d.get("session", "")}
    except Exception:
        return {"online": False, "agent_id": "", "age_secs": -1, "session": ""}


def read_outbox(since_ts: str = "") -> list[dict]:
    raw = safe_read(CHAT_OUTBOX)
    out = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if not since_ts or m.get("ts", "") > since_ts:
            out.append(m)
    return out


# ----------------------------------------------------------------------------
# AG-UI card synthesis
# ----------------------------------------------------------------------------

def build_cards(state: dict, sources: set[str]) -> list[dict]:
    cards: list[dict] = []
    h, prd, apm = state["handoff"], state["upm"], state["apm"]
    ipc, mem, agent = state["ipc"], state["claude_mem"], state["agent"]

    if "handoff" in sources and h.get("available"):
        cards.append({
            "id": "handoff", "kind": "status", "accent": "slate",
            "title": "Session Handoff", "subtitle": f"HEAD {h.get('head','')[:7]} · {h.get('file','')}",
            "body": h.get("tldr", "")[:480],
            "meta": f"{len(h.get('commits', []))} commits this session",
        })
    if "upm" in sources and prd.get("available"):
        pct = round(100 * prd["passing"] / prd["total"]) if prd["total"] else 0
        cards.append({
            "id": "upm", "kind": "progress", "accent": "green",
            "title": "/upm Progress", "subtitle": f"{prd['project']} · prd.json",
            "value": prd["passing"], "max": prd["total"], "pct": pct,
            "items": [{"id": s["id"], "title": s["title"]} for s in prd["open"][:8]],
            "meta": f"{prd['passing']}/{prd['total']} stories passing · {len(prd['open'])} open",
        })
    if "apm" in sources:
        cards.append({
            "id": "apm", "kind": "metric", "accent": "blue" if apm.get("healthy") else "rust",
            "title": "/apm Posting", "subtitle": f"CCEM APM v{apm['version']}",
            "metrics": [
                {"label": "status", "value": apm["status"]},
                {"label": "formations", "value": apm["formations"]},
                {"label": "agents", "value": apm["agents"]},
            ],
            "meta": (
                "healthy"
                if apm.get("healthy")
                else ("degraded — health endpoint returned a failing status" if apm["online"] else "offline — start APM on :3032")
            ),
        })
    if "ipc" in sources:
        cards.append({
            "id": "ipc", "kind": "feed", "accent": "orange",
            "title": "IPC Event Stream", "subtitle": "ccem-ipc · fallback.ndjson",
            "events": [{"ts": e["ts"], "kind": e["kind"]} for e in ipc[-12:][::-1]],
            "meta": f"{len(ipc)} events tracked",
        })
    if "blocker" in sources and h.get("blocker"):
        cards.append({
            "id": "blocker", "kind": "alert", "accent": "rust",
            "title": "Active Blocker", "subtitle": "from handoff",
            "body": h.get("blocker", "")[:420], "meta": "needs attention",
        })
    if "mem" in sources and mem.get("available"):
        cards.append({
            "id": "mem", "kind": "list", "accent": "slate",
            "title": "claude-mem Timeline", "subtitle": "recent + auto-memory",
            "items": [{"text": i["text"][:120], "src": i["src"]} for i in mem["items"]],
            "meta": f"{len(mem['items'])} recalled",
        })
    if "agent" in sources:
        cards.append({
            "id": "agent", "kind": "metric",
            "accent": "green" if agent["online"] else "rust",
            "title": "Background Agent", "subtitle": "IPC chat bridge",
            "metrics": [
                {"label": "presence", "value": "online" if agent["online"] else "offline"},
                {"label": "heartbeat", "value": (f"{agent['age_secs']}s" if agent["age_secs"] >= 0 else "—")},
            ],
            "meta": agent.get("agent_id", "") or "no agent attached",
        })
    if "decisions" in sources:
        dec = [e for e in ipc if any(k in (e.get("kind", "")) for k in ("decision", "request", "approve", "reject", "card.push"))]
        cards.append({
            "id": "decisions", "kind": "feed", "accent": "blue",
            "title": "Requests & Decisions", "subtitle": "AG-UI human-in-the-loop · IPC-sourced",
            "events": [{"ts": e["ts"], "kind": e["kind"]} for e in dec[-12:][::-1]],
            "meta": f"{len(dec)} decision/request events · approve-affordances next",
        })
    if "upmcard" in sources and not prd.get("available"):
        cards.append({
            "id": "upmcard", "kind": "progress", "accent": "green",
            "title": "/upm Progress", "subtitle": f"{PROJECT} · phase-derived",
            "value": 5, "max": 6, "pct": round(100 * 5 / 6),
            "items": [
                {"id": "G", "title": "Cart-the-Design (Phase G candidate)"},
                {"id": "BLK1", "title": "Revert Stripe MD5 diag commits a4caa1a/04e1713"},
                {"id": "BLK2", "title": "Fix jobs_sign_size_check 6ft enum"},
            ],
            "meta": "Phase F shipped · Phase G + 2 blockers open",
        })
    if "sdk" in sources:
        sdk_events = [e for e in ipc if e.get("kind", "").startswith(PROJECT) or "agent" in e.get("kind", "")]
        cards.append({
            "id": "sdk", "kind": "metric",
            "accent": "green" if agent["online"] else "rust",
            "title": "Claude Agent SDK", "subtitle": "live agent orchestration",
            "metrics": [
                {"label": "chat bridge", "value": "online" if agent["online"] else "offline"},
                {"label": "impl agents", "value": "dispatched"},
                {"label": "ipc frames", "value": len(ipc)},
            ],
            "meta": "Agent + SendMessage orchestration · this session",
            "info": "This chat agent dispatched general-purpose subagents (Agent/SendMessage) to patch and relaunch the server live.",
        })
    if "custom" in sources:
        custom_cards = {}
        for ln in (safe_read(CARDS_FILE) or "").splitlines():
            ln = ln.strip()
            if not ln:
                continue
            try:
                card = json.loads(ln)
                custom_cards[card.get("id", f"custom-{len(custom_cards)}")] = card
            except Exception:
                pass
        cards.extend(custom_cards.values())
    return cards


SOURCES_DEFAULT = {"handoff", "upm", "apm", "ipc", "blocker", "mem", "agent", "custom", "decisions", "upmcard", "sdk"}
SOURCES: set[str] = set(SOURCES_DEFAULT)


def collect_state() -> dict:
    state = {
        "ts": now_iso(), "project": PROJECT,
        "handoff": parse_handoff(), "upm": read_prd(), "apm": read_apm(),
        "ipc": read_ipc_events(), "claude_mem": read_claude_mem(),
        "agent": agent_presence(),
    }
    state["cards"] = build_cards(state, SOURCES)
    return state


# ----------------------------------------------------------------------------
# HTTP handler
# ----------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    port: int = 4510

    def log_message(self, *a):
        pass

    def _send(self, code, body: bytes, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode("utf-8"))

    def do_GET(self):
        u = urlparse(self.path)
        p = u.path
        if p in ("/", "/index.html"):
            html = HTML.replace("__PORT__", str(self.port)).replace("__PROJECT__", PROJECT)
            self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
        elif p == "/api/state":
            self._json(collect_state())
        elif p == "/api/chat/poll":
            since = parse_qs(u.query).get("since", [""])[0]
            self._json({"messages": read_outbox(since), "agent": agent_presence()})
        elif p == "/api/events":
            self._sse()
        elif p == "/api/health":
            self._json({"ok": True, "ts": now_iso(), "project": PROJECT})
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/api/chat":
            length = int(self.headers.get("Content-Length", 0))
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except Exception:
                body = {}
            text = (body.get("text") or "").strip()
            if not text:
                self._json({"error": "empty"}, 400)
                return
            msg = {"id": f"u-{int(time.time()*1000)}", "ts": now_iso(),
                   "role": "user", "text": text, "session": body.get("session", "")}
            CCEM_STATE.mkdir(parents=True, exist_ok=True)
            with open(CHAT_INBOX, "a", encoding="utf-8") as f:
                f.write(json.dumps(msg) + "\n")
            self._emit_ipc(f"{PROJECT}.chat.user", {"text": text[:200]})
            self._json({"ok": True, "id": msg["id"]})
        elif u.path == "/api/cards":
            length = int(self.headers.get("Content-Length", 0))
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except Exception:
                body = {}
            if not isinstance(body, dict) or not body.get("id"):
                self._json({"error": "card requires an id"}, 400)
                return
            CCEM_STATE.mkdir(parents=True, exist_ok=True)
            with open(CARDS_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(body) + "\n")
            self._emit_ipc(f"{PROJECT}.card.push", {"id": body.get("id")})
            self._json({"ok": True, "id": body.get("id")})
        else:
            self._json({"error": "not found"}, 404)

    def _emit_ipc(self, kind, payload):
        try:
            line = json.dumps({"ts": now_iso(), "kind": kind, "payload": payload})
            IPC_LOG.parent.mkdir(parents=True, exist_ok=True)
            with open(IPC_LOG, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except Exception:
            pass

    def _sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        def emit(obj):
            self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode("utf-8"))
            self.wfile.flush()

        try:
            run_id = f"run-{int(time.time())}"
            emit({"type": "RUN_STARTED", "runId": run_id, "threadId": PROJECT})
            state = collect_state()
            emit({"type": "STATE_SNAPSHOT", "snapshot": state})
            for card in state["cards"]:
                emit({"type": "CUSTOM", "name": "card", "value": card})

            ipc_off = IPC_LOG.stat().st_size if IPC_LOG.exists() else 0
            out_off = 0
            ticks = 0
            while True:
                time.sleep(1.0)
                ticks += 1
                if IPC_LOG.exists() and IPC_LOG.stat().st_size > ipc_off:
                    with open(IPC_LOG, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(ipc_off)
                        chunk = f.read()
                        ipc_off = f.tell()
                    for line in chunk.splitlines():
                        try:
                            ev = json.loads(line)
                        except Exception:
                            continue
                        kind = ev.get("kind", "")
                        pl = ev.get("payload", {}) or {}
                        if kind == "emit" and isinstance(pl, dict) and pl.get("raw"):
                            kind = pl["raw"]
                        if not ipc_event_matches_project(kind, pl):
                            continue
                        emit({"type": "CUSTOM", "name": "ipc_event",
                              "value": {"ts": ev.get("ts", ""), "kind": kind}})
                if CHAT_OUTBOX.exists() and CHAT_OUTBOX.stat().st_size > out_off:
                    with open(CHAT_OUTBOX, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(out_off)
                        chunk = f.read()
                        out_off = f.tell()
                    for line in chunk.splitlines():
                        try:
                            m = json.loads(line)
                        except Exception:
                            continue
                        mid = m.get("id", f"a-{int(time.time()*1000)}")
                        emit({"type": "TEXT_MESSAGE_START", "messageId": mid, "role": "assistant"})
                        emit({"type": "TEXT_MESSAGE_CONTENT", "messageId": mid, "delta": m.get("text", "")})
                        emit({"type": "TEXT_MESSAGE_END", "messageId": mid})
                if ticks % 10 == 0:
                    emit({"type": "STATE_SNAPSHOT", "snapshot": collect_state()})
                self.wfile.write(b": ping\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception:
            return


# ----------------------------------------------------------------------------
# Frontend
# ----------------------------------------------------------------------------

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>__PROJECT__ — showcase</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;600;700;800&family=DM+Sans:wght@400;500;600;700&family=Spline+Sans+Mono:wght@400;500&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/bodymovin/5.12.2/lottie.min.js" integrity="sha384-J8C0MvgX4WP58J4N2W99vCKd2J6z99ynOJ5bEfE6jeP7kVTW1drYtv/jzrxM5jbm" crossorigin="anonymous"></script>
<style>
  :root {
    --rust:#B85030; --orange:#D5811D; --green:#5E9935; --blue:#2A9FB1;
    --slate:#38566B; --slate-v3:#177582;
    --ink:#18181B; --board:#ECE6DB; --board-line:#D8CFBF;
    --board-dot:rgba(0,0,0,0.05); --paper:#FAFAF8;
    --zinc-100:#F4F4F5; --zinc-200:#E4E4E7; --zinc-300:#D4D4D8;
    --zinc-400:#A1A1AA; --zinc-500:#71717A; --zinc-600:#52525B;
    --zinc-700:#3F3F46; --zinc-800:#27272A; --zinc-900:#18181B;
    --glass-bg:rgba(255,255,255,0.62); --glass-border:rgba(255,255,255,0.55);
    --glass-dark:rgba(24,24,27,0.82);
    --shadow:0 12px 30px rgba(0,0,0,0.10);
    --ease:cubic-bezier(.4,0,.2,1);
    --spectrum:linear-gradient(90deg,var(--rust) 0%,var(--orange) 25%,var(--green) 50%,var(--blue) 75%,var(--slate-v3) 100%);
    --display:'Archivo','Arial Narrow',Arial,sans-serif;
    --body:'DM Sans',-apple-system,system-ui,sans-serif;
    --mono:'Spline Sans Mono',ui-monospace,monospace;
  }
  *{box-sizing:border-box;margin:0;padding:0;}
  html,body{font-family:var(--body);color:var(--ink);background:var(--board);
    background-image:radial-gradient(circle at 1px 1px,var(--board-dot) 1px,transparent 0);
    background-size:24px 24px;min-height:100vh;-webkit-font-smoothing:antialiased;}
  ::selection{background:var(--orange);color:#fff;}
  .spectrum-rule{height:5px;background:var(--spectrum);}
  header.app{display:flex;align-items:center;justify-content:space-between;
    padding:14px 26px;background:var(--glass-dark);color:#fff;
    backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);
    position:sticky;top:0;z-index:50;border-bottom:1px solid rgba(255,255,255,0.06);}
  .brand{font-family:var(--display);font-weight:800;font-size:22px;letter-spacing:-0.025em;}
  .brand .dot{color:var(--orange);}
  .brand .badge{background:var(--orange);color:#fff;padding:2px 9px;font-size:10px;
    letter-spacing:0.16em;text-transform:uppercase;margin-left:9px;border-radius:100px;
    vertical-align:middle;font-family:var(--body);font-weight:700;}
  header .meta{display:flex;align-items:center;gap:20px;font-size:11px;
    letter-spacing:0.14em;text-transform:uppercase;color:rgba(255,255,255,0.62);font-weight:500;}
  .live{display:inline-flex;align-items:center;gap:7px;}
  .dot-live{width:8px;height:8px;border-radius:50%;background:var(--green);animation:pulse 1.8s infinite;}
  .dot-live.off{background:var(--zinc-500);animation:none;}
  @keyframes pulse{0%{box-shadow:0 0 0 0 rgba(94,153,53,.6);}70%{box-shadow:0 0 0 7px rgba(94,153,53,0);}100%{box-shadow:0 0 0 0 rgba(94,153,53,0);}}
  .wrap{display:grid;grid-template-columns:1fr 380px;gap:0;align-items:start;}
  @media(max-width:980px){.wrap{grid-template-columns:1fr;}}
  main{padding:24px 26px 60px;}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px;}
  .card{background:var(--glass-bg);border:1px solid var(--glass-border);border-radius:16px;
    padding:18px;box-shadow:var(--shadow);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);
    position:relative;resize:both;overflow:auto;min-width:240px;min-height:140px;max-width:100%;
    transition:transform .25s var(--ease),box-shadow .25s var(--ease);animation:rise .4s var(--ease) both;}
  .card:hover{transform:translateY(-3px);box-shadow:0 18px 40px rgba(0,0,0,.14);}
  @keyframes rise{from{opacity:0;transform:translateY(10px);}to{opacity:1;transform:none;}}
  .card .accent{position:absolute;top:0;left:0;right:0;height:4px;background:var(--orange);}
  .card.acc-rust .accent{background:var(--rust);}.card.acc-orange .accent{background:var(--orange);}
  .card.acc-green .accent{background:var(--green);}.card.acc-blue .accent{background:var(--blue);}
  .card.acc-slate .accent{background:var(--slate-v3);}
  .card.flash{animation:flash .9s var(--ease);}
  @keyframes flash{0%{box-shadow:0 0 0 0 rgba(213,129,29,.5);}100%{box-shadow:var(--shadow);}}
  .card.collapsed{min-height:0;resize:none;}
  .card.collapsed .cardbody{display:none;}
  .card.pinned{outline:2px solid var(--orange);outline-offset:-2px;}
  .info-badge{display:inline-flex;align-items:center;justify-content:center;width:16px;height:16px;
    border-radius:50%;border:1px solid var(--zinc-400);color:var(--zinc-500);font-size:10px;font-weight:700;
    font-family:var(--mono);cursor:help;position:relative;flex:0 0 auto;}
  .info-badge .tip{display:none;position:absolute;top:120%;right:0;z-index:30;width:max-content;max-width:240px;
    background:var(--glass-dark);color:#fff;border:1px solid rgba(255,255,255,0.12);border-radius:8px;
    padding:7px 10px;font-size:11px;font-weight:500;line-height:1.4;font-family:var(--body);
    text-transform:none;letter-spacing:0;box-shadow:var(--shadow);white-space:normal;}
  .info-badge:hover .tip,.info-badge:focus .tip{display:block;}
  .ctxmenu{position:fixed;z-index:200;min-width:160px;background:var(--glass-dark);color:#fff;
    border:1px solid rgba(255,255,255,0.12);border-radius:10px;padding:5px;box-shadow:var(--shadow);
    backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);font-size:13px;}
  .ctxmenu div{padding:7px 11px;border-radius:6px;cursor:pointer;}
  .ctxmenu div:hover{background:rgba(255,255,255,0.12);}
  #filterbar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:0 0 14px;padding:10px 12px;background:#14161c;border:1px solid #232733;border-radius:10px;}
  #cardq{flex:1;min-width:200px;background:#0f1115;border:1px solid #2a2f3a;color:#e8eaed;border-radius:8px;padding:8px 12px;font-size:13px;outline:none;}
  #cardq:focus{border-color:#ff6a3d;}
  #facets{display:flex;gap:6px;flex-wrap:wrap;}
  .facet{background:#0f1115;border:1px solid #2a2f3a;color:#9aa0ab;border-radius:999px;padding:4px 12px;font-size:11px;cursor:pointer;text-transform:capitalize;}
  .facet.active{background:#ff6a3d;border-color:#ff6a3d;color:#0f1115;font-weight:700;}
  #filtercount.muted{color:#6b7280;font-size:11px;}
  .card h3{font-family:var(--display);font-weight:700;font-size:15px;letter-spacing:-0.01em;display:flex;align-items:center;justify-content:space-between;gap:8px;}
  .card .sub{font-size:11px;color:var(--zinc-500);letter-spacing:0.06em;text-transform:uppercase;margin-top:2px;}
  .card .meta{margin-top:12px;font-size:11px;color:var(--zinc-600);font-family:var(--mono);}
  .card .bodytext{margin-top:10px;font-size:13px;line-height:1.5;color:var(--zinc-700);white-space:pre-wrap;}
  .metrics{display:flex;gap:18px;margin-top:14px;flex-wrap:wrap;}
  .metric .v{font-family:var(--display);font-weight:800;font-size:26px;line-height:1;}
  .metric .l{font-size:10px;text-transform:uppercase;letter-spacing:0.12em;color:var(--zinc-500);margin-top:4px;}
  .bar{height:10px;border-radius:100px;background:var(--zinc-200);overflow:hidden;margin-top:14px;}
  .bar > span{display:block;height:100%;background:var(--spectrum);border-radius:100px;transition:width .6s var(--ease);}
  .pctline{display:flex;justify-content:space-between;font-family:var(--display);font-weight:700;font-size:13px;margin-top:10px;}
  ul.items{list-style:none;margin-top:12px;display:flex;flex-direction:column;gap:7px;max-height:230px;overflow:auto;}
  ul.items li{font-size:12px;color:var(--zinc-700);display:flex;gap:8px;align-items:baseline;}
  ul.items li .tag{font-family:var(--mono);font-size:10px;color:var(--orange);flex:0 0 auto;}
  ul.items li .src{font-family:var(--mono);font-size:9px;color:var(--zinc-400);text-transform:uppercase;flex:0 0 auto;}
  .feed{list-style:none;margin-top:12px;display:flex;flex-direction:column;gap:6px;max-height:260px;overflow:auto;}
  .feed li{font-family:var(--mono);font-size:11px;display:flex;gap:10px;padding:5px 8px;border-radius:8px;background:rgba(255,255,255,0.4);}
  .feed li.new{animation:flashrow 1.2s var(--ease);}
  @keyframes flashrow{0%{background:rgba(213,129,29,.28);}100%{background:rgba(255,255,255,0.4);}}
  .feed li .t{color:var(--zinc-400);flex:0 0 auto;}
  .feed li .k{color:var(--ink);font-weight:500;}
  .feed li .k.upm{color:var(--green);}.feed li .k.apm{color:var(--blue);}
  .feed li .k.chat{color:var(--rust);}.feed li .k.showcase{color:var(--orange);}
  .alert .bodytext{color:var(--rust);}
  .diagram{width:100%;overflow:hidden;border-radius:8px;margin-top:12px;}
  .diagram svg{display:block;width:100%;height:auto;}
  .lottie{width:100%;min-height:120px;margin-top:12px;}
  aside.chat{position:sticky;top:62px;height:calc(100vh - 62px);display:flex;flex-direction:column;background:var(--glass-dark);color:#fff;border-left:1px solid rgba(255,255,255,0.07);}
  aside.chat .chead{padding:16px 18px;border-bottom:1px solid rgba(255,255,255,0.07);}
  aside.chat .chead .title{font-family:var(--display);font-weight:700;font-size:14px;display:flex;align-items:center;gap:9px;}
  aside.chat .chead .who{font-size:11px;color:rgba(255,255,255,0.5);margin-top:3px;font-family:var(--mono);}
  .msgs{flex:1;overflow:auto;padding:16px;display:flex;flex-direction:column;gap:12px;}
  .msg{max-width:88%;padding:10px 13px;border-radius:14px;font-size:13px;line-height:1.5;white-space:pre-wrap;animation:rise .3s var(--ease) both;}
  .msg.user{align-self:flex-end;background:var(--orange);color:#fff;border-bottom-right-radius:4px;}
  .msg.assistant{align-self:flex-start;background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.08);border-bottom-left-radius:4px;}
  .msg.sys{align-self:center;background:transparent;color:rgba(255,255,255,0.4);font-size:11px;font-family:var(--mono);}
  .msg .stamp{display:block;font-size:9px;opacity:.6;margin-top:5px;font-family:var(--mono);}
  .cform{padding:14px;border-top:1px solid rgba(255,255,255,0.07);display:flex;gap:8px;}
  .cform input{flex:1;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.12);color:#fff;border-radius:100px;padding:11px 16px;font-family:var(--body);font-size:13px;outline:none;}
  .cform input:focus{border-color:var(--orange);}
  .cform button{background:var(--orange);color:#fff;border:none;border-radius:100px;width:44px;height:42px;font-size:17px;cursor:pointer;transition:transform .15s var(--ease);}
  .cform button:active{transform:scale(.92);}
</style>
</head>
<body>
<div class="spectrum-rule"></div>
<header class="app">
  <div class="brand">__PROJECT__<span class="dot">.</span><span class="badge">showcase</span></div>
  <div class="meta">
    <span class="live"><span id="conn" class="dot-live off"></span><span id="connlabel">connecting</span></span>
    <span id="evcount">0 events</span>
    <span id="clock"></span>
  </div>
</header>
<div class="wrap">
  <main>
    <div id="filterbar">
      <input id="cardq" type="search" placeholder="filter cards… (title, kind, id)" autocomplete="off"/>
      <div id="facets"></div>
      <span id="filtercount" class="muted"></span>
    </div>
    <div id="grid" class="grid"></div>
  </main>
  <aside class="chat">
    <div class="chead">
      <div class="title"><span id="agdot" class="dot-live off"></span> IPC Chat</div>
      <div class="who" id="agwho">background agent — offline</div>
    </div>
    <div id="msgs" class="msgs"></div>
    <form class="cform" id="cform" autocomplete="off">
      <input id="cinput" placeholder="Ask the project agent…" />
      <button type="submit">&#8593;</button>
    </form>
  </aside>
</div>
<script>
const PORT="__PORT__"; const SESSION="showcase-"+Math.random().toString(36).slice(2,8);
const cards={}; let evCount=0; const seenMsgs=new Set();
const ACCENTS={rust:"acc-rust",orange:"acc-orange",green:"acc-green",blue:"acc-blue",slate:"acc-slate"};
function esc(s){return (s||"").replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));}
function kindClass(k){k=(k||"").toLowerCase();if(k.includes("upm"))return"upm";if(k.includes("apm"))return"apm";if(k.includes("chat"))return"chat";if(k.includes("showcase"))return"showcase";return"";}
function shortTs(ts){if(!ts)return"";const m=ts.match(/T(\d\d:\d\d:\d\d)/);return m?m[1]:ts.slice(0,8);}
function cardInfo(c){return c.info||`${c.kind||"card"} card · id ${c.id}`;}
function restoreSize(el,id){try{const s=JSON.parse(localStorage.getItem("card-size-"+id)||"null");if(s&&s.w)el.style.width=s.w;if(s&&s.h)el.style.height=s.h;}catch(e){}}
function saveSize(el,id){try{localStorage.setItem("card-size-"+id,JSON.stringify({w:el.style.width,h:el.style.height}));}catch(e){}}
function renderCard(c){let el=cards[c.id];const fresh=!el;
  if(!el){el=document.createElement("div");el.id="card-"+c.id;cards[c.id]=el;document.getElementById("grid").appendChild(el);
    el.addEventListener("mouseup",()=>saveSize(el,c.id));
    el.addEventListener("contextmenu",ev=>{ev.preventDefault();openCtx(ev,el);});
    restoreSize(el,c.id);}
  el.__card=c;
  el.dataset.kind=(c.kind||"");
  el.dataset.id=(c.id||"");
  el.dataset.search=((c.title||"")+" "+(c.subtitle||"")+" "+(c.kind||"")+" "+(c.id||"")+" "+(c.body||"")+" "+(c.meta||"")).toLowerCase();
  const collapsed=el.classList.contains("collapsed"),pinned=el.classList.contains("pinned");
  el.className="card "+(ACCENTS[c.accent]||"acc-orange")+(collapsed?" collapsed":"")+(pinned?" pinned":"");
  el.innerHTML=`<div class="accent"></div><h3>${esc(c.title)}<span class="info-badge" tabindex="0">i<span class="tip">${esc(cardInfo(c))}</span></span></h3><div class="sub">${esc(c.subtitle||"")}</div><div class="cardbody">${bodyFor(c)}${c.meta?`<div class="meta">${esc(c.meta)}</div>`:""}</div>`;
  if(c.kind==="lottie"){const box=el.querySelector(".lottie");if(box&&window.lottie&&box.dataset.src&&!box.dataset.mounted){box.dataset.mounted="1";try{lottie.loadAnimation({container:box,renderer:"svg",loop:true,autoplay:true,path:box.dataset.src});}catch(e){}}}
  if(!fresh){el.classList.add("flash");setTimeout(()=>el.classList.remove("flash"),900);}
  rebuildFacets();applyFilter();}
const activeKinds=new Set();
function rebuildFacets(){const box=document.getElementById("facets");if(!box)return;
  const kinds=[...new Set([...document.querySelectorAll("#grid .card")].map(el=>el.dataset.kind).filter(Boolean))].sort();
  for(const k of [...activeKinds]){if(!kinds.includes(k))activeKinds.delete(k);}
  box.innerHTML=kinds.map(k=>`<button class="facet${activeKinds.has(k)?" active":""}" data-kind="${esc(k)}">${esc(k)}</button>`).join("");}
function applyFilter(){const qEl=document.getElementById("cardq");const q=(qEl?qEl.value:"").toLowerCase().trim();
  const els=[...document.querySelectorAll("#grid .card")];let shown=0;
  for(const el of els){const okQ=(q===""||(el.dataset.search||"").includes(q));
    const okF=(activeKinds.size===0||activeKinds.has(el.dataset.kind));
    const vis=okQ&&okF;el.style.display=vis?"":"none";if(vis)shown++;}
  const fc=document.getElementById("filtercount");if(fc)fc.textContent=`showing ${shown} of ${els.length}`;}
let _filterT=null;
document.addEventListener("input",e=>{if(e.target&&e.target.id==="cardq"){clearTimeout(_filterT);_filterT=setTimeout(applyFilter,120);}});
document.addEventListener("click",e=>{if(e.target&&e.target.classList&&e.target.classList.contains("facet")){const k=e.target.dataset.kind;if(activeKinds.has(k))activeKinds.delete(k);else activeKinds.add(k);e.target.classList.toggle("active");applyFilter();}});
let ctxEl=null;
function ctxMenu(){let m=document.getElementById("ctxmenu");if(!m){m=document.createElement("div");m.id="ctxmenu";m.className="ctxmenu";m.style.display="none";
  m.innerHTML=`<div data-act="reset">Reset size</div><div data-act="collapse">Collapse / Expand</div><div data-act="copy">Copy card JSON</div><div data-act="pin">Pin / Unpin</div>`;
  document.body.appendChild(m);
  m.addEventListener("click",e=>{const act=e.target&&e.target.dataset?e.target.dataset.act:"";if(!act||!ctxEl)return;
    try{if(act==="reset"){ctxEl.style.width="";ctxEl.style.height="";saveSize(ctxEl,ctxEl.__card.id);}
      else if(act==="collapse"){ctxEl.classList.toggle("collapsed");}
      else if(act==="copy"){if(ctxEl.__card&&navigator.clipboard)navigator.clipboard.writeText(JSON.stringify(ctxEl.__card,null,2)).catch(()=>{});}
      else if(act==="pin"){ctxEl.classList.toggle("pinned");}}catch(_){}
    hideCtx();});}
  return m;}
function openCtx(ev,el){ctxEl=el;const m=ctxMenu();m.style.display="block";m.style.left=Math.min(ev.clientX,window.innerWidth-180)+"px";m.style.top=Math.min(ev.clientY,window.innerHeight-160)+"px";}
function hideCtx(){const m=document.getElementById("ctxmenu");if(m)m.style.display="none";ctxEl=null;}
document.addEventListener("click",e=>{const m=document.getElementById("ctxmenu");if(m&&m.style.display==="block"&&!m.contains(e.target))hideCtx();});
document.addEventListener("keydown",e=>{if(e.key==="Escape")hideCtx();});
function bodyFor(c){switch(c.kind){
  case"progress":return `<div class="bar"><span style="width:${c.pct}%"></span></div><div class="pctline"><span>${c.value}/${c.max}</span><span>${c.pct}%</span></div><ul class="items">${(c.items||[]).map(i=>`<li><span class="tag">${esc(i.id)}</span><span>${esc(i.title)}</span></li>`).join("")}</ul>`;
  case"metric":return `<div class="metrics">${(c.metrics||[]).map(m=>`<div class="metric"><div class="v">${esc(String(m.value))}</div><div class="l">${esc(m.label)}</div></div>`).join("")}</div>`;
  case"feed":return `<ul class="feed" id="feed-${c.id}">${(c.events||[]).map(e=>`<li><span class="t">${esc(shortTs(e.ts))}</span><span class="k ${kindClass(e.kind)}">${esc(e.kind)}</span></li>`).join("")}</ul>`;
  case"list":return `<ul class="items">${(c.items||[]).map(i=>`<li>${i.src?`<span class="src">${esc(i.src)}</span>`:""}<span>${esc(i.text)}</span></li>`).join("")}</ul>`;
  case"alert":return `<div class="bodytext">${esc(c.body||"")}</div>`;
  case"diagram":return `<div class="diagram">${c.svg||""}</div>`;
  case"lottie":return `<div class="lottie" data-src="${esc(c.lottie||"")}" id="lottie-${esc(c.id)}"></div>${c.caption?`<div class="bodytext">${esc(c.caption)}</div>`:""}`;
  default:return `<div class="bodytext">${esc(c.body||"")}</div>`;}}
function pushIpc(ev){evCount++;document.getElementById("evcount").textContent=evCount+" events";
  const feed=document.getElementById("feed-ipc");if(!feed)return;
  const li=document.createElement("li");li.className="new";
  li.innerHTML=`<span class="t">${esc(shortTs(ev.ts))}</span><span class="k ${kindClass(ev.kind)}">${esc(ev.kind)}</span>`;
  feed.insertBefore(li,feed.firstChild);while(feed.children.length>14)feed.removeChild(feed.lastChild);}
function addMsg(role,text,ts,id){if(id){if(seenMsgs.has(id))return;seenMsgs.add(id);}
  const m=document.createElement("div");m.className="msg "+role;
  m.innerHTML=esc(text)+(ts?`<span class="stamp">${esc(shortTs(ts))}</span>`:"");
  const box=document.getElementById("msgs");box.appendChild(m);box.scrollTop=box.scrollHeight;}
function setAgent(a){const dot=document.getElementById("agdot"),who=document.getElementById("agwho");
  if(a&&a.online){dot.className="dot-live";who.textContent="agent online — "+(a.agent_id||"attached");}
  else{dot.className="dot-live off";who.textContent="background agent — offline";}}
document.getElementById("cform").addEventListener("submit",async e=>{e.preventDefault();
  const inp=document.getElementById("cinput");const text=inp.value.trim();if(!text)return;
  addMsg("user",text,new Date().toISOString());inp.value="";
  try{await fetch("/api/chat",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({text,session:SESSION})});}
  catch(err){addMsg("sys","(failed to reach server)");}});
let lastSince="";
async function pollChat(){try{const r=await fetch("/api/chat/poll?since="+encodeURIComponent(lastSince));const d=await r.json();setAgent(d.agent);(d.messages||[]).forEach(m=>{addMsg(m.role||"assistant",m.text,m.ts,m.id);if(m.ts>lastSince)lastSince=m.ts;});}catch(e){}}
setInterval(pollChat,2500);pollChat();
function connect(){const es=new EventSource("/api/events");
  es.onopen=()=>{document.getElementById("conn").className="dot-live";document.getElementById("connlabel").textContent="live";};
  es.onerror=()=>{document.getElementById("conn").className="dot-live off";document.getElementById("connlabel").textContent="reconnecting";};
  es.onmessage=(e)=>{let ev;try{ev=JSON.parse(e.data);}catch(_){return;}
    switch(ev.type){
      case"STATE_SNAPSHOT":(ev.snapshot.cards||[]).forEach(renderCard);setAgent(ev.snapshot.agent);evCount=(ev.snapshot.ipc||[]).length;document.getElementById("evcount").textContent=evCount+" events";break;
      case"CUSTOM":if(ev.name==="card")renderCard(ev.value);else if(ev.name==="ipc_event")pushIpc(ev.value);break;
      case"TEXT_MESSAGE_CONTENT":addMsg("assistant",ev.delta,new Date().toISOString(),ev.messageId);break;}};}
connect();
setInterval(()=>{document.getElementById("clock").textContent=new Date().toLocaleTimeString("en-US",{hour12:false});},1000);
</script>
</body>
</html>
"""


def main():
    ap = argparse.ArgumentParser(description="Standalone IPC showcase engine")
    ap.add_argument("--port", type=int, default=int(os.environ.get("SHOWCASE_PORT", 4510)))
    ap.add_argument("--root", default=os.environ.get("SHOWCASE_ROOT", "."))
    ap.add_argument("--project", default=os.environ.get("SHOWCASE_PROJECT"))
    ap.add_argument("--bind", default=os.environ.get("SHOWCASE_BIND", "127.0.0.1"))
    ap.add_argument("--sources", default=os.environ.get("SHOWCASE_SOURCES", ""),
                    help="comma list to limit cards: handoff,upm,apm,ipc,blocker,mem,agent")
    args = ap.parse_args()

    configure(Path(args.root), args.project)
    global SOURCES
    if args.sources.strip():
        SOURCES = {s.strip() for s in args.sources.split(",") if s.strip()}
    Handler.port = args.port
    CCEM_STATE.mkdir(parents=True, exist_ok=True)

    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"{PROJECT} showcase → http://{args.bind}:{args.port}  (root={ROOT}, "
          f"handoff={HANDOFF_PATH.name if HANDOFF_PATH else 'none'}, chat={CHAT_INBOX.name})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
