#!/usr/bin/env zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f .githooks/pre-commit ]]; then
  echo "No .githooks/pre-commit found. Aborting." >&2
  exit 1
fi

chmod +x .githooks/pre-commit

git config core.hooksPath .githooks

echo "Git hooks enabled: $(git config --get core.hooksPath)"
echo "Pre-commit hooks are now active for this repository."
