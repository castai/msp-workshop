#!/usr/bin/env bash
#
# teardown.sh — Remove the shared Locust demo.
#
# Deletes the 'locust' namespace. Everything inside it (locust master,
# workers, ConfigMap, LoadBalancer Service) goes with it. Namespace
# deletion also triggers AWS ELB cleanup; the class-level
# setup-class/eks/delete-eks-cluster.sh is responsible for waiting on
# the matching ELBs to disappear before tearing down the cluster.
#
# Usage:
#   ./teardown.sh
#   ./teardown.sh --yes   skip the confirmation prompt

set -euo pipefail

# ANSI colors for messages. Matches demos/ecommerce/teardown.sh.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[teardown]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[teardown]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[teardown]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[teardown]${NC} %s\n" "$*"; }

NAMESPACE="locust"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

main() {
  local skip_confirm=0
  for arg in "$@"; do
    case "${arg}" in
      --yes|-y)
        skip_confirm=1
        ;;
      -h|--help)
        printf 'Usage: %s [--yes]\n' "$0"
        printf '  --yes, -y   skip the confirmation prompt\n'
        exit 0
        ;;
      *)
        err "unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  printf '%b' "${BLUE}"
  printf '============================================================\n'
  printf '  Locust (shared load generator) — teardown\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'

  if ! command_exists kubectl; then
    err "kubectl is not installed."
    return 1
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    err "cannot connect to a Kubernetes cluster. Check your kubeconfig."
    return 1
  fi

  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    log "namespace '${NAMESPACE}' does not exist; nothing to do"
    return 0
  fi

  if [[ "${skip_confirm}" -ne 1 ]]; then
    warn "this will delete the '${NAMESPACE}' namespace and everything inside it,"
    warn "including the Locust LoadBalancer Service (which will trigger AWS ELB cleanup)."
    read -r -p "Continue? (yes/no): " reply
    if [[ "${reply}" != "yes" ]]; then
      info "teardown cancelled."
      exit 0
    fi
    printf '\n'
  fi

  info "deleting namespace '${NAMESPACE}'..."
  kubectl delete namespace "${NAMESPACE}" --wait=true --timeout=300s

  printf '\n'
  log "namespace '${NAMESPACE}' removed"
  printf '\n'
}

main "$@"
