# Brief JSON (input to scripts/render-brief.py)

Written by chief-of-staff to `~/.ops-agents/briefs/<YYYY-MM-DD-HHMM>.json`, rendered to `.html` beside it. Every key optional; the shared text block is still printed in the reply.

```json
{
  "title": "Ops brief",
  "generated_at": "2026-10-25T14:30-07:00",
  "window": "2026-10-25T00:00-07:00 → 2026-10-25T14:30-07:00",
  "headline": "Nothing urgent, but half the sources could not be checked. One new CI failure in lyfegame/shortcut.",
  "items": [
    {"priority": "P1", "text": "VM verification failing on dev, 5 runs in a row (aec1eea, PR #15741)", "link": "https://github.com/…/runs/40230421364", "action": "decide", "owner": "code-triage"}
  ],
  "not_checked": [
    {"source": "Gmail, Slack, Calendar", "reason": "comms has no connectors in this session", "fix": "claude.ai → Settings → Connectors; run in a cloud session"},
    {"source": "Vercel team <team>", "reason": "403", "fix": "authorize_team_access"}
  ],
  "clean": ["No Cloudflare Worker deployments or DNS/audit changes", "No new GitHub security alerts", "No PRs waiting on you"],
  "older": [
    {"priority": "P2", "text": "GCP Alerting Drift Check failing daily since 10-20", "link": "https://…", "action": "decide", "owner": "infra-builder"}
  ],
  "track": ["VM verification failure (code-triage hand-off to code-fixer)"],
  "next": "Say whether code-triage should trace the dev VM failure; connect the missing sources and re-run.",
  "connectors": [
    {"name": "Gmail", "capability": "mail", "status": "used", "agent": "comms"},
    {"name": "Microsoft_365", "capability": "mail, calendar, chat", "status": "used", "agent": "comms"},
    {"name": "Cloudflare_Developer_Platform", "capability": "edge", "status": "used", "agent": "cloud-ops, security-watch", "note": "deprecated bindings server"},
    {"name": "Slack", "capability": "chat", "status": "failing", "agent": "comms", "note": "proxy 403"},
    {"name": "Booking_com", "capability": "travel", "status": "unused"},
    {"name": "Acme_Thing", "capability": "?", "status": "unmapped"}
  ],
  "capabilities": {"available": ["gh", "github MCP", "gcloud"], "missing": ["Gmail/Slack/Calendar"], "not_checked": ["Cloud Build", "kube"]}
}
```

Rules for the writer:
- `connectors` lists EVERY connector in the session once; `status` ∈ used|unused|unmapped|failing.
- `priority` ∈ P0|P1|P2; `action` ∈ decide|approve|review|none. Blind spots go in `not_checked`, never in `items`.
- `window` is explicit ISO with offset, start → end; the same string is passed to every specialist.
- `track` lists only what is worth a ledger issue; the operator answers "track".
- The chat reply is three lines (headline, `Brief: <path>`, `Open it? (yes)`); everything else lives here.
