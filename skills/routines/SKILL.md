---
name: routines
description: Create, list or remove the ops-agents scheduled routines (morning brief, security sweep, stale ledger check, PR queue, weekly retro) from ~/.ops-agents/schedules/routines.md. Use when the operator says "set up my routines", "schedule the brief", "/routines", or asks what is scheduled.
allowed-tools: Read, Bash(date *)
---

# Routines skill

Tier: propose → execute. Creating a timer is an execute-tier action: list the plan, get a "go", then create. Removing one needs its own "go".

## 1. Read the catalogue
`~/.ops-agents/schedules/routines.md` — one row per routine: name, cadence, exact prompt text. The `<ZONE>` placeholder must be resolved: ask the operator for an IANA zone once if it is not already set in the file; never guess it.

## 2. Find the scheduling tool in this session (preflight)
Look for, in this order, and use the first that exists:
- a Claude scheduled-task tool (names like `create_trigger`, `list_triggers`, `update_trigger`, `delete_trigger`; may need loading through tool search) — Claude app and Claude Code remote sessions
- Claude Tag in Slack: you are in a channel; a routine is created by stating it ("every weekday at 10:00 <ZONE> run: ops brief")
- none → STATUS: needs-human, and print the manual steps from the "Where to create them" section of the catalogue, one line per platform. Never claim a schedule exists that you did not create.

## 3. List before creating
List existing scheduled tasks. Match by name (`ops-agents: <routine>`). Skip ones that already exist with the same cadence; report drift (different cadence or prompt) as an ITEM with action=decide.

## 4. Create (after "go")
For each missing routine:
- name: `ops-agents: <routine>`
- cron: the catalogue cadence rendered as a 5-field cron with `CRON_TZ=<ZONE>` (10:00 → `0 10 * * 1-5`; 07:00 daily → `0 7 * * *`; Fri 15:00 → `0 15 * * 5`). Scheduled tasks on the hour may be delayed by load; shift the minute 1–29 earlier per the tool's guidance if it asks for it, and say so.
- prompt: the exact prompt text from the catalogue, prefixed with `You are chief-of-staff (prompt: ~/.ops-agents/prompts/chief-of-staff.md). Scheduled run, no operator present. ` — each firing starts a fresh session.
- notifications: push on only when the tool offers it; email never.
- approval setting: whatever the tool reports; tell the operator which it got (runs that ask for approval will stall unattended).
Report each created task's id and next fire time.

## 5. Remove / change
Only on an explicit instruction naming the routine. Update in place when the tool supports it; otherwise delete and recreate, and say so.

## Output
Shared block. ITEMS: one line per routine — `[P2] <routine> — created|exists|drift|manual — <next fire or platform>`.

Stop conditions: zone unknown → ask; tool missing → manual steps, needs-human; tool refuses (interval too short, permission) → quote the reason, needs-human.
