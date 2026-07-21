#!/usr/bin/env bash
# serve.sh — portable launcher for the standalone IPC showcase engine.
#
# Canonical runner behind `/showcase --standalone --ipc`. Project-agnostic:
# auto-discovers handoff + claude-mem + prd from --root. Idempotent start,
# graceful stop, optional browser open. The chat *agent* is dispatched by the
# skill (a Claude agent), not here — this only owns the server process.
#
# Flags (all optional):
#   --port <N>        default 4510
#   --root <path>     project root (default: $PWD)
#   --project <slug>  label + chat-file scoping (default: basename of root)
#   --bind <addr>     default 127.0.0.1
#   --sources <csv>   limit cards: handoff,upm,apm,ipc,blocker,mem,agent
#   --open            open the browser after start
#   --stop            stop the server on <port> and exit
#   --status          print health + exit
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$HERE/showcase-serve.py"

# Defaults come from SHOWCASE_* env (so `npm start` can parameterize without
# flags); explicit flags below override them.
PORT="${SHOWCASE_PORT:-4510}"; ROOT="${SHOWCASE_ROOT:-$PWD}"
PROJECT="${SHOWCASE_PROJECT:-}"; BIND="${SHOWCASE_BIND:-127.0.0.1}"
SOURCES="${SHOWCASE_SOURCES:-}"
OPEN=0; STOP=0; STATUS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --root) ROOT="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --bind) BIND="$2"; shift 2;;
    --sources) SOURCES="$2"; shift 2;;
    --open) OPEN=1; shift;;
    --stop) STOP=1; shift;;
    --status) STATUS=1; shift;;
    *) shift;;  # ignore unknown (skill passes engine/npm flags it handles itself)
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
[ -z "$PROJECT" ] && PROJECT="$(basename "$ROOT")"
LOG="$HOME/.ccem/logs/${PROJECT}-showcase.log"
IPC="$HOME/.ccem/bin/ccem-ipc.sh"
mkdir -p "$HOME/.ccem/logs" "$HOME/.ccem/state" 2>/dev/null

health() { curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api/health" 2>/dev/null; }

if [ "$STATUS" = 1 ]; then
  if health; then curl -fsS "http://127.0.0.1:${PORT}/api/health"; echo; else echo "down on :${PORT}"; fi
  exit 0
fi

if [ "$STOP" = 1 ]; then
  PIDS="$(lsof -ti:"$PORT" 2>/dev/null)"
  [ -n "$PIDS" ] && kill $PIDS 2>/dev/null && echo "stopped :${PORT}" || echo "nothing on :${PORT}"
  [ -x "$IPC" ] && "$IPC" emit "showcase.standalone.stop" "{\"port\":${PORT},\"project\":\"${PROJECT}\"}" >/dev/null 2>&1 &
  exit 0
fi

if health; then
  echo "showcase: already running on :${PORT} (project=${PROJECT})"
  [ "$OPEN" = 1 ] && command -v open >/dev/null && open "http://127.0.0.1:${PORT}"
  exit 0
fi

ARGS=(--port "$PORT" --root "$ROOT" --project "$PROJECT" --bind "$BIND")
[ -n "$SOURCES" ] && ARGS+=(--sources "$SOURCES")
if command -v setsid >/dev/null 2>&1; then
  setsid python3 "$SERVER" "${ARGS[@]}" >"$LOG" 2>&1 &
else
  nohup python3 "$SERVER" "${ARGS[@]}" >"$LOG" 2>&1 &
fi
PID=$!
sleep 1
if health; then
  echo "showcase: started http://${BIND}:${PORT} (project=${PROJECT}, pid=${PID})"
  [ -x "$IPC" ] && "$IPC" emit "showcase.standalone.start" "{\"port\":${PORT},\"project\":\"${PROJECT}\",\"pid\":${PID}}" >/dev/null 2>&1 &
  [ "$OPEN" = 1 ] && command -v open >/dev/null && open "http://127.0.0.1:${PORT}"
  exit 0
else
  echo "showcase: FAILED to start — see $LOG" >&2; exit 1
fi
