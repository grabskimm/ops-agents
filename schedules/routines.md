# Scheduled routines

The Chief of Staff handles every prompt below; the timer only sends it. Create each routine once in the platform (not scriptable today), using exactly the prompt text — the agent keys its behaviour off it.

| Routine | Cadence | Prompt to send | What the Chief of Staff does |
| --- | --- | --- | --- |
| morning-brief | weekdays 10:00 <ZONE> | `morning brief` | fan-out to comms, cloud-ops, code-triage, security-watch since the last brief; merge; post to ledger #1 |
| security-sweep | daily 07:00 <ZONE> | `security sweep` | security-watch only, 24h window; P0/P1 only; silent when empty |
| stale-ledger | weekdays 16:00 <ZONE> | `stale ledger check` | ledger items in state/waiting-human older than 2 working days → one list with the question each one is waiting on |
| pr-nudge | weekdays 14:00 <ZONE> | `pr queue` | code-triage PR queue only; nothing else |
| weekly-retro | Fridays 15:00 <ZONE> | `weekly retro` | ledger items closed this week by agent, blind spots seen more than twice, prompts worth editing; opens a ledger issue labelled agent/chief-of-staff |

Rules (also in the chief-of-staff prompt):
- A scheduled run has no operator present: never execute-tier; anything needing a "go" is left in state/waiting-human.
- Output goes to the ledger comment; a chat/Slack/push notification only when there is at least one P0/P1 or a new blind spot. Silence means "checked, nothing".
- Times shown in any brief use <ZONE>.

Set `<ZONE>` once (IANA name) when creating the routines; all five use the same zone.

## Where to create them
- Claude Code (cloud routines, min interval 1 h, run without your laptop): Code tab → Routines → new → cadence, prompt, agent `chief-of-staff`. Claude Code Desktop routines run locally when the app is open.
- Claude app scheduled tasks: same prompts; each run starts a fresh session with the installed `~/.claude` config.
- Claude Tag (Slack): `@Claude` in `#ops-agents`: "every weekday at 10:00 <ZONE> run: morning brief" — results post in the channel.
- ChatGPT Work: in the chief-of-staff thread: "set up a scheduled task: weekdays 10:00 <zone>, send 'morning brief'". Codex Cloud automations for the Codex-side watchers.
- Your own cron (any box with the installed config and logins):
  ```
  0 10 * * 1-5  claude -p "morning brief" --agent chief-of-staff --permission-mode default --permission-prompts none --output-format json >> ~/.ops-agents/runs/brief.jsonl
  ```
