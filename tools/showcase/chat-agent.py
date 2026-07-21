#!/usr/bin/env python3
"""
chat-agent.py — bridge worker CLI for the showcase IPC chat.

A background Claude agent drives this so it only has to *compose* answers;
the mechanics (heartbeat, atomic next-message pull, reply posting, IPC emit)
live here. File-based so the bridge survives any single agent's lifetime.

Subcommands:
  beat   <agent_id> <session>        write/refresh presence heartbeat
  next                               print next unanswered user msg as JSON
                                     (or nothing); advances the cursor
  wait   [timeout] [agent_id]        long-poll (Python sleep, not shell) up to
                                     timeout secs for the next msg; advances the
                                     cursor and refreshes heartbeat while waiting
  reply  <reply_to_id> <text...>     post an assistant reply + emit IPC + beat
  peek                               list pending (unanswered) messages

State files (under ~/.ccem/state/):
  vyynl-chat-inbox.ndjson    user messages (written by the showcase server)
  vyynl-chat-outbox.ndjson   assistant replies (read by the server -> browser)
  vyynl-chat-agent.json      presence heartbeat
  vyynl-chat-cursor          count of inbox lines already consumed
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Project slug determines the bridge file prefix so multiple projects can run
# concurrent chat agents without colliding. Server + agent must agree on it;
# both read SHOWCASE_PROJECT (default "vyynl" for back-compat with this repo).
_PROJ = os.environ.get("SHOWCASE_PROJECT", "vyynl")
SLUG = re.sub(r"[^a-z0-9]+", "-", _PROJ.lower()).strip("-") or "project"

STATE = Path.home() / ".ccem" / "state"
INBOX = STATE / f"{SLUG}-chat-inbox.ndjson"
OUTBOX = STATE / f"{SLUG}-chat-outbox.ndjson"
AGENT = STATE / f"{SLUG}-chat-agent.json"
CURSOR = STATE / f"{SLUG}-chat-cursor"
IPC = Path.home() / ".ccem" / "bin" / "ccem-ipc.sh"


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_lines(p: Path) -> list[dict]:
    out = []
    try:
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    except FileNotFoundError:
        pass
    return out


def get_cursor() -> int:
    try:
        return int(CURSOR.read_text().strip())
    except Exception:
        return 0


def set_cursor(n: int):
    CURSOR.write_text(str(n))


def emit_ipc(kind: str, payload: dict):
    try:
        if IPC.exists():
            subprocess.Popen(
                ["bash", str(IPC), kind, json.dumps(payload)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    except Exception:
        pass


def write_beat(agent_id: str, session: str = ""):
    STATE.mkdir(parents=True, exist_ok=True)
    AGENT.write_text(json.dumps({
        "ts": now(), "agent_id": agent_id, "session": session, "status": "online",
    }))


def cmd_beat(agent_id: str, session: str = ""):
    write_beat(agent_id, session)
    print("ok")


def cmd_next():
    msgs = read_lines(INBOX)
    cur = get_cursor()
    if cur < len(msgs):
        msg = msgs[cur]
        set_cursor(cur + 1)
        print(json.dumps(msg))
    # else: print nothing


def cmd_wait(timeout: float = 25.0, agent_id: str = "agent"):
    """Block up to `timeout` secs (Python sleep, not shell) for the next msg.

    Refreshes the heartbeat each poll so the UI shows the agent online while
    it idles. Prints the message JSON and advances the cursor, or prints
    nothing on timeout.
    """
    deadline = time.time() + timeout
    while True:
        write_beat(agent_id, "")  # keep presence fresh (no stdout)
        msgs = read_lines(INBOX)
        cur = get_cursor()
        if cur < len(msgs):
            set_cursor(cur + 1)
            sys.stderr.write("hit\n")
            print(json.dumps(msgs[cur]))
            return
        if time.time() >= deadline:
            return
        time.sleep(2.0)


def cmd_peek():
    msgs = read_lines(INBOX)
    cur = get_cursor()
    pending = msgs[cur:]
    print(json.dumps({"pending": len(pending), "messages": pending}))


def cmd_reply(reply_to: str, text: str):
    STATE.mkdir(parents=True, exist_ok=True)
    rec = {
        "id": f"a-{int(datetime.now().timestamp()*1000)}",
        "ts": now(), "role": "assistant", "text": text, "reply_to": reply_to,
    }
    with open(OUTBOX, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
    emit_ipc(f"{SLUG}.chat.assistant", {"reply_to": reply_to, "len": len(text)})
    print("ok " + rec["id"])


def cmd_card(card_json: str):
    try:
        card = json.loads(card_json)
    except Exception as e:
        print(f"bad json: {e}", file=sys.stderr); sys.exit(2)
    CARDS = STATE / f"{SLUG}-cards.ndjson"
    STATE.mkdir(parents=True, exist_ok=True)
    with open(CARDS, "a", encoding="utf-8") as f:
        f.write(json.dumps(card) + "\n")
    emit_ipc(f"{SLUG}.card.push", {"id": card.get("id")})
    print("card " + str(card.get("id")))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "beat":
        cmd_beat(sys.argv[2] if len(sys.argv) > 2 else "agent",
                 sys.argv[3] if len(sys.argv) > 3 else "")
    elif cmd == "next":
        cmd_next()
    elif cmd == "wait":
        to = float(sys.argv[2]) if len(sys.argv) > 2 else 25.0
        aid = sys.argv[3] if len(sys.argv) > 3 else "agent"
        cmd_wait(to, aid)
    elif cmd == "peek":
        cmd_peek()
    elif cmd == "reply":
        if len(sys.argv) < 4:
            print("usage: reply <reply_to_id> <text...>", file=sys.stderr)
            sys.exit(2)
        cmd_reply(sys.argv[2], " ".join(sys.argv[3:]))
    elif cmd == "card":
        cmd_card(" ".join(sys.argv[2:]))
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
