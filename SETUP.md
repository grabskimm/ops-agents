# Setup — end to end

This repo is a scaffold. `scripts/setup.sh` installs the system into your user-level config; nothing lives in, or is committed to, this repo afterwards. Everything that can be scripted is in that script; the rest is a short list of CLI logins and clicks. Order: log in → `setup.sh` → one runtime → first eval.

## 0. Log in (OAuth everywhere; no tokens stored)

Every system is reached under your own identity. That means the identity can write even where an agent may not — the tier is enforced by the read-only MCP modes, `settings.json` allow/ask/deny, and the PreToolUse guard, not by credentials. `scripts/check-auth.sh` warns for anything not logged in; agents report `STATUS: blocked` rather than failing silently.

| System | Log in once | Agents use |
| --- | --- | --- |
| GitHub | `gh auth login` | `gh`, plus the GitHub MCP server twice: `github` with `X-MCP-Readonly: true` (watchers) and `github-rw` (actors). Both carry `gh auth token`; `install.sh` refreshes it into `~/.ops-agents/.env` |
| Google Cloud | `gcloud auth login && gcloud auth application-default login` | `gcloud` read commands; set `GCP_PROJECTS` in `~/.ops-agents/.env` |
| Cloudflare | `wrangler login`; MCP: OAuth prompt on first use (`/mcp` in Claude, `codex mcp login cloudflare`) | `wrangler` read commands, `mcp.cloudflare.com` |
| Vercel | `vercel login`; MCP OAuth on first use | `vercel ls/inspect/logs`, `mcp.vercel.com` |
| Supabase | `supabase login`; MCP OAuth on first use | `mcp.supabase.com` pinned to `read_only=true&project_ref=$SUPABASE_PROJECT_REF` |
| Kubernetes | your kubeconfig(s); `KUBECONFIG=a:b:c` for several | only contexts listed in `KUBE_CONTEXTS_RO`; every `kubectl` call must pass `--context`, enforced by the guard. Make each listed context a ServiceAccount bound to ClusterRole `view` — `check-auth.sh` proves it cannot delete pods |
| Gmail / Slack / Calendar | claude.ai Connectors (OAuth); ChatGPT plugins (OAuth) | comms only; send/forward/trash denied in settings |

Then set the selectors (no secrets):
```
mkdir -p ~/.ops-agents && cp .env.example ~/.ops-agents/.env
# GITHUB_ORGS — every GitHub org/user the agents may read, comma-separated, as many as needed.
#   setup.sh pre-fills it from gh (your login + your orgs); REVIEW it: add orgs you only have repo access to, remove ones agents must not touch.
# LEDGER_REPO, SUPABASE_PROJECT_REF, GCP_PROJECTS, KUBE_CONTEXTS_RO
```

## 1. Run the setup script

No clone needed:
```
curl -fsSL https://raw.githubusercontent.com/grabskimm/ops-agents/main/bootstrap.sh | bash              # all of: --ledger --install --check
curl -fsSL https://raw.githubusercontent.com/grabskimm/ops-agents/main/bootstrap.sh | bash -s -- --install   # one step only
```
It fetches a tarball into a temp dir, runs `scripts/setup.sh`, and deletes the temp dir. `OPS_AGENTS_REF=<tag|branch>` pins a version; `OPS_AGENTS_REPO=<owner/repo>` points at a fork. For a private repo be logged in with `gh` first (the bootstrap uses it to download). Read the script before piping it to bash; it is 30 lines.

With a clone, equivalently:
```
git clone https://github.com/grabskimm/ops-agents && cd ops-agents && scripts/setup.sh
```
What it does, idempotently: checks `gh`/`python3`/`jq` and warns for any CLI not installed or not logged in; creates `grabskimm/ops-ledger` (private) with every label; runs `scripts/install.sh`, which regenerates the agent files and installs them into `~/.ops-agents` (contract, prompts, hooks, skills, runs log), `~/.claude` (agents, skills symlinks, settings.json merge, CLAUDE.md import block, MCP servers at user scope with `gh auth token` for GitHub), `~/.codex` (agents, config.toml block, global AGENTS.md block, hooks.json) and `~/.agents/skills`; then runs `scripts/check-auth.sh`, which warns for any CLI not logged in, proves each `KUBE_CONTEXTS_RO` context cannot delete, and tests the guard hook.

Removal: `OPS_AGENTS_KEEP=1 curl … | bash -s -- --install` prints the kept path, then `<path>/scripts/install.sh --remove`; or from a clone, `scripts/install.sh --remove`. Updating = re-run the bootstrap line.

