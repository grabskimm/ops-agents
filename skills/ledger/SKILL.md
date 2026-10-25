---
name: ledger
description: Read, create and update task-ledger issues in $LEDGER_REPO (from ~/.ops-agents/.env). Use whenever an agent starts non-trivial work, changes state, or finishes with an artefact.
allowed-tools: Bash(gh issue *), Bash(gh api -X GET *), mcp__github__*, mcp__github-rw__*
---

# Ledger skill

Repo: `$LEDGER_REPO` from `~/.ops-agents/.env` (`set -a; . ~/.ops-agents/.env; set +a` first, or read the file). Empty → STATUS: blocked, ask the operator.

Tier note: reading is free; every write (create, comment, label, close) is execute-tier and happens only after the operator says "track" or "go" naming the item in this thread. Scheduled runs never write. Nothing else in `ops-ledger` is in scope.

Conventions: see `references.md` next to this file.

## 1. Find an existing issue
```
gh issue list -R "$LEDGER_REPO" --state open --label "agent/<name>" --search "<key term>" --json number,title,url,labels
```
If one matches, use it. Do not open a duplicate.

## 2. Create
```
gh issue create -R "$LEDGER_REPO" \
  --title "[<agent>] <short task>" \
  --label "agent/<name>" --label "tier/<observe|propose|execute>" --label "state/open" --label "src/<system>" \
  --body "<source link>\n\nIntent: <one line>"
```
Expected: an issue URL. Put it on the `LEDGER:` line of your output block.

## 3. Update state
```
gh issue edit -R "$LEDGER_REPO" <num> --remove-label "state/open" --add-label "state/waiting-human"
gh issue comment -R "$LEDGER_REPO" <num> --body "<what changed, link>"
```
States: open → waiting-human (needs a go/decision) → running (approved change in flight) → done.

## 4. Close
Only with a final comment naming the artefact (PR URL, draft ID, plan path):
```
gh issue comment -R "$LEDGER_REPO" <num> --body "Done: <artefact>"
gh issue close -R "$LEDGER_REPO" <num>
```

## 5. Run record
The brief baseline and run history live in ~/.ops-agents/runs (written by the SubagentStop hook); the ledger is not a log.

Stop conditions: `gh` not authenticated → STATUS: blocked, name the missing token. Label missing → create the issue without it and say so; never invent labels.
