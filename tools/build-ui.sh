#!/bin/zsh
# Build the Angular UI project from repo root.
# Usage: bash tools/build-ui.sh
set -euo pipefail

source "$(dirname "$0")/node-use.sh" 20.19.0
pushd "$(dirname "$0")/../services/ui" >/dev/null
npm run build
popd >/dev/null
