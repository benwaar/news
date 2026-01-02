#!/usr/bin/env bash
set -euo pipefail

# Clean up Docker artifacts: dangling images, build cache, and optionally all unused images/containers/networks.
# Usage:
#   bash tools/clean-docker.sh            # Safe prune (dangling images + build cache)
#   bash tools/clean-docker.sh --all      # Aggressive prune (unused images/containers/networks)
#   bash tools/clean-docker.sh --all -y   # Aggressive prune without confirmation
#   bash tools/clean-docker.sh -y         # Safe prune without confirmation
#
# Flags:
#   --all    Perform docker system prune -a (aggressive)
#   -y       Skip interactive confirmation
#
# Returns to project root automatically.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
pushd "${PROJECT_ROOT}" > /dev/null

ALL_MODE=false
AUTO_YES=false

for arg in "$@"; do
  case "$arg" in
    --all)
      ALL_MODE=true
      shift || true
      ;;
    -y|--yes)
      AUTO_YES=true
      shift || true
      ;;
    -h|--help)
      echo "Usage: clean-docker.sh [--all] [-y]";
      echo "  --all    Aggressive prune (docker system prune -a)";
      echo "  -y       Skip confirmation";
      popd > /dev/null; exit 0;
      ;;
    *)
      echo "Unknown argument: $arg" >&2; exit 1;
      ;;
  esac
done

confirm() {
  if [[ "$AUTO_YES" == true ]]; then
    return 0
  fi
  read -r -p "$1 (y/n): " ans
  [[ "$ans" == "y" ]]
}

before_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | wc -l || true)
before_dangling=$(docker images -f dangling=true -q | wc -l || true)

if [[ "$ALL_MODE" == true ]]; then
  echo "Requested aggressive prune (system prune -a)."
  if confirm "Proceed with aggressive prune (removes ALL unused images/containers/networks)?"; then
    docker system prune -a -f || true
  else
    echo "Aborted aggressive prune."; popd > /dev/null; exit 0
  fi
else
  echo "Performing safe prune: dangling images + build cache."
  if confirm "Proceed with safe prune?"; then
    # Dangling images
    docker image prune -f || true
    # Build cache
    docker builder prune -f || true
    # Optional: prune unused volumes lightly (without -a)
    docker volume prune -f || true
  else
    echo "Aborted safe prune."; popd > /dev/null; exit 0
  fi
fi

after_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | wc -l || true)
after_dangling=$(docker images -f dangling=true -q | wc -l || true)

echo "Summary:";
echo "  Images (count before -> after): ${before_images} -> ${after_images}";
echo "  Dangling images (before -> after): ${before_dangling} -> ${after_dangling}";

popd > /dev/null
