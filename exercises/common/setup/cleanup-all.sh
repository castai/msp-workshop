#!/usr/bin/env bash
#
# cleanup-all.sh — Complete teardown of the MSP workshop kind cluster.
#
# Usage:
#   ./cleanup-all.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[cleanup]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[cleanup]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[cleanup]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[cleanup]${NC} %s\n" "$*"; }

CLUSTER_NAME="workshop-cluster"

printf "==================================================\n"
printf "  MSP Workshop — Complete Cleanup\n"
printf "==================================================\n\n"

warn "this will delete the '${CLUSTER_NAME}' kind cluster and optionally prune Docker resources."
printf '\n'
read -r -p "Are you sure? (yes/no): " reply
if [[ "${reply}" != "yes" ]]; then
  info "cleanup cancelled."
  exit 0
fi

printf '\n'

info "deleting kind cluster..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  log "cluster '${CLUSTER_NAME}' deleted"
else
  warn "cluster '${CLUSTER_NAME}' not found"
fi

printf '\n'
info "pruning Docker containers..."
docker container prune -f

printf '\n'
info "pruning Docker volumes..."
docker volume prune -f

printf '\n'
info "Docker disk usage:"
docker system df

printf '\n'
read -r -p "Clean up unused Docker images? This will free space but slow down the next setup. (yes/no): " reply
if [[ "${reply}" == "yes" ]]; then
  info "pruning Docker images..."
  docker image prune -a -f
fi

printf '\n'
printf "==================================================\n"
log "cleanup complete"
printf "==================================================\n"
printf '\n'
printf "To set up the workshop again:\n"
printf "  ./exercises/common/setup/install-kind.sh\n"
