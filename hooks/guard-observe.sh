#!/usr/bin/env bash
# PreToolUse guard: block mutating commands/tools when the active agent is observe-tier.
# Exit 2 = block (stderr is the reason shown to the model). Exit 0 = allow.
# Input: hook JSON on stdin (tool_name, tool_input, agent/session fields when present).
set -euo pipefail

OBSERVE_AGENTS="comms cloud-ops code-triage security-watch chief-of-staff"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
agent="$(printf '%s' "$input" | jq -r '.agent_name // .subagent_type // .agent // empty')"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

# Agent name may also be passed by the launcher.
agent="${agent:-${OPS_AGENT_NAME:-}}"

is_observe=0
for a in $OBSERVE_AGENTS; do
  [[ "$agent" == "$a" ]] && is_observe=1
done

# 0. kubectl: every call must name --context and it must be one of KUBE_CONTEXTS_RO (from ~/.ops-agents/.env).
if [[ "$tool" == "Bash" && "$cmd" =~ (^|[[:space:]|;&])kubectl([[:space:]]|$) ]]; then
  for envf in "${OPS_AGENTS_HOME:-$HOME/.ops-agents}/.env" "${CLAUDE_PROJECT_DIR:-.}/selectors.env"; do [[ -f "$envf" ]] && { set -a; source "$envf"; set +a; break; }; done
  if [[ "$cmd" =~ config[[:space:]]+(use-context|set-context|set-credentials|set-cluster) ]]; then
    echo "guard-observe: kubectl config changes are never allowed from an agent." >&2; exit 2; fi
  if [[ ! "$cmd" =~ config[[:space:]]+get-contexts ]]; then
    ctx="$(printf '%s' "$cmd" | grep -oE -- '--context[= ]+[^ ]+' | head -1 | sed -E 's/--context[= ]+//' || true)"
    [[ -z "$ctx" ]] && { echo "guard-observe: kubectl must name --context <one of: ${KUBE_CONTEXTS_RO:-unset}>." >&2; exit 2; }
    case ",${KUBE_CONTEXTS_RO:-}," in *",$ctx,"*) ;; *) echo "guard-observe: context '$ctx' is not in KUBE_CONTEXTS_RO." >&2; exit 2;; esac
  fi
fi

# 1. Always-blocked patterns, every tier (belt and braces with settings.json deny).
always_block='(git push[^|;&]*(main|master|--force|-f\b))|terraform (apply|destroy)([[:space:]]|$)|kubectl (apply|delete|rollout|scale|edit|patch|exec|cp)([[:space:]]|$)|helm (install|upgrade|uninstall|rollback)([[:space:]]|$)|wrangler (deploy([[:space:]]|$)|publish|secret|kv:key put|d1 execute|delete)|vercel (deploy([[:space:]]|$)|--prod|env |rm |remove )|supabase (db (push|reset)|secrets set|functions deploy)|gcloud [^|;&]* (create|delete|update|deploy|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding)([[:space:]]|$)|gcloud (iam |auth login|config set)|gh pr merge|gh api -X (POST|PUT|PATCH|DELETE)'
if [[ "$tool" == "Bash" && "$cmd" =~ $always_block ]]; then
  echo "guard-observe: '$cmd' is a mutating command; never allowed from an agent. Propose it in the ledger instead." >&2
  exit 2
fi

# 2. Observe tier: block any write-shaped command or MCP tool.
if [[ $is_observe -eq 1 ]]; then
  observe_block='(^|[[:space:]|;&(])(git (push|commit|checkout -b|merge|rebase|reset)|gh (pr|issue) (create|edit|close|comment)|tee|rm|rmdir|mv|cp|chmod|chown|touch|mkdir|sed -i|npm (publish|install)|pip install)([[:space:]]|$)|>[[:space:]]*[^/&]'
  if [[ "$tool" == "Bash" && "$cmd" =~ $observe_block ]]; then
    echo "guard-observe: agent '$agent' is observe-tier; '$cmd' writes. Report it as an ITEM with action=approve." >&2
    exit 2
  fi
  # chief-of-staff may write its brief files only.
  if [[ "$tool" == "Write" ]] && printf '%s' "$input" | jq -e '.tool_input.file_path | test("/.ops-agents/briefs/")' >/dev/null 2>&1; then exit 0; fi
  case "$tool" in
    Write|Edit|NotebookEdit|mcp__github-rw__*|mcp__gmail__send_message|mcp__gmail__reply|mcp__gmail__forward|mcp__gmail__trash_*|mcp__*__create_*|mcp__*__update_*|mcp__*__delete_*|mcp__*__send_*)
      echo "guard-observe: agent '$agent' is observe-tier; tool '$tool' mutates." >&2
      exit 2
      ;;
  esac
fi

exit 0
