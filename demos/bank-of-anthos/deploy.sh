#!/usr/bin/env bash
#
# deploy.sh — Idempotent deploy of the Bank of Anthos demo.
#
# Pipeline:
#   1. Verify kubectl and helm are installed.
#   2. helm upgrade --install the bank-of-anthos chart.
#   3. Wait up to 5 minutes for the frontend LoadBalancer Service to get
#      an external endpoint.
#   4. Print the public URL and verification commands.
#
# Usage:
#   ./deploy.sh
#   ./deploy.sh --dry-run   print the helm command, skip execution and LB wait

set -euo pipefail

# ANSI colors for messages. Matches demos/ecommerce/deploy.sh.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log() { printf "${GREEN}[deploy]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[deploy]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[deploy]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[deploy]${NC} %s\n" "$*"; }

RELEASE_NAME="bank-of-anthos"
CHART_NAME="bank-of-anthos"
NAMESPACE="bank-of-anthos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/${CHART_NAME}"

# LoadBalancer wait budget: 5 minutes total, 5s between probes.
LB_WAIT_SECONDS=300
LB_PROBE_INTERVAL=5

HELM_CMD=(
  helm upgrade --install "${RELEASE_NAME}" "./${CHART_NAME}"
  --namespace "${NAMESPACE}"
  --create-namespace
  --wait
  --timeout 10m
)

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_banner() {
  printf '%b' "${BOLD}${BLUE}"
  printf '============================================================\n'
  printf '  Bank of Anthos demo — deploy\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'
}

ensure_prereqs() {
  if ! command_exists kubectl; then
    err "kubectl is not installed."
    return 1
  fi

  if ! command_exists helm; then
    err "helm is not installed."
    return 1
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    err "cannot connect to a Kubernetes cluster. Check your kubeconfig."
    return 1
  fi

  if [[ ! -d "${CHART_DIR}" ]]; then
    err "chart directory not found at ${CHART_DIR}"
    return 1
  fi

  log "connected to cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
  log "helm:  $(helm version --short 2>/dev/null || echo unknown)"
}

install_chart() {
  info "installing chart '${RELEASE_NAME}' from ${CHART_DIR}..."
  ( cd "${SCRIPT_DIR}" && "${HELM_CMD[@]}" )
  printf '\n'
  log "helm release '${RELEASE_NAME}' installed in namespace '${NAMESPACE}'"
}

wait_for_loadbalancer() {
  info "waiting up to ${LB_WAIT_SECONDS}s for service/frontend to receive an external endpoint..."

  local elapsed=0
  local endpoint=""

  while [[ ${elapsed} -lt ${LB_WAIT_SECONDS} ]]; do
    endpoint="$(
      kubectl get svc frontend -n "${NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
    )"
    if [[ -z "${endpoint}" ]]; then
      endpoint="$(
        kubectl get svc frontend -n "${NAMESPACE}" \
          -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
      )"
    fi

    if [[ -n "${endpoint}" ]]; then
      printf '\n'
      log "frontend LoadBalancer endpoint ready: ${endpoint}"
      printf '%s' "${endpoint}" > "${SCRIPT_DIR}/.frontend_endpoint"
      return 0
    fi

    sleep "${LB_PROBE_INTERVAL}"
    elapsed=$((elapsed + LB_PROBE_INTERVAL))
    printf '.'
  done

  printf '\n'
  warn "frontend LoadBalancer did not receive an endpoint within ${LB_WAIT_SECONDS}s"
  warn "the service is probably still provisioning — check:"
  warn "  kubectl get svc frontend -n ${NAMESPACE} -w"
  return 1
}

print_next_steps() {
  local endpoint=""
  if [[ -f "${SCRIPT_DIR}/.frontend_endpoint" ]]; then
    endpoint="$(cat "${SCRIPT_DIR}/.frontend_endpoint" 2>/dev/null || true)"
  fi

  printf '\n%b' "${BOLD}${GREEN}"
  printf '============================================================\n'
  printf '  Bank of Anthos demo is deployed\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'

  if [[ -n "${endpoint}" ]]; then
    printf 'Public URL:\n'
    printf '  http://%s\n' "${endpoint}"
    printf '\n'
  else
    printf 'Public URL: pending — check:\n'
    printf '  kubectl get svc frontend -n %s -w\n' "${NAMESPACE}"
    printf '\n'
  fi

  printf 'Verify deployment:\n'
  printf '  kubectl get pods -n %s\n' "${NAMESPACE}"
  printf '  kubectl get svc -n %s\n' "${NAMESPACE}"
  printf '  helm list -n %s\n' "${NAMESPACE}"
  printf '\n'

  printf 'Reach the frontend from inside the cluster:\n'
  printf '  curl http://frontend.%s.svc.cluster.local:80\n' "${NAMESPACE}"
  printf '\n'

  printf 'Tear down when done:\n'
  printf '  ./teardown.sh\n'
  printf '\n'
}

main() {
  local dry_run=0
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)
        dry_run=1
        ;;
      -h|--help)
        printf 'Usage: %s [--dry-run]\n' "$0"
        printf '  --dry-run   print the helm command and skip execution + LB wait\n'
        exit 0
        ;;
      *)
        err "unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  print_banner

  if [[ "${dry_run}" -eq 1 ]]; then
    info "[dry-run] would execute:"
    printf '  '
    printf '%s ' "${HELM_CMD[@]}"
    printf '\n\n'
    info "[dry-run] would then wait up to ${LB_WAIT_SECONDS}s for service/frontend LoadBalancer endpoint"
    info "[dry-run] no changes made"
    exit 0
  fi

  ensure_prereqs
  install_chart
  wait_for_loadbalancer || true
  print_next_steps
}

main "$@"
