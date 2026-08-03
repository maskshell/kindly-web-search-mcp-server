#!/usr/bin/env bash
# fork-pr-check.sh — guard against fork-only / Solid Forge content leaking into upstream PRs.
#
# A PR branch is cut from `main` (the pristine upstream mirror) and must carry only
# feature commits. This script diffs the branch against `main` and FAILS (exit 1) if
# the diff contains any fork-local content from the denylist below.
#
# Usage:  bash scripts/fork-pr-check.sh [branch]   (default: HEAD / current branch)
# Maintenance: when the fork-only manifest in CLAUDE.md (Fork Workflow) changes,
#              mirror the change in FORK_FILES / the marker regexes below.

set -uo pipefail

BRANCH="${1:-HEAD}"
BASE="main"

echo "==> fork-pr-check: diffing ${BRANCH} against ${BASE}"

fail=0
changed="$(git diff --name-only "${BASE}..${BRANCH}")"

has_file() { printf '%s\n' "$changed" | grep -qxF "$1"; }
leak() { printf '  LEAK: %s\n' "$1"; fail=1; }

# 1. Fork-only WHOLE files — must never appear in an upstream PR diff.
for f in .importlinter.ini .env.solidforge.example scripts/fork-pr-check.sh scripts/hooks/pre-push .markdownlint.json; do
  if has_file "$f"; then leak "fork-only file '$f' is in the PR diff"; fi
done

# 2. Fork-only SECTIONS in shared files (detect ADDED diff lines matching fork markers).
if has_file pyproject.toml; then
  if git diff "${BASE}..${BRANCH}" -- pyproject.toml | grep -Eq '^\+\[dependency-groups\]'; then
    leak "pyproject.toml: added [dependency-groups] section (fork-only gate deps)"
  fi
fi

if has_file .gitignore; then
  if git diff "${BASE}..${BRANCH}" -- .gitignore \
      | grep -Eq '^\+(\.claude/parallel-dev|\.env\.solidforge|/\.graphiti\.json|/\.semgrep\.yml|/\.spectral\.yaml|/\.vale\.ini|/uv\.lock|!\.env\.solidforge\.example)'; then
    leak ".gitignore: added fork-local ignore pattern(s)"
  fi
fi

if [ "$fail" -eq 1 ]; then
  echo "FAIL — fork-only content would leak upstream."
  echo "Keep Solid Forge / fork-local changes off PR branches. If a feature commit"
  echo "bundled a config edit, split it (git rebase -i) or drop the offending lines."
  exit 1
fi

echo "PASS — no fork-only content in PR diff."
