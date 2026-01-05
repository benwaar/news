#!/bin/zsh
# Start Angular UI (news or portal) with correct Node via nvm.
# Usage: zsh tools/ui-start.sh [news|portal]
set -euo pipefail

# Source nvm and switch Node using the project helper
source "$(dirname "$0")/node-use.sh" 20.19.0

UI_NAME="${1:-news}"
case "$UI_NAME" in
	news) UI_DIR="$(dirname "$0")/../services/ui-news" ;;
	portal) UI_DIR="$(dirname "$0")/../services/ui-portal" ;;
	*) echo "Unknown UI: $UI_NAME (use 'news' or 'portal')" >&2; exit 2 ;;
esac

cd "$UI_DIR"
npm start
