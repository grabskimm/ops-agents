# Ledger conventions (grabskimm/ops-ledger)

- Writes happen only on the operator's "track"/"go". Runs are logged in ~/.ops-agents/runs, not in the ledger.
- Title format: `[<agent>] <short task>`.
- Body: source link(s) on the first line, then intent, then a running log of comments.
- Labels are set on creation: `agent/<name>`, `tier/<observe|propose|execute>`, `state/open`, `src/<system>`; security findings add `sec/<source>`.
- `state/waiting-human` means the agent has stopped and needs a "go" or a decision; `state/running` means an actor is applying an approved change.
- Close only with a final comment naming the artefact: PR URL, Gmail draft ID, or plan path.
- Search before creating: `is:issue is:open label:agent/<name> "<key term>"`.
