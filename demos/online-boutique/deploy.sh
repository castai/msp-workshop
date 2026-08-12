#!/usr/bin/env bash
#
# deploy.sh — Idempotent deploy of the Online Boutique demo.
#
# Pipeline:
#   1. Verify kubectl, helm, and cluster reachability.
#   2. Run helm upgrade --install of the wrapper chart.
#   3. Wait for the LoadBalancer Service to get an endpoint.
#   4. Print the public URL and verification commands.
#
# Usage:
#   ./deploy.sh
#   ./deploy.sh --dry-run   print the helm command and exit; do not deploy

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

RELEASE="online-boutique"
NAMESPACE="online-boutique"
FRONTEND_SERVICE="${RELEASE}-frontend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/online-boutique"

# Maximum time to wait for the LoadBalancer Service to receive an endpoint.
LB_WAIT_SECONDS=300
# Polling interval for the LB endpoint wait.
LB_POLL_SECONDS=5

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_banner() {
  printf '%b' "${BOLD}${BLUE}"
  printf '============================================================\n'
  printf '  Online Boutique demo - deploy\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'
}

ensure_prereqs() {
  if ! command_exists kubectl; then
    err "kubectl is not installed. Run ./setup/validate-setup.sh first."
    return 1
  fi

  if ! command_exists helm; then
    err "helm is not installed. Run ./setup/validate-setup.sh first."
    return 1
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    err "cannot connect to a Kubernetes cluster. Check your kubeconfig."
    return 1
  fi
  log "connected to cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
}

helm_command() {
  printf 'helm upgrade --install %s %s \\\n' "${RELEASE}" "./online-boutique"
  printf '  --namespace %s --create-namespace --wait --timeout 10m\n' "${NAMESPACE}"
}

run_helm_install() {
  info "installing chart ${CHART_DIR} as release '${RELEASE}' in namespace '${NAMESPACE}'..."
  if ! helm upgrade --install "${RELEASE}" "${CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout 10m; then
    err "helm upgrade --install failed for release '${RELEASE}'"
    return 1
  fi
  log "helm release '${RELEASE}' is ready"
}

wait_for_lb_endpoint() {
  info "waiting up to ${LB_WAIT_SECONDS}s for LoadBalancer Service ${FRONTEND_SERVICE} to receive an endpoint..."
  local elapsed=0
  local ingress
  while [[ ${elapsed} -lt ${LB_WAIT_SECONDS} ]]; do
    if ! kubectl get svc "${FRONTEND_SERVICE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      err "service/${FRONTEND_SERVICE} not found in namespace '${NAMESPACE}'"
      return 1
    fi

    ingress="$(kubectl get svc "${FRONTEND_SERVICE}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.loadBalancer.ingress}' 2>/dev/null || true)"
    if [[ -n "${ingress}" && "${ingress}" != "[]" ]]; then
      log "service/${FRONTEND_SERVICE} has an endpoint: ${ingress}"
      return 0
    fi

    if (( elapsed % 30 == 0 )); then
      info "  ...still waiting (${elapsed}s elapsed)"
    fi
    sleep "${LB_POLL_SECONDS}"
    elapsed=$((elapsed + LB_POLL_SECONDS))
  done

  err "service/${FRONTEND_SERVICE} did not receive an endpoint within ${LB_WAIT_SECONDS}s"
  err "current status:"
  kubectl get svc "${FRONTEND_SERVICE}" -n "${NAMESPACE}" || true
  return 1
}

print_next_steps() {
  local public_url
  public_url="$(kubectl get svc "${FRONTEND_SERVICE}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -z "${public_url}" ]]; then
    public_url="$(kubectl get svc "${FRONTEND_SERVICE}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  fi

  printf '\n%b' "${BOLD}${GREEN}"
  printf '============================================================\n'
  printf '  Online Boutique demo is deployed\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'

  if [[ -n "${public_url}" ]]; then
    printf 'Public URL (LoadBalancer):\n'
    printf '  http://%s\n' "${public_url}"
    printf '\n'
  else
    warn 'public LoadBalancer endpoint is not yet available.'
    warn 're-run the command below once AWS has finished provisioning.'
    printf '\n'
  fi

  printf 'Verify deployment:\n'
  printf '  kubectl get pods -n %s\n' "${NAMESPACE}"
  printf '  kubectl get svc -n %s\n' "${NAMESPACE}"
  printf '\n'

  printf 'Inspect the frontend Service and its public URL:\n'
  printf '  kubectl get svc %s -n %s\n' "${FRONTEND_SERVICE}" "${NAMESPACE}"
  local _jqpath
  _jqpath='{.status.loadBalancer.ingress[0].hostname}'
  printf '  kubectl get svc %s -n %s -o jsonpath=%s\n' \
    "${FRONTEND_SERVICE}" "${NAMESPACE}" "'${_jqpath}'"
  printf '\n'

  printf 'In-cluster URL (use this from Locust or other pods):\n'
  printf '  http://%s.%s.svc.cluster.local:80\n' "${FRONTEND_SERVICE}" "${NAMESPACE}"
  printf '\n'

  printf 'Port-forward fallback (e.g. for local browsing):\n'
  printf '  kubectl port-forward -n %s svc/%s 8080:80\n' "${NAMESPACE}" "${FRONTEND_SERVICE}"
  printf '  curl http://localhost:8080\n'
  printf '\n'

  printf 'Generate load with the shared Locust demo:\n'
  printf '  see ../locust/README.md (in-cluster target:\n'
  printf '  http://%s.%s.svc.cluster.local:80,  user class: BoutiqueUser)\n' \
    "${FRONTEND_SERVICE}" "${NAMESPACE}"
  printf '\n'

  printf 'Tear down when done (removes the namespace and its LoadBalancer):\n'
  printf '  ./teardown.sh\n'
  printf '  ./teardown.sh --yes   skip the confirmation prompt\n'
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
        printf '  --dry-run   print the helm command and exit; do not deploy\n'
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
    # In dry-run we only need kubectl/helm present so we can confirm the
    # command we are about to print is what they would run; we deliberately
    # skip the cluster-connectivity check because dry-run must work without
    # an active cluster.
    if ! command_exists kubectl; then
      err "kubectl is not installed. Run ./setup/validate-setup.sh first."
      return 1
    fi
    if ! command_exists helm; then
      err "helm is not installed. Run ./setup/validate-setup.sh first."
      return 1
    fi
    info '--dry-run set; printing helm command and exiting.'
    printf '\n'
    helm_command
    printf '\n'
    log 'dry-run complete; nothing was applied.'
    exit 0
  fi

  ensure_prereqs
  run_helm_install
  wait_for_lb_endpoint || true

  print_next_steps
}

main "$@"
