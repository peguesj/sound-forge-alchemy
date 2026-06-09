# Sound Forge Alchemy (sfa) — Project Instructions

> **This is the canonical Sound Forge Alchemy codebase.** The React/Vite/Express prototype that this Phoenix app was ported from lives at `~/Developer/sound-forge-alchemy`. See `.claude/CLAUDE.md` for the full domain context and architecture.

## Resume Parity (cross-repo)

This repo and `~/Developer/sound-forge-alchemy` are two repos representing **one logical project**. Running `resume` in either directory should land Claude Code, Cursor, Aider, or any other copilot on the same project state. The bridge mechanism:

- **Auto-memory MEMORY.md** mirrors a `cross-repo-pointer` entry in both `~/.claude/projects/-Users-jeremiah-Developer-sfa/memory/` and `~/.claude/projects/-Users-jeremiah-Developer-sound-forge-alchemy/memory/`.
- **Project CLAUDE.md** in both repos explicitly names the other and identifies which is canonical (this one).
- **`AGENTS.md`** + `.vscode-copilot-instructions.md` + `.vscode-copilot-unified-instructions.md` (already in this repo) extend the same anchors to non-Claude tools.

When in doubt about which repo a task belongs in:
- Phoenix / Elixir / LiveView / Oban / Ecto / Demucs / librosa / lalal.ai → here (`~/Developer/sfa`)
- React / Vite / Express / TypeScript microservices / `alchemy2/` refactor experiment → sister repo (`~/Developer/sound-forge-alchemy`)

## Authoritative Pointers

- **Stack & architecture**: `.claude/CLAUDE.md` (domain, Phoenix 1.8 patterns, Demucs/librosa interop, Oban queues, Ecto schemas).
- **Multi-AI tool instructions**: `AGENTS.md`, `.vscode-copilot-instructions.md`, `.vscode-copilot-unified-instructions.md`.
- **UPM source of truth**: `prd.json` at repo root. Branch-scoped PRDs in `.ralph/<branch>/prd.json`.
- **Competitive intel**: `.claude/COMPETITIVE_ANALYSIS_SAMPLAB.md`.
- **Plane PM**: workspace `lgtm`, project id `6f35c181-4a86-476d-bb2a-fba869f68918`, identifier `SFA` — all 387 historical issues originate from this repo.

## Quick Commands

```bash
source .env && mix phx.server      # start Phoenix
mix test                            # run tests
mix compile --warnings-as-errors    # required before /upm ship
```

## Attribution Policy

Never include `Generated with Claude Code`, `Co-Authored-By: Claude`, `🤖`, or any AI/Claude attribution in commits, PRs, issue comments, or other externally-submitted content. Hard rule, no exceptions.
