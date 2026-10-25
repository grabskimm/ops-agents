#!/usr/bin/env bash
# Scaffold a new agent: prompts/<name>.md from the template + an agents.json entry, then rebuild.
# Usage: scripts/new-agent.sh <name> <tier> "<one-line description>" [mcp servers, comma-separated]
#   tier: observe | observe-propose | propose-execute
# Afterwards: edit prompts/<name>.md, add a routing line to prompts/chief-of-staff.md and a row to AGENTS.md,
# then scripts/install.sh (or push + re-run the bootstrap line).
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:?name}"; tier="${2:?tier}"; desc="${3:?description}"; mcps="${4:-}"
[[ "$name" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "name must be kebab-case"; exit 1; }
[[ -f "$SRC/prompts/$name.md" ]] && { echo "prompts/$name.md exists"; exit 1; }
jq -e --arg n "$name" '.agents[$n]' "$SRC/agents.json" >/dev/null 2>&1 && { echo "$name already in agents.json"; exit 1; }

case "$tier" in
  observe)         tier_json="observe";         tools='["Read","Grep","Glob","Bash"]'; dis='["Write","Edit","NotebookEdit"]'; model=sonnet; cmodel=gpt-6-luna; eff=high; feats='{"apps":false}'; gh_tools='"mcp__github__*"'; gh_mcp=github; codex_gh=github_ro;;
  observe-propose) tier_json="observe->propose"; tools='["Read","Grep","Glob"]';       dis='["Write","Edit","Bash"]';          model=sonnet; cmodel=gpt-6-luna; eff=medium; feats='{"shell_tool":false,"apps":false}'; gh_tools='"mcp__github__*"'; gh_mcp=github; codex_gh=github_ro;;
  propose-execute) tier_json="propose->execute"; tools='["Read","Grep","Glob","Bash","Write","Edit"]'; dis='["mcp__github__*"]'; model=opus; cmodel=gpt-6.1-sol; eff=medium; feats='{}'; gh_tools='"mcp__github-rw__*"'; gh_mcp=github-rw; codex_gh=github_rw;;
  *) echo "tier must be observe | observe-propose | propose-execute"; exit 1;;
esac

extra_tools=""; extra_mcp=""; extra_codex=""
IFS=, read -ra arr <<< "$mcps"
for m in "${arr[@]}"; do [[ -z "$m" ]] && continue; extra_tools+=",\"mcp__${m}__*\""; extra_mcp+=",\"$m\""; extra_codex+=",\"$m\""; done

tmp="$(mktemp)"
jq --arg n "$name" --arg d "$desc" --arg t "$tier_json" --arg model "$model" --arg cmodel "$cmodel" --arg eff "$eff" \
   --argjson tools "$(echo "$tools" | jq ". + [${gh_tools}${extra_tools}]")" --argjson dis "$dis" \
   --argjson mcp "$(echo "[\"$gh_mcp\"${extra_mcp}]")" --argjson feats "$feats" --argjson cmcp "$(echo "[\"$codex_gh\"${extra_codex}]")" '
  .agents[$n] = {
    description: $d, tier: $t,
    claude: { model: $model, tools: $tools, disallowedTools: $dis, mcpServers: $mcp, skills: ["ledger"], maxTurns: 40 },
    codex:  { model: $cmodel, model_reasoning_effort: $eff, features: $feats, allowed_mcp: $cmcp }
  }' "$SRC/agents.json" > "$tmp" && mv "$tmp" "$SRC/agents.json"

sed -e "s/<name>/$name/" -e "s/<observe | observe → propose | propose → execute>/${tier_json//->/ → }/" "$SRC/prompts/_template.md" > "$SRC/prompts/$name.md"
python3 "$SRC/scripts/build-agents.py" >/dev/null
cat <<EOF
created prompts/$name.md and agents.json entry ($tier_json); generated .claude/agents/$name.md and .codex/agents/$name.toml
next:
  1. fill in prompts/$name.md (every <placeholder>)
  2. add a routing line to prompts/chief-of-staff.md and a row to the Agents table in AGENTS.md
  3. if observe-tier, add "$name" to OBSERVE_AGENTS in hooks/guard-observe.sh
  4. scripts/install.sh   (or commit, push, re-run the bootstrap line)
  5. evals/$name.md with three known-answer cases
EOF
