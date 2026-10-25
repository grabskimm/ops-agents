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

# 1. Always-blocked patterns, every tier (belt and braces with settings.json deny).
always_block='(git push[^|;&]*(main|master|--force|-f\b))|terraform (apply|destroy)|kubectl (apply|delete|rollout|scale|edit|patch)|helm (install|upgrade|uninstall)|wrangler (deploy|publish)|vercel (deploy|--prod|env )|gcloud [^|;&]*(create|delete|update|deploy)|gcloud iam |gh pr merge|gh api -X (POST|PUT|PATCH|DELETE)'
if [[ "$tool" == "Bash" && "$cmd" =~ $always_block ]]; then
  echo "guard-observe: '$cmd' is a mutating command; never allowed from an agent. Propose it in the ledger instead." >&2
  exit 2
fi

# 2. Observe tier: block any write-shaped command or MCP tool.
if [[ $is_observe -eq 1 ]]; then
  observe_block='git (push|commit|checkout -b|merge|rebase|reset)|gh (pr|issue) (create|edit|close|comment)|>\s*[^/]|tee |rm |mv |chmod |npm (publish|install)|pip install'
  if [[ "$tool" == "Bash" && "$cmd" =~ $observe_block ]]; then
    echo "guard-observe: agent '$agent' is observe-tier; '$cmd' writes. Report it as an ITEM with action=approve." >&2
    exit 2
  fi
  case "$tool" in
    Write|Edit|NotebookEdit|mcp__github-rw__*|mcp__gmail__send_message|mcp__gmail__reply|mcp__gmail__forward|mcp__gmail__trash_*|mcp__*__create_*|mcp__*__update_*|mcp__*__delete_*|mcp__*__send_*)
      # Ledger writes are the one exception: issue create/comment on ops-ledger via the read MCP server.
      if [[ "$tool" == mcp__github__* ]] && printf '%s' "$input" | jq -e '.tool_input | tostring | test("ops-ledger")' >/dev/null; then
        exit 0
      fi
      echo "guard-observe: agent '$agent' is observe-tier; tool '$tool' mutates." >&2
      exit 2
      ;;
  esac
fi

exit 0
