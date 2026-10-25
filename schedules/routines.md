# Scheduled routines

The Chief of Staff handles every prompt below; the timer only sends it. To create the timers, say **"set up my routines"** (or `/routines`) in a Claude app or Claude Code remote session: the `routines` skill reads this file, lists what exists, and creates the missing ones after your "go". Where no scheduling tool exists (local CLI, Codex) it prints the manual steps from the section at the end instead.

| Routine | Cadence | Prompt to send | What the Chief of Staff does |
| --- | --- | --- | --- |
| ops-brief | weekdays 10:00 <ZONE> | `ops brief` | fan-out to comms, cloud-ops, code-triage, security-watch since the last run; merge; report (run log is the record) |
| security-sweep | daily 07:00 <ZONE> | `security sweep` | security-watch only, 24h window; P0/P1 only; silent when empty |
| stale-ledger | weekdays 16:00 <ZONE> | `stale ledger check` | ledger items in state/waiting-human older than 2 working days → one list with the question each one is waiting on |
| pr-nudge | weekdays 14:00 <ZONE> | `pr queue` | code-triage PR queue only; nothing else |
| weekly-retro | Fridays 15:00 <ZONE> | `weekly retro` | ledger items closed this week by agent, blind spots seen more than twice, prompts worth editing; proposes under TRACK? |

Rules (also in the chief-of-staff prompt):
- A scheduled run has no operator present: never execute-tier, never a ledger write; anything needing a "go" or "track" waits in the report.
- Output is the report (and the run log); a chat/Slack/push notification only when there is at least one P0/P1 or a new blind spot. Silence means "checked, nothing".
- Times shown in any brief use <ZONE>.

Set `<ZONE>` once (IANA name) when creating the routines; all five use the same zone.

## Where to create them by hand (when the session has no scheduling tool)
- Claude Code (cloud routines, min interval 1 h, run without your laptop): Code tab → Routines → new → cadence, prompt, agent `chief-of-staff`. Claude Code Desktop routines run locally when the app is open.
- Claude app scheduled tasks: same prompts; each run starts a fresh session with the installed `~/.claude` config.
- Claude Tag (Slack): `@Claude` in `#ops-agents`: "every weekday at 10:00 <ZONE> run: ops brief" — results post in the channel.
- ChatGPT Work: in the chief-of-staff thread: "set up a scheduled task: weekdays 10:00 <zone>, send 'ops brief'". Codex Cloud automations for the Codex-side watchers.
- Your own cron (any box with the installed config and logins):
  ```
  0 10 * * 1-5  claude -p "ops brief" --agent chief-of-staff --permission-mode default --permission-prompts none --output-format json >> ~/.ops-agents/runs/brief.jsonl
  ```
