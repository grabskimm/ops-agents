#!/usr/bin/env bash
# End-to-end setup for ops-agents. Idempotent: re-run any time.
# Usage: scripts/setup.sh [--claude] [--codex] [--ledger] [--all]   (default: --all)
# Needs: gh (authenticated as the operator), python3, jq. Optional: claude, codex, gcloud, kubectl, npx.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${ORG:-grabskimm}"
LEDGER="${LEDGER:-$ORG/ops-ledger}"
DO_CLAUDE=0; DO_CODEX=0; DO_LEDGER=0
[[ $# -eq 0 ]] && set -- --all
for a in "$@"; do case "$a" in
  --all) DO_CLAUDE=1; DO_CODEX=1; DO_LEDGER=1;;
  --claude) DO_CLAUDE=1;; --codex) DO_CODEX=1;; --ledger) DO_LEDGER=1;;
  *) echo "unknown flag $a"; exit 1;;
esac; done

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 — $2"; exit 1; }; }

echo "== prerequisites"
need gh "https://cli.github.com"; need python3 "python 3.11+"; need jq "https://jqlang.github.io/jq"
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }
ok "gh authenticated as $(gh api user --jq .login)"
for c in claude codex gcloud kubectl npx; do command -v "$c" >/dev/null 2>&1 && ok "$c found" || warn "$c not installed (optional)"; done

echo "== environment"
if [[ -f .env ]]; then set -a; source .env; set +a; ok ".env loaded"; else warn ".env missing — copy .env.example and fill tokens (connectors will fail until then)"; fi

echo "== generated agent files"
python3 scripts/build-agents.py >/dev/null && ok ".claude/agents and .codex/agents regenerated"
chmod +x hooks/*.sh scripts/*.sh scripts/*.py
mkdir -p .agents; ln -sfn ../skills .claude/skills; ln -sfn ../skills .agents/skills; ok "skills symlinked for both runtimes"

if [[ $DO_LEDGER -eq 1 ]]; then
  echo "== ledger: $LEDGER"
  if ! gh repo view "$LEDGER" >/dev/null 2>&1; then
    gh repo create "$LEDGER" --private --description "Task ledger for ops-agents" >/dev/null && ok "created $LEDGER"
  else ok "$LEDGER exists"; fi
  mk() { gh label create "$1" -R "$LEDGER" --color "$2" --description "$3" --force >/dev/null; }
  for a in chief-of-staff comms cloud-ops code-triage security-watch code-fixer infra-builder skills-librarian; do mk "agent/$a" 0075ca "owner agent"; done
  for t in observe propose execute; do mk "tier/$t" 5319e7 "tier used"; done
  for s in open waiting-human running done; do mk "state/$s" e4e669 "task state"; done
  for s in gmail slack gcp cf supabase vercel github; do mk "src/$s" bfd4f2 "source system"; mk "sec/$s" d93f0b "security finding source"; done
  ok "labels ensured"
  if [[ "$(gh issue list -R "$LEDGER" --search 'daily brief log in:title' --state all --json number --jq length)" == "0" ]]; then
    gh issue create -R "$LEDGER" --title "daily brief log" --label agent/chief-of-staff --body "chief-of-staff comments here after every brief. Newest comment = baseline window for the next run." >/dev/null
    ok "issue 'daily brief log' created"
  else ok "issue 'daily brief log' exists"; fi
  n="$(gh issue list -R "$LEDGER" --search 'daily brief log in:title' --state all --json number --jq '.[0].number')"
  [[ "$n" != "1" ]] && warn "daily brief log is issue #$n, not #1 — update prompts/chief-of-staff.md and skills/ledger/SKILL.md"
fi

if [[ $DO_CLAUDE -eq 1 ]]; then
  echo "== Claude Code"
  python3 -c "import json;json.load(open('.claude/settings.json'));json.load(open('.mcp.json'))" && ok "settings.json / .mcp.json parse"
  if command -v claude >/dev/null 2>&1; then
    claude mcp list 2>/dev/null | grep -q . && ok "claude mcp list runs (project .mcp.json is picked up when you start claude in this dir; approve the servers on first run)" || warn "claude mcp list returned nothing — start 'claude' here once and approve the project MCP servers"
    echo "  next: claude --agent chief-of-staff   (in this directory)"
  else warn "claude CLI not found: npm install -g @anthropic-ai/claude-code"; fi
  echo "  connectors (Gmail, Slack, Google Calendar) are attached in claude.ai Settings → Connectors; they appear as mcp__gmail__*, mcp__slack__*, mcp__google-calendar__* in cloud sessions"
  echo "  daily brief: create a routine in Claude Code (cloud) — weekdays 10:00 local, prompt 'morning brief', agent chief-of-staff"
fi

if [[ $DO_CODEX -eq 1 ]]; then
  echo "== Codex"
  python3 -c "import tomllib,glob;[tomllib.load(open(f,'rb')) for f in glob.glob('.codex/**/*.toml',recursive=True)]" && ok ".codex/*.toml parse"
  if command -v codex >/dev/null 2>&1; then
    ok "codex CLI found; .codex/config.toml and .codex/agents are read from this directory"
    echo "  next: codex   (in this directory) → 'morning brief — spawn cloud_ops, code_triage, security_watch in parallel, wait, merge by chief-of-staff rules'"
  else warn "codex CLI not found: npm install -g @openai/codex"; fi
  echo "  connectors (Gmail, Slack, Google Calendar) are plugins from github.com/openai/plugins: codex plugin install gmail|slack|google-calendar"
  echo "  daily brief: ChatGPT Work scheduled task, weekdays 10:00 local, prompt 'morning brief', in a thread with this repo open"
fi

echo "== token tiers"
scripts/check-tokens.sh || warn "token check reported problems (see above)"
echo "done."
