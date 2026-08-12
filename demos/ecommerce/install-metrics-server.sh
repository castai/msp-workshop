#!/usr/bin/env bash
#
# install-metrics-server.sh — Install metrics-server via Helm.
#
# Required for `kubectl top` and the HorizontalPodAutoscalers used by the
# E-commerce demo. Idempotent: if metrics-server is already
# installed and serving data (verified via `kubectl top nodes`) the script
# exits without touching anything.
#
# This script is standalone (does not depend on setup/validate-setup.sh), but
# if `helm` is missing it points the user at setup/validate-setup.sh which is
# the canonical installer in this repo.
#
# Usage:
#   ./install-metrics-server.sh

set -euo pipefail

# ANSI colors for messages. Matches the rest of msp-workshop.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[install-metrics-server]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[install-metrics-server]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[install-metrics-server]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[install-metrics-server]${NC} %s\n" "$*"; }

RELEASE_NAME="metrics-server"
CHART_REPO="metrics-server"
CHART_NAME="metrics-server/metrics-server"
CHART_NAMESPACE="kube-system"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# If metrics-server is already serving data, exit early.
metrics_server_ready() {
  kubectl top nodes >/dev/null 2>&1
}

print_banner() {
  printf '%b' "${BLUE}"
  printf '============================================================\n'
  printf '  metrics-server installer (E-commerce demo)\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'
}

main() {
  print_banner

  # 1. kubectl connectivity.
  info "checking cluster connectivity..."
  if ! kubectl cluster-info >/dev/null 2>&1; then
    err "cannot connect to a Kubernetes cluster. Check your kubeconfig."
    return 1
  fi
  log "connected to cluster"

  # 2. helm availability. The repo's validate-setup.sh installs helm; we do
  #    not silently install it here because that requires sudo and diverges
  #    from the existing setup flow.
  if ! command_exists helm; then
    err "helm is not installed."
    err "install it via: ./setup/validate-setup.sh"
    err "or visit https://helm.sh/docs/intro/install/"
    return 1
  fi
  log "helm available: $(helm version --short)"

  # 3. Already installed and serving? Exit clean.
  if metrics_server_ready; then
    log "metrics-server is already installed and serving data; nothing to do"
    kubectl top nodes || true
    return 0
  fi

  # 4. Add/update the metrics-server helm repo.
  info "adding helm repo '${CHART_REPO}'..."
  helm repo add "${CHART_REPO}" https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
  helm repo update "${CHART_REPO}" >/dev/null
  log "helm repo ready"

  # 5. Install/upgrade. Helm is idempotent on release name. If your cluster's
  #    kubelet serves a self-signed certificate, append
  #    --set args={--kubelet-insecure-tls} to the helm upgrade call below.
  log "installing metrics-server (this can take 30-60s)..."
  if ! helm upgrade --install "${RELEASE_NAME}" "${CHART_NAME}" \
        --namespace "${CHART_NAMESPACE}" \
        --wait \
        --timeout 5m; then
    err "helm install/upgrade failed"
    return 1
  fi
  log "metrics-server chart applied"

  # 6. Wait for `kubectl top nodes` to succeed (up to ~60s).
  info "waiting for metrics-server to start serving data..."
  local _attempt
  for _attempt in $(seq 1 12); do
    if metrics_server_ready; then
      log "metrics-server is ready"
      kubectl top nodes || true
      printf '\n'
      return 0
    fi
    printf '.'
    sleep 5
  done

  printf '\n'
  warn "metrics-server installed but metrics are not yet available."
  warn "give it another minute, then verify with: kubectl top nodes"
  return 0
}

main "$@"
