#!/usr/bin/env bash
#
# deploy.sh — Idempotent deploy of the shared Locust load generator.
#
# Locust is shared across every demo in this workshop (ecommerce,
# online-boutique, bank-of-anthos). One instance, one LoadBalancer, one URL.
# Workshop users enter the target application's URL directly in the Locust
# web UI.
#
# Pipeline:
#   1. Verify kubectl/helm and cluster reachability.
#   2. helm upgrade --install the locust chart into the 'locust' namespace.
#   3. Wait for the LoadBalancer Service to receive an endpoint (hostname/IP).
#   4. Print the public Locust UI URL and a port-forward fallback command.
#
# Usage:
#   ./deploy.sh            # full deploy
#   ./deploy.sh --dry-run  # print the helm command and exit (no cluster changes)

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

RELEASE="locust"
NAMESPACE="locust"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/locust"

DRY_RUN=0

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_banner() {
  printf '%b' "${BOLD}${BLUE}"
  printf '============================================================\n'
  printf '  Locust (shared load generator) — deploy\n'
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

build_helm_command() {
  printf 'helm upgrade --install %s %s --namespace %s --create-namespace --wait --timeout 5m' \
    "${RELEASE}" "${CHART_DIR}" "${NAMESPACE}"
}

run_helm() {
  info "running: $(build_helm_command)"
  if ! helm upgrade --install "${RELEASE}" "${CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout 5m; then
    err "helm upgrade --install failed."
    err "check helm output above and the cluster state."
    return 1
  fi
}

wait_for_loadbalancer() {
  info "waiting up to 5 minutes for LoadBalancer Service '${RELEASE}' to get an endpoint..."
  local _attempt _max_attempts _status
  _max_attempts=60  # 60 * 5s = 300s
  for _attempt in $(seq 1 "${_max_attempts}"); do
    _status="$(kubectl get svc "${RELEASE}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.loadBalancer.ingress}' 2>/dev/null || true)"
    if [[ -n "${_status}" && "${_status}" != "[]" && "${_status}" != "null" ]]; then
      printf '\n'
      log "LoadBalancer endpoint is ready: ${_status}"
      return 0
    fi
    printf '.'
    sleep 5
  done
  printf '\n'
  warn "timed out waiting for LoadBalancer endpoint after 5 minutes."
  warn "the Service is created but the cloud provider has not assigned an address yet."
  warn "check: kubectl get svc ${RELEASE} -n ${NAMESPACE}"
  warn "you can still reach Locust via port-forward (see fallback below)."
  return 1
}

get_loadbalancer_endpoint() {
  kubectl get svc "${RELEASE}" -n "${NAMESPACE}" \
    -o jsonpath='{range .status.loadBalancer.ingress[*]}{.hostname}{.ip}{"\n"}{end}' \
    | awk 'NF{print; exit}'
}

print_next_steps() {
  local endpoint="$1"
  printf '\n%b' "${BOLD}${GREEN}"
  printf '============================================================\n'
  printf '  Locust is deployed\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'

  if [[ -n "${endpoint}" ]]; then
    printf 'Open the Locust web UI:\n'
    printf '  http://%s:8089\n' "${endpoint}"
  else
    printf 'Locust web UI (public URL not yet available):\n'
    printf '  http://<pending>:8089\n'
    printf '  watch it appear: kubectl get svc %s -n %s -w\n' "${RELEASE}" "${NAMESPACE}"
  fi
  printf '\n'

  printf 'Port-forward fallback (works even without a LoadBalancer endpoint):\n'
  printf '  kubectl port-forward -n %s svc/%s 8089:8089\n' "${NAMESPACE}" "${RELEASE}"
  printf '  then open http://localhost:8089\n'
  printf '\n'

  printf 'In the Locust web UI:\n'
  printf '  1. Enter the target application URL in the "Host" field.\n'
  printf '     Examples (in-cluster):\n'
  printf '       http://web-frontend.demo-ecommerce.svc.cluster.local:80\n'
  printf '       http://online-boutique-frontend.online-boutique.svc.cluster.local:80\n'
  printf '       http://frontend.bank-of-anthos.svc.cluster.local:80\n'
  printf '  2. Pick a user class that matches the target:\n'
  printf '       BoutiqueUser  -> Online Boutique product/cart/checkout flow\n'
  printf '       BankUser      -> Bank of Anthos login/dashboard flow\n'
  printf '       GenericUser   -> GET / repeatedly; works against any frontend\n'
  printf '  3. Set Number of users + Spawn rate, then click "Start swarming".\n'
  printf '\n'

  printf 'Verify the deployment:\n'
  printf '  kubectl get pods -n %s\n' "${NAMESPACE}"
  printf '  kubectl get svc -n %s\n' "${NAMESPACE}"
  printf '\n'

  printf 'Tear down when done:\n'
  printf '  ./teardown.sh\n'
  printf '  ./teardown.sh --yes   # skip the confirmation prompt\n'
  printf '\n'

  printf 'Note: the Locust web UI has no authentication. Acceptable for a\n'
  printf 'workshop; do not expose this Service to the public internet in\n'
  printf 'a real environment.\n'
  printf '\n'
}

main() {
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        printf 'Usage: %s [--dry-run]\n' "$0"
        printf '  --dry-run   print the helm command and exit (no cluster changes)\n'
        exit 0
        ;;
      *)
        err "unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  print_banner

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    # In dry-run, only verify the binaries exist; skip the cluster check so
    # this works without an active kubeconfig.
    if ! command_exists kubectl; then
      err "kubectl is not installed."
      exit 1
    fi
    if ! command_exists helm; then
      err "helm is not installed."
      exit 1
    fi
    info "[dry-run] would run: $(build_helm_command)"
    info "[dry-run] would wait for LoadBalancer endpoint on svc/${RELEASE} in ns/${NAMESPACE}"
    info "[dry-run] no changes made. exiting cleanly."
    exit 0
  fi

  ensure_prereqs

  run_helm

  local endpoint=""
  if wait_for_loadbalancer; then
    endpoint="$(get_loadbalancer_endpoint || true)"
  fi

  print_next_steps "${endpoint}"
}

main "$@"
