#!/usr/bin/env bash
# Prove each credential's tier. A read token that can write is a failed check.
# Reads .env if present. Exit 1 on any failure.
set -uo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && { set -a; source .env; set +a; }
ORG="${ORG:-grabskimm}"; LEDGER="${LEDGER:-$ORG/ops-ledger}"
fail=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; fail=1; }
skip() { printf '  \033[33m-\033[0m %s\n' "$*"; }

gh_code() { # token, method, path -> http status
  curl -s -o /dev/null -w '%{http_code}' -X "$2" -H "Authorization: Bearer $1" -H "Accept: application/vnd.github+json" "https://api.github.com$3"
}

echo "GitHub read token (GH_TOKEN_READ)"
if [[ -n "${GH_TOKEN_READ:-}" ]]; then
  [[ "$(gh_code "$GH_TOKEN_READ" GET /user)" == 200 ]] && ok "authenticates" || bad "cannot authenticate"
  # Attempt a write that must fail: create a label on the ledger with an invalid body still needs write scope to get past 403.
  c="$(gh_code "$GH_TOKEN_READ" POST "/repos/$LEDGER/labels")"
  [[ "$c" == 403 || "$c" == 404 ]] && ok "cannot write labels (HTTP $c)" || bad "write not blocked (HTTP $c) — token is not read-only"
  c="$(gh_code "$GH_TOKEN_READ" POST "/repos/$LEDGER/issues")"
  [[ "$c" == 422 || "$c" == 400 ]] && ok "can write ledger issues (HTTP $c = reached validation)" || bad "ledger issues:write missing (HTTP $c)"
else skip "GH_TOKEN_READ not set"; fi

echo "GitHub write token (GH_TOKEN_RW)"
if [[ -n "${GH_TOKEN_RW:-}" ]]; then
  [[ "$(gh_code "$GH_TOKEN_RW" GET /user)" == 200 ]] && ok "authenticates" || bad "cannot authenticate"
  repos="$(curl -s -H "Authorization: Bearer $GH_TOKEN_RW" "https://api.github.com/installation/repositories" 2>/dev/null | jq -r '.repositories[]?.full_name' 2>/dev/null)"
  [[ -n "$repos" ]] && ok "scoped to: $(echo "$repos" | tr '\n' ' ')" || skip "could not list scoped repos (fine for classic PATs; verify scope in GitHub settings)"
  echo "  reminder: branch protection on main must require PRs — the token cannot enforce that"
else skip "GH_TOKEN_RW not set"; fi

echo "Supabase (SUPABASE_PAT_RO)"
if [[ -n "${SUPABASE_PAT_RO:-}" && -n "${SUPABASE_PROJECT_REF:-}" ]]; then
  c="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $SUPABASE_PAT_RO" "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF")"
  [[ "$c" == 200 ]] && ok "reads project $SUPABASE_PROJECT_REF" || bad "cannot read project (HTTP $c)"
  grep -q -- '--read-only' .mcp.json .codex/config.toml && ok "--read-only flag present in both MCP configs" || bad "--read-only flag missing"
else skip "SUPABASE_PAT_RO / SUPABASE_PROJECT_REF not set"; fi

echo "Cloudflare (CLOUDFLARE_API_TOKEN)"
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify | jq -e '.success' >/dev/null && ok "token valid" || bad "token invalid"
  echo "  verify in the dashboard that every permission is *:Read"
else skip "CLOUDFLARE_API_TOKEN not set (OAuth via mcp.cloudflare.com is fine)"; fi

echo "Vercel (VERCEL_TOKEN)"
if [[ -n "${VERCEL_TOKEN:-}" ]]; then
  c="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $VERCEL_TOKEN" https://api.vercel.com/v2/user)"
  [[ "$c" == 200 ]] && ok "token valid" || bad "token invalid (HTTP $c)"
  echo "  the token inherits the member's role; the member must be Viewer"
else skip "VERCEL_TOKEN not set"; fi

echo "Google Cloud (GOOGLE_APPLICATION_CREDENTIALS)"
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "$GOOGLE_APPLICATION_CREDENTIALS" ]] && command -v gcloud >/dev/null; then
  sa="$(jq -r .client_email "$GOOGLE_APPLICATION_CREDENTIALS")"
  proj="$(jq -r .project_id "$GOOGLE_APPLICATION_CREDENTIALS")"
  roles="$(gcloud projects get-iam-policy "$proj" --flatten=bindings[].members --filter="bindings.members:serviceAccount:$sa" --format='value(bindings.role)' 2>/dev/null | tr '\n' ' ')"
  [[ -n "$roles" ]] && ok "$sa roles: $roles" || bad "cannot read IAM for $sa"
  echo "$roles" | grep -Eq 'roles/(owner|editor|iam\.securityAdmin)' && bad "service account holds a write role" || ok "no owner/editor role"
else skip "GOOGLE_APPLICATION_CREDENTIALS not set or gcloud missing"; fi

echo "Kubernetes (KUBECONFIG)"
if [[ -n "${KUBECONFIG:-}" ]] && command -v kubectl >/dev/null; then
  kubectl auth can-i get pods >/dev/null 2>&1 && ok "can get pods" || bad "cannot get pods"
  kubectl auth can-i delete pods >/dev/null 2>&1 && bad "can DELETE pods — kubeconfig is not read-only" || ok "cannot delete pods"
else skip "KUBECONFIG not set or kubectl missing"; fi

exit $fail
