#!/usr/bin/env bash
# End-to-end setup. This repo is a scaffold: everything is installed into the operator's user-level
# config (~/.ops-agents, ~/.claude, ~/.codex, ~/.agents) and nothing is committed back here.
# Usage: scripts/setup.sh [--ledger] [--install] [--check] [--all]   (default: --all). Idempotent.
# Hard requirements: python3, jq. Everything else (gh login, OAuth, MCP, CLIs) only warns and the step is skipped.
# Always exits 0; the WARNINGS count at the end tells you what is left.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OPS="${OPS_AGENTS_HOME:-$HOME/.ops-agents}"
# Org and ledger come from ~/.ops-agents/.env (GITHUB_ORGS, LEDGER_REPO); env vars ORG / LEDGER override; last resort = the gh login.
[[ -f "$OPS/.env" ]] && { set -a; . "$OPS/.env" 2>/dev/null; set +a; }
ORG="${ORG:-${GITHUB_ORGS%%,*}}"; LEDGER="${LEDGER:-${LEDGER_REPO:-}}"
DO_LEDGER=0; DO_INSTALL=0; DO_CHECK=0
[[ $# -eq 0 ]] && set -- --all
for a in "$@"; do case "$a" in
  --all) DO_LEDGER=1; DO_INSTALL=1; DO_CHECK=1;;
  --ledger) DO_LEDGER=1;; --install) DO_INSTALL=1;; --check) DO_CHECK=1;;
  *) echo "unknown flag $a"; exit 1;;
esac; done
WARNINGS=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing hard requirement: $1 — $2"; exit 1; }; }
gh_login() { # prints the login on success; exit 1 with gh's reason on failure
  local who; who="$(gh api user --jq .login 2>"${TMPDIR:-/tmp}/gh_err.$$")" && { printf '%s' "$who"; rm -f "${TMPDIR:-/tmp}/gh_err.$$"; return 0; }
  GH_ERR="$(head -c 300 "${TMPDIR:-/tmp}/gh_err.$$" 2>/dev/null | tr '\n' ' ')"; rm -f "${TMPDIR:-/tmp}/gh_err.$$"; return 1
}

echo "== prerequisites"
need python3 "python 3.11+"; need jq "https://jqlang.github.io/jq"
GH_OK=0
if ! command -v gh >/dev/null 2>&1; then warn "gh not installed (https://cli.github.com) — ledger creation and GitHub MCP registration skipped"
elif who="$(gh_login)"; then GH_OK=1; ok "gh authenticated as $who"; ORG="${ORG:-$who}"; LEDGER="${LEDGER:-$ORG/ops-ledger}"
else warn "gh cannot reach github.com as you (${GH_ERR:-no detail}) — try: unset GH_TOKEN; gh auth login -h github.com. Ledger step and GitHub MCP registration skipped"; fi
[[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]] && warn "GH_TOKEN/GITHUB_TOKEN is set in this shell; gh uses it instead of your OAuth login"
for c in claude codex gcloud wrangler vercel supabase kubectl; do command -v "$c" >/dev/null 2>&1 && ok "$c found" || warn "$c not installed — agents that need it will report STATUS: blocked"; done
echo "== OAuth logins (warn only; log in with each CLI, no tokens are stored)"
command -v gcloud >/dev/null && { [[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]] && ok "gcloud" || warn "gcloud auth login && gcloud auth application-default login"; }
command -v wrangler >/dev/null && { wrangler whoami >/dev/null 2>&1 && ok "wrangler" || warn "wrangler login"; }
command -v vercel >/dev/null && { vercel whoami >/dev/null 2>&1 && ok "vercel" || warn "vercel login"; }
command -v supabase >/dev/null && { supabase projects list >/dev/null 2>&1 && ok "supabase" || warn "supabase login"; }
mkdir -p "$OPS"
if [[ ! -f "$OPS/.env" ]]; then cp "$SRC/.env.example" "$OPS/.env"; warn "created $OPS/.env from template — set SUPABASE_PROJECT_REF, GCP_PROJECTS, KUBE_CONTEXTS_RO, then re-run"; fi

if [[ $DO_LEDGER -eq 1 && $GH_OK -eq 0 ]]; then warn "ledger step skipped: gh not logged in"; DO_LEDGER=0; fi
if [[ -z "${GITHUB_ORGS:-}" && $GH_OK -eq 1 ]]; then
  # Discover: your login + every org you belong to. Written as the PROPOSED list; review it.
  found="$who"; for o in $(gh api user/orgs --paginate --jq '.[].login' 2>/dev/null); do found="$found,$o"; done
  if grep -q '^GITHUB_ORGS=' "$OPS/.env"; then sed -i.bak "s#^GITHUB_ORGS=.*#GITHUB_ORGS=$found#" "$OPS/.env"; rm -f "$OPS/.env.bak"; else echo "GITHUB_ORGS=$found" >> "$OPS/.env"; fi
  GITHUB_ORGS="$found"; warn "GITHUB_ORGS pre-filled with your login + orgs ($found) — REVIEW it in $OPS/.env: add any other user/org the agents must read (comma-separated, as many as needed), remove what they must not touch"
