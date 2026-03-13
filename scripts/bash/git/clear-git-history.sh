#!/usr/bin/env bash

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

BRANCH="${GIT_DEFAULT_BRANCH:-main}"

echo "WARNING: This will permanently destroy all git history and force-push to origin/$BRANCH."
echo "This operation cannot be undone."
echo

if $DRY_RUN; then
	echo "[dry-run] Would run:"
	echo "  git checkout --orphan new-branch"
	echo "  git add -A"
	echo "  git commit -m 'Initial commit'"
	echo "  git branch -D $BRANCH"
	echo "  git branch -m $BRANCH"
	echo "  git push -f origin $BRANCH"
	echo "  git branch --set-upstream-to=origin $BRANCH"
	exit 0
fi

read -rp "Type 'yes' to confirm: " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 1; }

git checkout --orphan new-branch
git add -A
git commit -m "Initial commit"
git branch -D "$BRANCH"
git branch -m "$BRANCH"
git push -f origin "$BRANCH"
git branch --set-upstream-to=origin "$BRANCH"
