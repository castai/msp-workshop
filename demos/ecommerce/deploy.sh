#!/usr/bin/env bash
#
# deploy.sh — Idempotent deploy of the E-commerce demo.
#
# Pipeline:
#   1. Verify the cluster is reachable.
#   2. Create the demo-ecommerce namespace (idempotent).
#   3. Install metrics-server via install-metrics-server.sh (idempotent).
#   4. Apply all manifests under manifests/.
#   5. Wait for deployments to be ready.
#   6. Wait for the HPAs to exist.
#   7. Print verification + port-forward commands.
#
# Usage:
#   ./deploy.sh

set -euo pipefail

# ANSI colors for messages. Matches setup/*.sh.
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

NAMESPACE="demo-ecommerce"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

# Deployments to wait on. Order does not matter; kubectl waits per-resource.
DEPLOYMENTS=(
  web-frontend
  order-service
  notification-service
  load-generator
)

# HPAs to wait on.
HPAS=(
  web-frontend
  order-service
)

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_banner() {
  printf '%b' "${BOLD}${BLUE}"
  printf '============================================================\n'
  printf '  E-commerce demo — deploy\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'
}

ensure_prereqs() {
  if ! command_exists kubectl; then
    err "kubectl is not installed. Run ./setup/setup-all.sh first."
    return 1
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    err "cannot connect to a Kubernetes cluster. Check your kubeconfig."
    return 1
  fi
  log "connected to cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
}

create_namespace() {
  info "ensuring namespace '${NAMESPACE}' exists..."
  if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    log "namespace '${NAMESPACE}' already exists"
  else
    kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"
    log "namespace '${NAMESPACE}' created"
  fi
}

install_metrics_server() {
  info "ensuring metrics-server is available (needed for HPA + kubectl top)..."
  if ! bash "${SCRIPT_DIR}/install-metrics-server.sh"; then
    err "metrics-server install failed. HPAs will not scale."
    err "fix the issue and re-run ./deploy.sh"
    return 1
  fi
}

apply_manifests() {
  info "applying manifests in ${MANIFESTS_DIR}..."
  kubectl apply -f "${MANIFESTS_DIR}/"
  printf '\n'
}

wait_for_deployments() {
  local deploy
  for deploy in "${DEPLOYMENTS[@]}"; do
    info "waiting for deployment/${deploy} to be ready..."
    if ! kubectl wait --for=condition=available \
          --timeout=180s \
          -n "${NAMESPACE}" \
          "deployment/${deploy}" >/dev/null; then
      err "deployment/${deploy} did not become available in 180s"
      err "current status:"
      kubectl get pods -n "${NAMESPACE}" -l "app=${deploy}" || true
      return 1
    fi
    log "deployment/${deploy} is ready"
  done
}

wait_for_hpas() {
  local hpa
  for hpa in "${HPAS[@]}"; do
    info "waiting for hpa/${hpa} to be registered..."
    local _attempt
    for _attempt in $(seq 1 30); do
      if kubectl get hpa "${hpa}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        log "hpa/${hpa} is registered"
        break
      fi
      sleep 2
    done
    if ! kubectl get hpa "${hpa}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      err "hpa/${hpa} did not appear within 60s"
      return 1
    fi
  done
}

print_next_steps() {
  printf '\n%b' "${BOLD}${GREEN}"
  printf '============================================================\n'
  printf '  E-commerce demo is deployed\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'

  printf 'Verify deployment:\n'
  printf '  kubectl get pods -n %s\n' "${NAMESPACE}"
  printf '  kubectl get hpa -n %s\n' "${NAMESPACE}"
  printf '  kubectl get pdb -n %s\n' "${NAMESPACE}"
  printf '  kubectl top pods -n %s\n' "${NAMESPACE}"
  printf '\n'

  printf 'Watch HPA scale under load (give it 3-5 minutes):\n'
  printf '  kubectl get hpa -n %s -w\n' "${NAMESPACE}"
  printf '\n'

  printf 'Access services via port-forward (each in its own terminal):\n'
  printf '  kubectl port-forward -n %s svc/web-frontend 8080:80\n' "${NAMESPACE}"
  printf '  kubectl port-forward -n %s svc/order-service 8081:80\n' "${NAMESPACE}"
  printf '  kubectl port-forward -n %s svc/notification-service 8082:80\n' "${NAMESPACE}"
  printf '\n'
  printf 'Then in another terminal:\n'
  printf '  curl http://localhost:8080\n'
  printf '  curl http://localhost:8081\n'
  printf '  curl http://localhost:8082\n'
  printf '\n'

  printf 'Tail the load generator logs to confirm traffic:\n'
  printf '  kubectl logs -n %s -l app=load-generator -f --tail=20\n' "${NAMESPACE}"
  printf '\n'

  printf 'Tear down when done (keeps metrics-server in place):\n'
  printf '  ./teardown.sh\n'
  printf '\n'
}

main() {
  print_banner

  ensure_prereqs
  create_namespace
  install_metrics_server
  apply_manifests
  wait_for_deployments
  wait_for_hpas

  print_next_steps
}

main "$@"