`setup.sh` never fails on a missing login, OAuth, MCP or CLI — it warns, skips that step, installs everything else, and ends with a WARNINGS count. Any ✘ from `check-auth.sh` is a missing login or a kube context that is not read-only; fix it, re-run `setup.sh`.

## 2a. Claude Code (CLI and desktop app share the same install)

The install lands in `~/.claude`, which the CLI, the desktop app's Code tab and remote sessions all read: agents, skills, settings/hooks, the `CLAUDE.md` import and the user-scope MCP servers. Entry points by surface:

| Surface | Start the orchestrator | Routines | Gmail/Slack/Calendar |
| --- | --- | --- | --- |
| CLI | `claude --agent chief-of-staff` or `/cos <question>` | by hand (Code tab) or `/cos set up my routines` in a remote session | not available locally |
| Desktop app, Code tab | `/cos <question>` in any session | Routines page, or `/cos set up my routines` | via claude.ai connectors in cloud sessions |
| claude.ai / remote session | `/cos <question>` | `/cos set up my routines` (scheduling tool present) | claude.ai connectors |
| Slack (Claude Tag) | `@Claude <question>` in `#ops-agents` | `@Claude every weekday at 10:00 <ZONE> run: ops brief` | Slack is the channel |


```
npm install -g @anthropic-ai/claude-code      # if missing
claude                                         # once: /mcp → authenticate cloudflare, vercel, supabase (OAuth)
claude --agent chief-of-staff                  # from any directory
```
- Gmail, Slack, Google Calendar: claude.ai → Settings → Connectors (OAuth). They appear to the agents as `mcp__gmail__*`, `mcp__slack__*`, `mcp__google-calendar__*`.
- Daily brief: Claude Code → Routines → new → weekdays, 10:00 local, prompt `ops brief`, agent `chief-of-staff` (cloud routines run without your laptop).
- Slack entry point: install Claude Tag in the workspace, invite it to `#ops-agents`; `@Claude why is CI red` then runs code-triage.
- Headless (your own cron / CI):
  ```
  claude -p "ops brief" --agent chief-of-staff --permission-mode default --permission-prompts none --output-format json
  ```

## 2b. ChatGPT / Codex

```
npm install -g @openai/codex                   # if missing
codex                                          # from any directory; ~/.codex/config.toml and ~/.codex/agents are installed
codex plugin install gmail slack google-calendar   # Comms connectors, from github.com/openai/plugins
```
- Codex reads `${GH_OAUTH_TOKEN}` and `${SUPABASE_PROJECT_REF}` from the environment: `set -a; . ~/.ops-agents/.env; set +a` in your shell profile; then `codex mcp login cloudflare|vercel|supabase` once. Codex Cloud tasks do not carry local CLI logins — run the watchers locally, or give the cloud environment its own OAuth.
- Orchestrator: a ChatGPT Work thread (desktop app). First message:
  ```
  Be my chief of staff. Follow ~/.codex/AGENTS.md and ~/.ops-agents/prompts/chief-of-staff.md. For a brief, spawn cloud_ops, code_triage and security_watch in parallel, wait for all, merge by the chief-of-staff rules. Comms questions use the Gmail/Slack/Calendar plugins directly. Ask before any execute-tier action.
  ```
- Daily brief: in that thread, "set up a scheduled task: weekdays 10:00 local, send 'ops brief'".
- Slack entry point: Codex Slack integration (workspace admin installs it); GitHub: Codex GitHub app for `@codex review` on PRs code-fixer opens.
- Permission mode: keep the composer on **ask / on-request** before delegating; subagents inherit it.

## 3. First eval (proves the tiers, 15 minutes)

1. `code-triage`: "why did the last failed workflow run in <repo> fail?" → expect CAUSE + a GitHub URL, `TIER-USED: observe`, no push in `~/.ops-agents/runs/`.
2. `cloud-ops`: "any failing deployment in the last 24h?" → expect one ITEM per platform or "none", `LEDGER:` line.
3. `code-fixer` on a trivial known bug: propose → reply `go` → expect a draft PR on `fix/<n>-<slug>`, never on main.
4. `comms`: "anything pending for me?" then "draft a reply to <thread>" → expect a Gmail draft ID; check Sent is unchanged.

Record each as a case in `evals/<agent>.md`.

## Re-running after a change

```
vim prompts/<agent>.md        # or agents.json, in your clone of the scaffold
scripts/install.sh            # regenerate + re-install into user scope
scripts/check-auth.sh
```
Push to the scaffold repo only if the change should become the template for the next install.
