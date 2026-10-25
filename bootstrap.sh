#!/usr/bin/env bash
# One-shot setup without keeping a clone:
#   curl -fsSL https://raw.githubusercontent.com/grabskimm/ops-agents/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- --install          # any setup.sh flags
#   OPS_AGENTS_REF=v1 curl -fsSL .../bootstrap.sh | bash         # pin a tag/branch
#   OPS_AGENTS_KEEP=1 ...                                        # keep the extracted copy, print its path
# Downloads a tarball of the scaffold to a temp dir, runs scripts/setup.sh, removes the temp dir.
# Nothing from the repo stays on disk; what setup installs lives in ~/.ops-agents, ~/.claude, ~/.codex, ~/.agents.
set -uo pipefail
REPO="${OPS_AGENTS_REPO:-grabskimm/ops-agents}"
REF="${OPS_AGENTS_REF:-main}"
URL="https://github.com/$REPO/archive/refs/heads/$REF.tar.gz"
[[ "$REF" =~ ^v[0-9] ]] && URL="https://github.com/$REPO/archive/refs/tags/$REF.tar.gz"

for c in curl tar python3 jq; do command -v "$c" >/dev/null 2>&1 || { echo "missing: $c"; exit 1; }; done
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ops-agents.XXXXXX")"
cleanup() { [[ "${OPS_AGENTS_KEEP:-0}" == "1" ]] && { echo "kept: $TMP"; return; }; rm -rf "$TMP"; }
trap cleanup EXIT

echo "== fetching $REPO@$REF"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh api "repos/$REPO/tarball/$REF" > "$TMP/src.tgz" 2>/dev/null || curl -fsSL "$URL" -o "$TMP/src.tgz"
else
  curl -fsSL "$URL" -o "$TMP/src.tgz"
fi || { echo "download failed: $URL (private repo? log in with gh first)"; exit 1; }
tar -xzf "$TMP/src.tgz" -C "$TMP" || { echo "extract failed"; exit 1; }
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
chmod +x "$SRC"/scripts/*.sh "$SRC"/hooks/*.sh 2>/dev/null

echo "== running setup ${*:-(--all)}"
bash "$SRC/scripts/setup.sh" "$@"
echo "== scaffold removed from disk; installed config is in ~/.ops-agents (re-run this one-liner to update)"
