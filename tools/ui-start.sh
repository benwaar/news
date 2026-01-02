#!/bin/zsh
# Start Angular UI with correct Node version via nvm.
# Usage: bash tools/ui-start.sh
set -euo pipefail

# Source nvm and switch Node using the project helper
source "$(dirname "$0")/node-use.sh" 20.19.0

cd "$(dirname "$0")/../services/ui"
# Use package.json start which already sources node-use internally (fallback here is enough)
npm start
