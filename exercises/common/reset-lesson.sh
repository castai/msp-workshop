#!/usr/bin/env bash
#
# reset-lesson.sh — Reset a single lesson namespace while leaving the cluster intact.
#
# Usage:
#   ./reset-lesson.sh <namespace>
#
# The script deletes the namespace, waits for its removal, then recreates it
# empty so the lesson can be re-applied from a clean state.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[reset-lesson]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[reset-lesson]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[reset-lesson]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[reset-lesson]${NC} %s\n" "$*"; }

# Namespaces that must never be deleted.
is_protected_namespace() {
  local ns="$1"
  case "${ns}" in
    default | kube-system | kube-public | kube-node-lease)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

list_lesson_namespaces() {
  kubectl get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep -E '^lesson-' || true
}

usage() {
  printf 'Usage: %s <namespace>\n' "$0"
  printf '\n'
  printf 'Resets a lesson namespace by deleting and recreating it.\n'
  printf 'The Kubernetes cluster itself is left untouched.\n'
  printf '\n'
  printf 'Examples:\n'
  printf '  %s lesson-01-workloads\n' "$0"
  printf '  %s lesson-02-networking\n' "$0"
  printf '\n'
  local lesson_ns
  lesson_ns="$(list_lesson_namespaces)"
  if [[ -n "${lesson_ns}" ]]; then
    printf 'Current lesson namespaces:\n'
    printf '%s\n' "${lesson_ns}"
  else
    printf 'No namespaces with the "lesson-" prefix currently exist.\n'
  fi
}

main() {
  if [[ "$#" -ne 1 ]]; then
    usage
    exit 1
  fi

  local namespace="$1"

  if [[ -z "${namespace}" ]]; then
    err "namespace argument is empty"
    usage
    exit 1
  fi

  if is_protected_namespace "${namespace}"; then
    err "refusing to delete protected namespace: ${namespace}"
    exit 1
  fi

  log "resetting namespace: ${namespace}"

  if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
    warn "namespace ${namespace} does not exist; creating it empty"
    kubectl create namespace "${namespace}"
    log "namespace ${namespace} created"
    exit 0
  fi

  info "deleting namespace ${namespace}..."
  kubectl delete namespace "${namespace}" --wait=false

  info "waiting for namespace ${namespace} to be removed..."
  if ! kubectl wait --for=delete namespace "${namespace}" --timeout=120s >/dev/null 2>&1; then
    err "timed out waiting for namespace ${namespace} to be deleted"
    exit 1
  fi

  info "recreating namespace ${namespace}..."
  kubectl create namespace "${namespace}"

  log "namespace ${namespace} has been reset"
}

main "$@"
