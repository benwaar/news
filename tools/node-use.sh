#!/bin/zsh
# Ensure a specific Node version using nvm. Usage:
#   bash tools/node-use.sh [version]
# If no version provided, reads from nearest .nvmrc up the tree.
set -euo pipefail

# Unset npm_config_prefix which breaks nvm
unset npm_config_prefix 2>/dev/null || true

# Load nvm (non-interactive friendly)
if [[ -z "${NVM_DIR:-}" ]]; then
  if [[ -d "$HOME/.nvm" ]]; then
    export NVM_DIR="$HOME/.nvm"
  elif [[ -d "/opt/homebrew/opt/nvm" ]]; then
    export NVM_DIR="/opt/homebrew/opt/nvm"
  fi
fi

if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
  . "/opt/homebrew/opt/nvm/nvm.sh"
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
  . "$HOME/.nvm/nvm.sh"
else
  echo "nvm not found. Install via Homebrew: brew install nvm" >&2
  exit 1
fi

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  # find nearest .nvmrc
  SEARCH_DIR="$PWD"
  while [[ "$SEARCH_DIR" != "/" ]]; do
    if [[ -f "$SEARCH_DIR/.nvmrc" ]]; then
      TARGET=$(cat "$SEARCH_DIR/.nvmrc" | tr -d ' \t\r\n')
      break
    fi
    SEARCH_DIR=$(dirname "$SEARCH_DIR")
  done
fi

if [[ -z "$TARGET" ]]; then
  echo "No version specified and no .nvmrc found." >&2
  exit 1
fi

echo "[node-use] Ensuring Node $TARGET via nvm"
nvm install "$TARGET" >/dev/null
nvm use "$TARGET"
hash -r
echo "[node-use] Active: $(node -v)"
