# Setup — end to end

Everything that can be scripted is in `scripts/setup.sh`; the rest is a short list of clicks in the vendor UIs. Order: credentials → `setup.sh` → one runtime → first eval.

## 0. Credentials (once, in each vendor's UI — cannot be scripted)

| Credential | Where | Minimum scope |
| --- | --- | --- |
| `GH_TOKEN_READ` | GitHub → Settings → Developer settings → Fine-grained tokens | repos: all you want watched. Permissions: Contents **read**, Actions read, Pull requests read, Code scanning/Dependabot/Secret scanning alerts read, Metadata read; **plus** Issues **write** restricted to `ops-ledger` (make a second fine-grained token if GitHub won't mix the two repo sets, and give the ledger token to the `github` server) |
| `GH_TOKEN_RW` | same page | repos: only the ones code-fixer / infra-builder may change. Contents write, Pull requests write, Metadata read. Turn on branch protection → require PR on `main` in each of those repos |
| `SUPABASE_PAT_RO` + `SUPABASE_PROJECT_REF` | Supabase → Account → Access Tokens | personal access token; the `--read-only` flag in both MCP configs is what makes it read-only |
| `CLOUDFLARE_API_TOKEN` (or OAuth) | Cloudflare → My Profile → API Tokens | Zone:Read, Workers Scripts:Read, Firewall Services:Read, Logs:Read, Account Settings:Read |
| `VERCEL_TOKEN` | Vercel → Settings → Tokens, on a **Viewer** team member | token scope = that member's role |
| `GOOGLE_APPLICATION_CREDENTIALS` | GCP → IAM → Service Accounts → create `ops-agents-ro` → key | roles/viewer, roles/logging.viewer, roles/iam.securityReviewer |
| `KUBECONFIG` | your cluster | a ServiceAccount bound to ClusterRole `view`; `kubectl config view --minify --raw` for that SA |

Then:
```
cp .env.example .env    # fill in; .env is git-ignored
```

## 1. Run the setup script

```
scripts/setup.sh            # all of: --ledger --claude --codex
```
What it does, idempotently: checks `gh`/`python3`/`jq`; loads `.env`; regenerates agent files; symlinks `skills/` for both runtimes; creates `grabskimm/ops-ledger` (private) with every label and the "daily brief log" issue; validates every JSON/TOML; runs `scripts/check-tokens.sh`, which proves each read token cannot write and each write token is scoped.

Any ✘ from `check-tokens.sh` means a token has more power than its agent; fix it before running an agent.

## 2a. Claude Code

```
npm install -g @anthropic-ai/claude-code      # if missing
cd ops-agents && claude                        # first run: approve the 5 project MCP servers from .mcp.json
claude --agent chief-of-staff
```
- Gmail, Slack, Google Calendar: claude.ai → Settings → Connectors (OAuth). They appear to the agents as `mcp__gmail__*`, `mcp__slack__*`, `mcp__google-calendar__*`.
- Daily brief: Claude Code → Routines → new → weekdays, 10:00 local, prompt `morning brief`, agent `chief-of-staff` (cloud routines run without your laptop).
- Slack entry point: install Claude Tag in the workspace, invite it to `#ops-agents`, point it at this repo; `@Claude why is CI red` then runs code-triage.
- Headless (your own cron / CI):
  ```
  claude -p "morning brief" --agent chief-of-staff --permission-mode default --permission-prompts none --output-format json
  ```

## 2b. ChatGPT / Codex

```
npm install -g @openai/codex                   # if missing
cd ops-agents && codex                         # reads .codex/config.toml and .codex/agents/*.toml
codex plugin install gmail slack google-calendar   # Comms connectors, from github.com/openai/plugins
```
- Put the same `.env` values into Codex Cloud environment secrets if you run tasks there (local `gcloud`/`kubectl` auth does not travel).
- Orchestrator: a ChatGPT Work thread (desktop app, with this repo open). First message:
  ```
  Be my chief of staff for this repo. Follow AGENTS.md and prompts/chief-of-staff.md. For a brief, spawn cloud_ops, code_triage and security_watch in parallel, wait for all, merge by the chief-of-staff rules. Comms questions use the Gmail/Slack/Calendar plugins directly. Ask before any execute-tier action.
  ```
- Daily brief: in that thread, "set up a scheduled task: weekdays 10:00 local, send 'morning brief'".
- Slack entry point: Codex Slack integration (workspace admin installs it); GitHub: Codex GitHub app for `@codex review` on PRs code-fixer opens.
- Permission mode: keep the composer on **ask / on-request** before delegating; subagents inherit it.

## 3. First eval (proves the tiers, 15 minutes)

1. `code-triage`: "why did the last failed workflow run in <repo> fail?" → expect CAUSE + a GitHub URL, `TIER-USED: observe`, no push in `.runs/`.
2. `cloud-ops`: "any failing deployment in the last 24h?" → expect one ITEM per platform or "none", `LEDGER:` line.
3. `code-fixer` on a trivial known bug: propose → reply `go` → expect a draft PR on `fix/<n>-<slug>`, never on main.
4. `comms`: "anything pending for me?" then "draft a reply to <thread>" → expect a Gmail draft ID; check Sent is unchanged.

Record each as a case in `evals/<agent>.md`.

## Re-running after a change

```
vim prompts/<agent>.md        # or agents.json
python3 scripts/build-agents.py
scripts/check-tokens.sh
git add -A && git commit -m "prompt: <agent> — <what changed>"
```
