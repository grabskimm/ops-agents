# ops-agents

Eight-agent daily working system for a platform engineer: one orchestrator, four read-only watchers, three PR-only actors, one task ledger. Runs on Claude Code and on ChatGPT/Codex from the same prompts.

```
AGENTS.md              shared contract (tiers, ledger, output block); CLAUDE.md just @imports it
agents.json            per-agent settings (model, tools, MCP servers) for both runtimes
prompts/<agent>.md     canonical prompt per agent — edit these
scripts/build-agents.py  generates .claude/agents/*.md and .codex/agents/*.toml from the two above
.claude/               settings.json (allow/ask/deny + hooks), agents/ (generated), rules/, skills -> ../skills
.codex/                config.toml (mcp_servers, approval_policy), agents/ (generated), hooks.json
.agents/skills -> ../skills   Codex skill root; same SKILL.md folders
skills/<name>/SKILL.md shared skills (ledger first)
hooks/                 guard-observe.sh (PreToolUse tier guard), ledger-touch.sh (SubagentStop run log)
evals/                 known-answer cases per agent
.mcp.json              Claude Code MCP servers (two GitHub entries: read token / write token)
.env.example           every credential, with its minimum scope
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

- Tokens: watchers hold read-only credentials; actors hold a write token scoped to named repos. `.env.example` lists each scope.
- Claude Code: per-agent `tools` / `disallowedTools` / `mcpServers`, `permissions.ask` on every push and PR, `hooks/guard-observe.sh` exits 2 on mutating commands from observe-tier agents.
- Codex: `approval_policy = "on-request"` on the parent session, two GitHub MCP servers, agent prompts name which they may use.

## Run

Claude Code — orchestrator as the main thread:
```
claude --agent chief-of-staff
```
Headless daily brief:
```
claude -p "morning brief" --agent chief-of-staff --permission-mode default --permission-prompts none --output-format json
```
Codex — in the ChatGPT desktop app or CLI, with this repo open:
```
morning brief — spawn cloud_ops, code_triage and security_watch in parallel, wait for all, merge by the chief-of-staff rules
```

## Edit a prompt

1. Change `prompts/<agent>.md` (or a setting in `agents.json`).
2. `python3 scripts/build-agents.py`
3. Re-run that agent's `evals/` cases; commit prompt + generated files together.

## Ledger

`grabskimm/ops-ledger` (GitHub Issues). Create it with labels `agent/*`, `tier/*`, `state/*`, `src/*`, `sec/*` and issue #1 titled "daily brief log" before first use. `skills/ledger/SKILL.md` has the commands.