elif [[ -z "${GITHUB_ORGS:-}" ]]; then warn "GITHUB_ORGS not set in $OPS/.env — list every GitHub org/user the agents may read, comma-separated (can be many)"; fi
if [[ $GH_OK -eq 1 ]]; then
  grep -q '^LEDGER_REPO=.\+' "$OPS/.env" 2>/dev/null || { sed -i.bak "s#^LEDGER_REPO=.*#LEDGER_REPO=$LEDGER#" "$OPS/.env" 2>/dev/null && rm -f "$OPS/.env.bak"; grep -q '^LEDGER_REPO=' "$OPS/.env" || echo "LEDGER_REPO=$LEDGER" >> "$OPS/.env"; ok "LEDGER_REPO=$LEDGER written to $OPS/.env"; }
fi
if [[ $DO_LEDGER -eq 1 ]]; then
  echo "== ledger: $LEDGER"
  if ! gh repo view "$LEDGER" >/dev/null 2>&1; then
    gh repo create "$LEDGER" --private --description "Task ledger for ops-agents" >/dev/null 2>&1 && ok "created $LEDGER" || warn "could not create $LEDGER (permissions?) — create it by hand"
  else ok "$LEDGER exists"; fi
  mk() { gh label create "$1" -R "$LEDGER" --color "$2" --description "$3" --force >/dev/null 2>&1 || warn "label $1 not created"; }
  for a in chief-of-staff comms cloud-ops code-triage security-watch code-fixer infra-builder skills-librarian; do mk "agent/$a" 0075ca "owner agent"; done
  for t in observe propose execute; do mk "tier/$t" 5319e7 "tier used"; done
  for s in open waiting-human running done; do mk "state/$s" e4e669 "task state"; done
  for s in gmail slack gcp cf supabase vercel github; do mk "src/$s" bfd4f2 "source system"; mk "sec/$s" d93f0b "security finding source"; done
  ok "labels ensured"
fi

if [[ $DO_INSTALL -eq 1 ]]; then
  echo "== install into user scope"
  "$SRC/scripts/install.sh" || warn "install.sh reported a problem (see above); re-run after fixing"
fi

if [[ $DO_CHECK -eq 1 ]]; then
  echo "== auth + tier guard"
  OPS_AGENTS_HOME="$OPS" "$SRC/scripts/check-auth.sh" || warn "auth check reported problems (see above)"
fi

cat <<EOF
== remaining manual steps
Selectors in $OPS/.env (re-run this script after editing):
  - GITHUB_ORGS: every GitHub org/user the agents may read — comma-separated, as many as needed (pre-filled from gh; review it)
  - LEDGER_REPO, GCP_PROJECTS, KUBE_CONTEXTS_RO, SUPABASE_PROJECT_REF
Claude Code (CLOUD profile — see docs/runtimes.md):
  - claude.ai → Settings → Connectors: Gmail, Slack, Google Calendar, GitHub; add custom connectors for Cloudflare, Vercel, Supabase (same MCP URLs)
  - cloud sessions open this repo (or your fork); set GITHUB_ORGS etc. as cloud environment variables or commit selectors.env to the fork
Claude Code (LOCAL profile):
  - routines: in a Claude app / Claude Code remote session say "set up my routines" (skill creates them); CLI-only → Routines page by hand from $OPS/schedules/routines.md
  - Slack: install Claude Tag, invite to #ops-agents
  - claude → /mcp → authenticate cloudflare, vercel, supabase (OAuth, once)
  - run:  claude --agent chief-of-staff   (CLI)   |   /cos <question>   (CLI, desktop app Code tab, remote sessions)
Codex:
  - codex plugin install gmail slack google-calendar
  - add  set -a; . $OPS/.env; set +a  to your shell profile (Codex reads \${GH_OAUTH_TOKEN}, \${SUPABASE_PROJECT_REF} from env)
  - codex mcp login cloudflare && codex mcp login vercel && codex mcp login supabase
  - ChatGPT Work thread: one scheduled task per row of $OPS/schedules/routines.md
  - Slack / GitHub: Codex Slack integration, Codex GitHub app
  - run:  codex     (from any directory)
EOF
echo "done. WARNINGS: $WARNINGS (each is a login, install or UI step still to do; nothing above was fatal)"
exit 0
