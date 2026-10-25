# Evals

One file per agent, three cases each, with known answers. Re-run after any prompt change.

Format (`evals/<agent>.md`):

```
## Case 1 — <name>
Ask: <the operator's exact words>
Expected ITEMS: <lines that must appear, with their source links>
Expected tier: observe | propose | execute
Expected ledger: issue created | existing issue updated | none
Must NOT: <any write outside scope, e.g. "no git push", "no Gmail send">
Judge: <how to score: exact match / contains / human>
```

Pass = correct ITEMS, correct TIER-USED, LEDGER line present when expected, nothing on the Must NOT list in `.runs/` or in the connector's audit log.

Run (Claude Code, headless):
```
claude -p "<Ask>" --agent <agent> --permission-mode default --permission-prompts none --output-format json
```
Run (Codex, non-interactive):
```
codex exec --agent <agent_name> "<Ask>"
```
