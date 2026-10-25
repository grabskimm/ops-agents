# Local vs cloud: what each runtime can reach

| Source | LOCAL (CLI, desktop Code tab) | CLOUD (claude.ai Code, remote, Claude Tag, routines) |
| --- | --- | --- |
| Config | `~/.claude` + `~/.ops-agents` (from `install.sh`) | the opened repo: `CLAUDE.md`, `.claude/agents`, `.claude/settings.json`, `.mcp.json`, `hooks/`, `skills/` — open **this scaffold repo** (or your fork) |
| Selectors | `~/.ops-agents/.env` | `selectors.env` in your fork (git-ignored here) or the cloud environment's variables |
| GitHub | `gh` login + user-scope `github` / `github-rw` MCP | claude.ai GitHub connector, or the GitHub MCP as a custom connector |
| Cloudflare / Vercel / Supabase | user-scope MCP (OAuth via `/mcp`), CLIs | claude.ai → Settings → Connectors → **add custom connector** with the same URLs: `https://mcp.cloudflare.com/mcp`, `https://mcp.vercel.com`, `https://mcp.supabase.com/mcp?read_only=true&project_ref=<ref>` (OAuth in claude.ai) |
| Gmail / Slack / Calendar | **unavailable** | claude.ai connectors |
| GCP (`gcloud`) | your login / ADC | **unavailable** (no login in the sandbox) |
| Kubernetes | `KUBE_CONTEXTS_RO` contexts | **unavailable** |
| Scheduling | cron line or desktop Routines | cloud routines, Claude Tag, `/cos set up my routines` |
| Brief output | `~/.ops-agents/briefs/*.html`, `open` | published artifact link |

Consequence: a complete picture is two runs — the cloud routine covers comms + GitHub + Cloudflare/Vercel/Supabase; a local `/cos` covers GCP + Kubernetes (+ the same GitHub/Cloudflare/Vercel/Supabase if you prefer). The chief-of-staff labels each run LOCAL or CLOUD and marks the other half `unavailable here`, never as a setup gap.

Cloud setup checklist (one-time, in claude.ai):
1. Settings → Connectors: Gmail, Slack, Google Calendar, GitHub.
2. Add custom connectors for Cloudflare, Vercel, Supabase (URLs above); authorize once.
3. Fork this repo (or use it as is) and set `GITHUB_ORGS`, `LEDGER_REPO`, `SUPABASE_PROJECT_REF` as cloud environment variables, or commit `selectors.env` to your fork.
4. Open the repo in a cloud session: `/cos morning brief`, then `/cos set up my routines`.
