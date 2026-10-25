# Ledger conventions (grabskimm/ops-ledger)

- Issue #1 is the "daily brief log". chief-of-staff comments on it after every brief: `brief <ISO timestamp> — <n> items`. The newest comment is the baseline window for the next run.
- Title format: `[<agent>] <short task>`.
- Body: source link(s) on the first line, then intent, then a running log of comments.
- Labels are set on creation: `agent/<name>`, `tier/<observe|propose|execute>`, `state/open`, `src/<system>`; security findings add `sec/<source>`.
- `state/waiting-human` means the agent has stopped and needs a "go" or a decision; `state/running` means an actor is applying an approved change.
- Close only with a final comment naming the artefact: PR URL, Gmail draft ID, or plan path.
- Search before creating: `is:issue is:open label:agent/<name> "<key term>"`.
