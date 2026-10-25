@AGENTS.md
@skills/ledger/SKILL.md

# Runtime note
This file is read when a Claude Code session opens this repo directly (cloud / remote sessions). On a local machine the same contract is imported from ~/.ops-agents/AGENTS.md by ~/.claude/CLAUDE.md after scripts/install.sh. Selectors: ~/.ops-agents/.env locally; in the cloud, `$CLAUDE_PROJECT_DIR/selectors.env` or the environment's variables (see docs/runtimes.md).
