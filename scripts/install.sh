#!/usr/bin/env bash
# Install the orchestrating system from this scaffold into the operator's user-level config.
# Nothing is written back to this repo; it can be deleted after install (keep it to re-install after edits).
#
#   scripts/install.sh            install / update (idempotent; managed blocks are replaced, not duplicated)
#   scripts/install.sh --remove   remove everything this script installed
#
# Targets:
#   ~/.ops-agents/            AGENTS.md, hooks/, skills/, agents.json, prompts/, runs/   (the system's home)
#   ~/.claude/agents/*.md     Claude Code subagents (user scope)
#   ~/.claude/skills/<n>      symlinks -> ~/.ops-agents/skills/<n>
#   ~/.claude/settings.json   permissions + hooks merged in (managed keys only)
#   ~/.claude/CLAUDE.md       managed block importing ~/.ops-agents/AGENTS.md
#   ~/.claude.json            MCP servers at user scope, via `claude mcp add` when the CLI exists
#   ~/.codex/agents/*.toml    Codex custom agents (user scope)
#   ~/.codex/config.toml      managed block: [agents] + [mcp_servers.*] + approval/sandbox
#   ~/.codex/AGENTS.md        managed block with the shared contract (Codex global instructions)
#   ~/.codex/hooks.json       PreToolUse guard
#   ~/.agents/skills/<n>      symlinks -> ~/.ops-agents/skills/<n>   (Codex user skill root)
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:?}"
OPS="$HOME_DIR/.ops-agents"
MARK_B="# >>> ops-agents (managed) >>>"
MARK_E="# <<< ops-agents (managed) <<<"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

