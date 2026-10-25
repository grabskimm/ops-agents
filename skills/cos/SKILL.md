---
name: cos
description: Hand a request to the chief-of-staff orchestrator. Use /cos <question> from any surface (CLI, desktop app, remote session) instead of claude --agent chief-of-staff.
argument-hint: <question or routine prompt, e.g. "morning brief", "what's running", "any pending items">
agent: chief-of-staff
user-invocable: true
disable-model-invocation: true
---

The operator's request is: $ARGUMENTS

Handle it exactly as your prompt (~/.ops-agents/prompts/chief-of-staff.md) says: preflight, route to the specialists by the routing table, merge by the merge rules, end with the shared output block. If $ARGUMENTS is empty, run "what should my focus be today?".
