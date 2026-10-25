# ops-agents

Scaffold for an eight-agent daily working system: one orchestrator, four read-only watchers, three PR-only actors, one task ledger. Runs on Claude Code and on ChatGPT/Codex from the same prompts.

**This repo is a template, not a workspace.** One line installs it without keeping a clone:

```
curl -fsSL https://raw.githubusercontent.com/grabskimm/ops-agents/main/bootstrap.sh | bash
```

`scripts/setup.sh` installs the system into your user-level config (`~/.ops-agents`, `~/.claude`, `~/.codex`, `~/.agents`); agents then run from any directory. Nothing runs from, or commits back to, this repo — the only writes it ever receives are PRs from skills-librarian adding a skill.

```
bootstrap.sh           curl | bash entry point: fetch tarball → setup.sh → delete; flags pass through (`bash -s -- --install`)
AGENTS.md              shared contract (tiers, ledger, output block) → ~/.ops-agents/AGENTS.md, imported by ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md
agents.json            per-agent settings (model, tools, MCP servers) for both runtimes
prompts/<agent>.md     canonical prompt per agent — edit these; prompts/_template.md + scripts/new-agent.sh scaffold a new one
scripts/build-agents.py  generates .claude/agents/*.md and .codex/agents/*.toml from the two above
scripts/setup.sh       end to end: ledger repo + labels, install, auth checks, prints the manual steps
scripts/install.sh     installs into ~/.ops-agents, ~/.claude, ~/.codex, ~/.agents (idempotent; --remove undoes it)
scripts/check-auth.sh  warns for CLIs not logged in (OAuth), proves read-only kube contexts, tests the guard
.claude/               settings.json template (allow/ask/deny + hooks, merged into ~/.claude/settings.json), agents/ (generated → ~/.claude/agents)
.codex/                config.toml template (→ managed block in ~/.codex/config.toml), agents/ (generated → ~/.codex/agents), hooks.json
.mcp.json              Claude Code MCP servers, all OAuth (registered at user scope by install.sh via `claude mcp add`)
skills/<name>/SKILL.md shared skills → ~/.ops-agents/skills, symlinked from ~/.claude/skills and ~/.agents/skills
hooks/                 guard-observe.sh (PreToolUse tier guard), ledger-touch.sh (SubagentStop run log → ~/.ops-agents/runs)
evals/                 known-answer cases per agent
schedules/routines.md  the timer prompts the chief-of-staff handles (brief, sweep, stale check, PR nudge, retro); skills/routines creates them via the session's scheduling tool
.env.example           selectors only (project ref, GCP projects, read-only kube contexts) → ~/.ops-agents/.env
```

## Agents

| Agent | Tier | Owns |
| --- | --- | --- |
| chief-of-staff | route + merge | daily brief, "what's running", cross-domain questions |
| comms | observe → propose | Gmail, Slack, Calendar; drafts only |
| cloud-ops | observe | GCP, Cloudflare, Supabase, Vercel |
| code-triage | observe | GitHub code paths, CI failures, PR queue |
| security-watch | observe | alerts, secrets, RLS, WAF, IAM/env drift |
| code-fixer | propose → execute | app code → branch + PR |
| infra-builder | propose → execute | Terraform / Helm / Docker / k8s → branch + PR |
| skills-librarian | propose → execute | find / run / author skills |

## Enforcement, not prose

- Identity: everything runs under your OAuth logins (`gh`, `gcloud`, `wrangler`, `vercel`, `supabase`, kubeconfigs); no tokens stored. So the fence is the read-only MCP modes (`X-MCP-Readonly` on GitHub, `read_only=true` on Supabase), the allow/ask/deny lists, and the guard hook — `check-auth.sh` verifies them.
- Claude Code: per-agent `tools` / `disallowedTools` / `mcpServers`, `permissions.ask` on every push and PR, `hooks/guard-observe.sh` exits 2 on mutating commands from observe-tier agents and on any `kubectl` call that does not name a `KUBE_CONTEXTS_RO` context.
- Codex: `approval_policy = "on-request"` on the parent session, two GitHub MCP servers (read-only header vs full), agent prompts name which they may use.

## Run (from any directory, after `scripts/setup.sh`)

```
claude --agent chief-of-staff
codex       # then: "morning brief — spawn cloud_ops, code_triage, security_watch in parallel, wait, merge by chief-of-staff rules"
```
Headless daily brief:
```
claude -p "morning brief" --agent chief-of-staff --permission-mode default --permission-prompts none --output-format json
```

## Edit a prompt

1. Change `prompts/<agent>.md` (or a setting in `agents.json`) in a clone or fork of this scaffold.
2. `scripts/install.sh` — regenerates and re-installs into user scope (or push and re-run the bootstrap line, with `OPS_AGENTS_REPO=<fork>`).
3. Re-run that agent's `evals/` cases. Push to this repo only if the scaffold itself should change.

## Ledger

`grabskimm/ops-ledger` (GitHub Issues), created by `scripts/setup.sh --ledger` with labels `agent/*`, `tier/*`, `state/*`, `src/*`, `sec/*` and issue #1 "daily brief log". `skills/ledger/SKILL.md` has the commands.