strip_block() { # file -> remove managed block
  [[ -f "$1" ]] || return 0
  awk -v b="$MARK_B" -v e="$MARK_E" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
append_block() { # file, content
  mkdir -p "$(dirname "$1")"; touch "$1"; strip_block "$1"
  { echo "$MARK_B"; printf '%s\n' "$2"; echo "$MARK_E"; } >> "$1"
}

if [[ "${1:-}" == "--remove" ]]; then
  echo "== removing"
  for f in "$SRC"/prompts/*.md; do n="$(basename "$f" .md)"; rm -f "$HOME_DIR/.claude/agents/$n.md" "$HOME_DIR/.codex/agents/$n.toml"; done
  for d in "$SRC"/skills/*/; do n="$(basename "$d")"; rm -f "$HOME_DIR/.claude/skills/$n" "$HOME_DIR/.agents/skills/$n"; done
  strip_block "$HOME_DIR/.claude/CLAUDE.md"; strip_block "$HOME_DIR/.codex/config.toml"; strip_block "$HOME_DIR/.codex/AGENTS.md"
  if [[ -f "$HOME_DIR/.claude/settings.json" ]]; then
    jq 'del(.permissions.ops_agents_managed) | .hooks |= with_entries(select(.value | tostring | test("ops-agents") | not)) | .permissions |= (.allow -= (.ops_agents_allow // []) | .ask -= (.ops_agents_ask // []) | .deny -= (.ops_agents_deny // []) | del(.ops_agents_allow,.ops_agents_ask,.ops_agents_deny))' "$HOME_DIR/.claude/settings.json" > "$HOME_DIR/.claude/settings.json.tmp" && mv "$HOME_DIR/.claude/settings.json.tmp" "$HOME_DIR/.claude/settings.json"
  fi
  if command -v claude >/dev/null 2>&1; then for s in github github-rw cloudflare vercel supabase; do claude mcp remove -s user "$s" >/dev/null 2>&1 || true; done; fi
  rm -f "$HOME_DIR/.codex/hooks.json"
  rm -rf "$OPS"
  ok "removed (runs log deleted with ~/.ops-agents)"; exit 0
fi

echo "== build"
python3 "$SRC/scripts/build-agents.py" >/dev/null && ok "agent files generated from prompts/ + agents.json"

echo "== ~/.ops-agents"
mkdir -p "$OPS/runs"
rm -rf "$OPS/hooks" "$OPS/skills" "$OPS/prompts"
cp -R "$SRC/hooks" "$OPS/hooks"; cp -R "$SRC/skills" "$OPS/skills"; cp -R "$SRC/prompts" "$OPS/prompts"; rm -rf "$OPS/schedules"; cp -R "$SRC/schedules" "$OPS/schedules"
cp "$SRC/AGENTS.md" "$OPS/AGENTS.md"; cp "$SRC/agents.json" "$OPS/agents.json"; cp "$SRC/.env.example" "$OPS/.env.example"
[[ -f "$OPS/.env" ]] || { cp "$SRC/.env.example" "$OPS/.env"; warn "$OPS/.env created from template — set SUPABASE_PROJECT_REF, GCP_PROJECTS, KUBE_CONTEXTS_RO"; }
chmod +x "$OPS"/hooks/*.sh
ok "contract, prompts, hooks, skills copied"

echo "== Claude Code (user scope)"
mkdir -p "$HOME_DIR/.claude/agents" "$HOME_DIR/.claude/skills"
cp "$SRC"/.claude/agents/*.md "$HOME_DIR/.claude/agents/"
for d in "$OPS"/skills/*/; do n="$(basename "$d")"; ln -sfn "$d" "$HOME_DIR/.claude/skills/$n"; done
ok "agents + skills installed"
append_block "$HOME_DIR/.claude/CLAUDE.md" "@$OPS/AGENTS.md
@$OPS/skills/ledger/SKILL.md"
ok "~/.claude/CLAUDE.md imports the shared contract"
# settings.json: merge managed permissions and hooks, remembering what we added so --remove can undo it.
S="$HOME_DIR/.claude/settings.json"; [[ -f "$S" ]] || echo '{}' > "$S"
jq --slurpfile m "$SRC/.claude/settings.json" --arg ops "$OPS" '
  def uniq: unique;
  ($m[0].permissions) as $p
  | .permissions.defaultMode = ($p.defaultMode // .permissions.defaultMode // "default")
  | .permissions.allow = (((.permissions.allow // []) - (.permissions.ops_agents_allow // [])) + $p.allow | uniq)
  | .permissions.ask   = (((.permissions.ask   // []) - (.permissions.ops_agents_ask   // [])) + $p.ask   | uniq)
  | .permissions.deny  = (((.permissions.deny  // []) - (.permissions.ops_agents_deny  // [])) + $p.deny  | uniq)
  | .permissions.ops_agents_allow = $p.allow | .permissions.ops_agents_ask = $p.ask | .permissions.ops_agents_deny = $p.deny
  | .hooks = ((.hooks // {}) | with_entries(select(.value | tostring | test("ops-agents") | not)))
  | .hooks.PreToolUse   = ((.hooks.PreToolUse   // []) + [{"matcher":"Bash|mcp__.*","hooks":[{"type":"command","command":($ops + "/hooks/guard-observe.sh")}]}])
  | .hooks.SubagentStop = ((.hooks.SubagentStop // []) + [{"matcher":"*","hooks":[{"type":"command","command":($ops + "/hooks/ledger-touch.sh")}]}])
' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
ok "settings.json: permissions + hooks merged (existing entries kept)"
set +e   # from here on: gh/MCP/OAuth steps warn, never abort
# GH_OAUTH_TOKEN comes from gh's OAuth login; written into ~/.ops-agents/.env for the MCP headers (re-run install after a new gh auth login).
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  tok="$(gh auth token 2>/dev/null || true)"
  if [[ -n "$tok" ]]; then
    touch "$OPS/.env"
    if grep -q '^GH_OAUTH_TOKEN=' "$OPS/.env"; then sed -i.bak "s#^GH_OAUTH_TOKEN=.*#GH_OAUTH_TOKEN=$tok#" "$OPS/.env"; rm -f "$OPS/.env.bak"; else echo "GH_OAUTH_TOKEN=$tok" >> "$OPS/.env"; fi
    chmod 600 "$OPS/.env"; ok "GH_OAUTH_TOKEN refreshed from gh auth token"
  fi
else warn "gh not logged in — GitHub MCP servers will fail until: gh auth login && scripts/install.sh"; fi
set -a; [[ -f "$OPS/.env" ]] && source "$OPS/.env" 2>/dev/null; set +a
if command -v claude >/dev/null 2>&1; then
  for s in github github-rw cloudflare vercel supabase; do claude mcp remove -s user "$s" >/dev/null 2>&1 || true; done
  claude mcp add -s user -t http github     https://api.githubcopilot.com/mcp/ -H "Authorization: Bearer ${GH_OAUTH_TOKEN:-UNSET}" -H "X-MCP-Readonly: true" >/dev/null 2>&1 && ok "mcp github (read-only header)" || warn "mcp github failed"
  claude mcp add -s user -t http github-rw  https://api.githubcopilot.com/mcp/ -H "Authorization: Bearer ${GH_OAUTH_TOKEN:-UNSET}" >/dev/null 2>&1 && ok "mcp github-rw" || warn "mcp github-rw failed"
  claude mcp add -s user -t http cloudflare https://mcp.cloudflare.com/mcp >/dev/null 2>&1 && ok "mcp cloudflare (OAuth on first use)" || warn "mcp cloudflare failed"
  claude mcp add -s user -t http vercel     https://mcp.vercel.com >/dev/null 2>&1 && ok "mcp vercel (OAuth on first use)" || warn "mcp vercel failed"
  claude mcp add -s user -t http supabase   "https://mcp.supabase.com/mcp?read_only=true&project_ref=${SUPABASE_PROJECT_REF:-UNSET}" >/dev/null 2>&1 && ok "mcp supabase read_only (OAuth on first use)" || warn "mcp supabase failed"
  echo "  finish OAuth: start claude, run /mcp, authenticate cloudflare, vercel, supabase once"
else
  warn "claude CLI not found; MCP servers not registered. Install, then re-run."
fi

set -e
echo "== Codex (user scope)"
mkdir -p "$HOME_DIR/.codex/agents" "$HOME_DIR/.agents/skills"
cp "$SRC"/.codex/agents/*.toml "$HOME_DIR/.codex/agents/"
for d in "$OPS"/skills/*/; do n="$(basename "$d")"; ln -sfn "$d" "$HOME_DIR/.agents/skills/$n"; done
append_block "$HOME_DIR/.codex/config.toml" "$(sed -e '/^#/d' -e '/^$/d' "$SRC/.codex/config.toml")"
append_block "$HOME_DIR/.codex/AGENTS.md" "$(cat "$SRC/AGENTS.md")"
sed "s#hooks/guard-observe.sh#$OPS/hooks/guard-observe.sh#" "$SRC/.codex/hooks.json" > "$HOME_DIR/.codex/hooks.json"
ok "agents, skills, config block, global AGENTS.md block, hooks installed"
echo "  Codex reads \${GH_OAUTH_TOKEN} and \${SUPABASE_PROJECT_REF} from the environment: add  set -a; . $OPS/.env; set +a  to your shell profile."
echo "  then once:  codex mcp login cloudflare && codex mcp login vercel && codex mcp login supabase"

echo "done. Start anywhere with:  claude --agent chief-of-staff   |   codex"
