#!/usr/bin/env bash
# SubagentStop hook: append the subagent's STATUS/LEDGER lines to a local run log so the task list
# stays current even when a run is cut short. Posting to the ledger issue is left to the agent
# (it needs the operator's "ask" approval for gh issue comment); this file is the fallback record.
set -euo pipefail

input="$(cat)"
agent="$(printf '%s' "$input" | jq -r '.agent_name // .subagent_type // .agent // "unknown"')"
last="$(printf '%s' "$input" | jq -r '.last_message // .output // .result // empty')"

logdir="${CLAUDE_PROJECT_DIR:-.}/.runs"
mkdir -p "$logdir"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "## $ts $agent"
  printf '%s\n' "$last" | grep -E '^(STATUS|TIER-USED|LEDGER|NEXT):' || echo "STATUS: unknown (no output block)"
  echo
} >> "$logdir/$(date -u +%Y-%m-%d).md"

exit 0
