# Connector map — capability → owning agent

Preflight (chief-of-staff, every run): list **every** connector / MCP server the session exposes — a connector-listing tool first (`ListConnectors` or similar), then the `mcp__<Server>__` prefixes — and classify each with this table. Case-insensitive match on the server name. Output the full inventory on the brief page under "Connectors"; in chat only the counts.

| Connector (server name contains) | Capability | Used by | Notes |
| --- | --- | --- | --- |
| gmail | mail | comms | drafts only |
| microsoft_365 (outlook_*) | mail, calendar | comms | drafts only; outlook_calendar read-only |
| microsoft_365 (teams_*, chat_message_search) | chat | comms | read-only |
| slack | chat | comms | read-only |
| google_calendar, google-calendar | calendar | comms | read-only |
| availcal | calendar (free/busy) | comms | read-only by design |
| github, github-rw | source control, CI, security alerts | code-triage, security-watch, code-fixer (rw), skills-librarian (rw) | `github` read-only header; `github-rw` actors only |
| cloudflare, cloudflare_developer_platform | edge: Workers, DNS, WAF, KV/R2/D1 | cloud-ops, security-watch (read); infra-builder (plan only) | the Workers-Bindings server is deprecated; prefer `mcp.cloudflare.com/mcp` |
| vercel | deployments, env var names | cloud-ops, security-watch | read |
| supabase | db health, RLS, auth, functions | cloud-ops, security-watch | `read_only=true` |
| google_drive, claude_docs, sharepoint (microsoft_365) | documents | comms (read context), skills-librarian (write via PR only) | read |
| figma, draw_io | diagrams | infra-builder | output artefacts only |
| gitkraken (plugin) | git, PRs, issues | code-triage (read), code-fixer | local git on the operator's machine |
| memory | operator memory | none | never read by agents; personal, not ops |
| booking_com, expedia, kiwi_com, edreams, tripit | travel | none | out of scope: list as `unused` |
| widgets, visualize, claude_docs (render) | presentation | chief-of-staff | brief rendering only |
| anything else | — | none | list as `unmapped: <name>` and ask the operator which agent should own it; never guess |

Rules:
- Every connector appears exactly once in the inventory: `used by <agent>`, `unused (out of scope)`, or `unmapped`.
- A capability served by two connectors (e.g. Gmail and Outlook mail) is covered by both; comms reports each.
- A connector present but failing (auth, 403, proxy) is `present, failing: <reason>` — a blind spot with a fix, not `missing`.
- Tier rules still apply per tool: the guard and deny lists block writes regardless of which connector exposes them.
