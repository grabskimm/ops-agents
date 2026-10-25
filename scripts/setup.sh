#!/usr/bin/env bash
# End-to-end setup. This repo is a scaffold: everything is installed into the operator's user-level
# config (~/.ops-agents, ~/.claude, ~/.codex, ~/.agents) and nothing is committed back here.
# Usage: scripts/setup.sh [--ledger] [--install] [--check] [--all]   (default: --all). Idempotent.
# Needs: gh (authenticated as the operator), python3, jq. Optional: claude, codex, gcloud, kubectl, npx.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OPS="${OPS_AGENTS_HOME:-$HOME/.ops-agents}"
ORG="${ORG:-grabskimm}"; LEDGER="${LEDGER:-$ORG/ops-ledger}"
DO_LEDGER=0; DO_INSTALL=0; DO_CHECK=0
[[ $# -eq 0 ]] && set -- --all
for a in "$@"; do case "$a" in
  --all) DO_LEDGER=1; DO_INSTALL=1; DO_CHECK=1;;
  --ledger) DO_LEDGER=1;; --install) DO_INSTALL=1;; --check) DO_CHECK=1;;
  *) echo "unknown flag $a"; exit 1;;
esac; done
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 — $2"; exit 1; }; }

echo "== prerequisites"
need gh "https://cli.github.com"; need python3 "python 3.11+"; need jq "https://jqlang.github.io/jq"
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }
ok "gh authenticated as $(gh api user --jq .login)"
for c in claude codex gcloud wrangler vercel supabase kubectl; do command -v "$c" >/dev/null 2>&1 && ok "$c found" || warn "$c not installed — agents that need it will report STATUS: blocked"; done
echo "== OAuth logins (warn only; log in with each CLI, no tokens are stored)"
gh auth status >/dev/null 2>&1 && ok "gh" || warn "gh auth login"
command -v gcloud >/dev/null && { [[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]] && ok "gcloud" || warn "gcloud auth login && gcloud auth application-default login"; }
command -v wrangler >/dev/null && { wrangler whoami >/dev/null 2>&1 && ok "wrangler" || warn "wrangler login"; }
command -v vercel >/dev/null && { vercel whoami >/dev/null 2>&1 && ok "vercel" || warn "vercel login"; }
command -v supabase >/dev/null && { supabase projects list >/dev/null 2>&1 && ok "supabase" || warn "supabase login"; }
mkdir -p "$OPS"
if [[ ! -f "$OPS/.env" ]]; then cp "$SRC/.env.example" "$OPS/.env"; warn "created $OPS/.env from template — set SUPABASE_PROJECT_REF, GCP_PROJECTS, KUBE_CONTEXTS_RO, then re-run"; fi

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

if [[ $DO_INSTALL -eq 1 ]]; then
  echo "== install into user scope"
  "$SRC/scripts/install.sh"
fi

if [[ $DO_CHECK -eq 1 ]]; then
  echo "== auth + tier guard"
  OPS_AGENTS_HOME="$OPS" "$SRC/scripts/check-auth.sh" || warn "auth check reported problems (see above)"
fi

cat <<EOF
== remaining manual steps
Claude Code:
  - claude.ai → Settings → Connectors: Gmail, Slack, Google Calendar (OAuth)
  - Claude Code → Routines: create each row of $OPS/schedules/routines.md (prompt text verbatim, agent chief-of-staff)
  - Slack: install Claude Tag, invite to #ops-agents
  - claude → /mcp → authenticate cloudflare, vercel, supabase (OAuth, once)
  - run:  claude --agent chief-of-staff     (from any directory)
Codex:
  - codex plugin install gmail slack google-calendar
  - add  set -a; . $OPS/.env; set +a  to your shell profile (Codex reads \${GH_OAUTH_TOKEN}, \${SUPABASE_PROJECT_REF} from env)
  - codex mcp login cloudflare && codex mcp login vercel && codex mcp login supabase
  - ChatGPT Work thread: one scheduled task per row of $OPS/schedules/routines.md
  - Slack / GitHub: Codex Slack integration, Codex GitHub app
  - run:  codex     (from any directory)
done.
EOF
