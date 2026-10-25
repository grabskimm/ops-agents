#!/usr/bin/env bash
# Verify every CLI the agents rely on is logged in (OAuth), that each read-only kube context really is
# read-only, and that the tier guard blocks. Warns, never prompts. Exit 1 on any ✘.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"; OPS="${OPS_AGENTS_HOME:-$HOME/.ops-agents}"
[[ -f "$OPS/.env" ]] && { set -a; source "$OPS/.env"; set +a; }
fail=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; fail=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "GitHub (gh)"
if have gh; then
  if who="$(gh api user --jq .login 2>/tmp/gh_err.$$)"; then ok "logged in as $who"
  else bad "cannot reach github.com as you ($(head -c 200 /tmp/gh_err.$$ | tr '\n' ' ')) → unset GH_TOKEN; gh auth login -h github.com"; fi; rm -f /tmp/gh_err.$$
  [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]] && warn "GH_TOKEN/GITHUB_TOKEN set in this shell — gh is using it, not your OAuth login"
  [[ -n "${GITHUB_ORGS:-}" ]] && ok "GITHUB_ORGS=$GITHUB_ORGS" || bad "GITHUB_ORGS not set in $OPS/.env"
  IFS=, read -ra orgs <<< "${GITHUB_ORGS:-}"; for o in "${orgs[@]}"; do [[ -z "$o" ]] && continue; gh api "users/$o" --jq .login >/dev/null 2>&1 && ok "$o reachable" || bad "$o not reachable as $(gh api user --jq .login 2>/dev/null) — wrong account? gh auth switch -u <user>"; done
  n="$(gh auth status 2>&1 | grep -c 'Logged in to github.com account' || true)"; [[ "${n:-0}" -gt 1 ]] && warn "$n gh accounts on github.com; agents use the ACTIVE one — gh auth switch -u <user> before a run, or list them in GH_ACCOUNTS"
  gh auth status -h github.com 2>&1 | grep -q 'Token scopes' && warn "$(gh auth status -h github.com 2>&1 | grep -o 'Token scopes:.*' | head -1) — the identity can write; tier is enforced by X-MCP-Readonly, settings.json and the guard hook"
else bad "gh not installed"; fi

echo "Google Cloud (gcloud)"
if have gcloud; then
  acct="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)"
  [[ -n "$acct" ]] && ok "active account $acct" || bad "no active account → gcloud auth login"
  gcloud auth application-default print-access-token >/dev/null 2>&1 && ok "ADC present" || warn "no ADC → gcloud auth application-default login (needed by SDK-based tools)"
  [[ -n "${GCP_PROJECTS:-}" ]] || warn "GCP_PROJECTS not set in $OPS/.env — cloud-ops will ask which project"
else warn "gcloud not installed"; fi

echo "Cloudflare (wrangler)"
if have wrangler; then wrangler whoami >/dev/null 2>&1 && ok "logged in" || bad "not logged in → wrangler login"; else warn "wrangler not installed (MCP OAuth still works)"; fi

echo "Vercel (vercel)"
if have vercel; then vercel whoami >/dev/null 2>&1 && ok "logged in as $(vercel whoami 2>/dev/null)" || bad "not logged in → vercel login"; else warn "vercel not installed (MCP OAuth still works)"; fi

echo "Supabase (supabase)"
if have supabase; then supabase projects list >/dev/null 2>&1 && ok "logged in" || bad "not logged in → supabase login"; else warn "supabase CLI not installed (MCP OAuth still works)"; fi
[[ -n "${SUPABASE_PROJECT_REF:-}" ]] && ok "SUPABASE_PROJECT_REF=$SUPABASE_PROJECT_REF" || warn "SUPABASE_PROJECT_REF not set — the read-only Supabase MCP needs it"
grep -q 'read_only=true' "$SRC/.mcp.json" "$SRC/.codex/config.toml" && ok "Supabase MCP pinned to read_only=true in both configs" || bad "read_only=true missing from an MCP config"

echo "Kubernetes (kubectl, contexts)"
if have kubectl; then
  all="$(kubectl config get-contexts -o name 2>/dev/null | tr '\n' ' ')"
  [[ -n "$all" ]] && ok "contexts: $all" || bad "no kube contexts — set KUBECONFIG to your kubeconfig file(s)"
  if [[ -z "${KUBE_CONTEXTS_RO:-}" ]]; then bad "KUBE_CONTEXTS_RO not set in $OPS/.env — agents cannot run kubectl at all until it lists read-only contexts"
  else
    IFS=, read -ra ctxs <<< "$KUBE_CONTEXTS_RO"
    for c in "${ctxs[@]}"; do
      kubectl config get-contexts "$c" >/dev/null 2>&1 || { bad "context '$c' not found"; continue; }
      kubectl --context "$c" auth can-i get pods >/dev/null 2>&1 && ok "$c: can get pods" || bad "$c: cannot get pods"
      if kubectl --context "$c" auth can-i delete pods >/dev/null 2>&1; then bad "$c: can DELETE pods — not read-only; bind a ServiceAccount to ClusterRole view and point this context at it"; else ok "$c: cannot delete pods"; fi
    done
  fi
else warn "kubectl not installed"; fi

echo "Guard hook"
h="$OPS/hooks/guard-observe.sh"; [[ -x "$h" ]] || h="$SRC/hooks/guard-observe.sh"
echo '{"tool_name":"Bash","tool_input":{"command":"terraform apply"}}' | OPS_AGENT_NAME=infra-builder "$h" >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "blocks terraform apply" || bad "did not block terraform apply"
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}' | OPS_AGENT_NAME=code-triage "$h" >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "blocks observe-tier gh pr create" || bad "did not block observe-tier write"
echo '{"tool_name":"Bash","tool_input":{"command":"kubectl get pods"}}' | OPS_AGENT_NAME=cloud-ops "$h" >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "blocks kubectl without --context" || bad "did not block kubectl without --context"

echo "Claude Code MCP (OAuth)"
if have claude; then
  claude mcp list 2>/dev/null | grep -qi 'cloudflare' && ok "servers registered at user scope; complete OAuth for cloudflare/vercel/supabase on first use (claude → /mcp)" || warn "run scripts/install.sh, then open claude and finish OAuth under /mcp"
else warn "claude CLI not installed"; fi
echo "Codex MCP (OAuth)"
have codex && ok "codex found: run 'codex mcp login cloudflare', 'codex mcp login vercel', 'codex mcp login supabase' once" || warn "codex CLI not installed"

exit $fail
