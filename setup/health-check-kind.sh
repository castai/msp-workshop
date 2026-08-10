#!/usr/bin/env bash
#
# health-check-kind.sh — Quick health check of the MSP workshop kind cluster.
#
# Usage:
#   ./health-check-kind.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

pass() { printf "${GREEN}✅${NC} %s\n" "$*"; }
fail() { printf "${RED}❌${NC} %s\n" "$*"; ERRORS=$((ERRORS + 1)); }
warn() { printf "${YELLOW}⚠️${NC} %s\n" "$*"; WARNINGS=$((WARNINGS + 1)); }
info() { printf "${BLUE}ℹ️${NC} %s\n" "$*"; }

CLUSTER_NAME="workshop-cluster"
EXPECTED_CONTEXT="kind-workshop-cluster"

printf "==================================================\n"
printf "  MSP Workshop — kind Cluster Health Check\n"
printf "==================================================\n\n"

# 1. Docker
info "checking Docker..."
if docker info >/dev/null 2>&1; then
  pass "Docker is running"
  DOCKER_MEM="$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)"
  DOCKER_MEM_GB="$(echo "${DOCKER_MEM}" | awk '{print int($1/1024/1024/1024)}')"
  if [[ -n "${DOCKER_MEM_GB}" && "${DOCKER_MEM_GB}" -ge 8 ]]; then
    pass "Docker has ${DOCKER_MEM_GB}GB memory"
  else
    warn "Docker has only ${DOCKER_MEM_GB:-unknown}GB memory (8GB+ recommended)"
  fi
else
  fail "Docker is not running"
  exit 1
fi
printf "\n"

# 2. Cluster exists
info "checking kind cluster..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  pass "cluster '${CLUSTER_NAME}' exists"
else
  fail "cluster '${CLUSTER_NAME}' not found"
  info "run: ./install-kind.sh"
  exit 1
fi
printf "\n"

# 3. kubectl connectivity and context
info "checking kubectl connectivity..."
if kubectl cluster-info >/dev/null 2>&1; then
  pass "can connect to cluster"
else
  fail "cannot connect to cluster"
fi

CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${CONTEXT}" == "${EXPECTED_CONTEXT}" ]]; then
  pass "context is '${EXPECTED_CONTEXT}'"
else
  warn "context is '${CONTEXT}' (expected: ${EXPECTED_CONTEXT})"
fi
printf "\n"

# 4. Nodes
info "checking nodes..."
NODE_COUNT="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
READY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"

if [[ "${NODE_COUNT}" -eq 4 ]]; then
  pass "found 4 nodes"
else
  warn "found ${NODE_COUNT} nodes (expected: 4)"
fi

if [[ "${READY_NODES}" -eq "${NODE_COUNT}" && "${NODE_COUNT}" -gt 0 ]]; then
  pass "all ${NODE_COUNT} nodes are Ready"
else
  fail "only ${READY_NODES} of ${NODE_COUNT} nodes are Ready"
fi
printf "\n"

# 5. System pods
info "checking kube-system pods..."
SYSTEM_TOTAL="$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')"
SYSTEM_RUNNING="$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [[ "${SYSTEM_RUNNING}" -eq "${SYSTEM_TOTAL}" && "${SYSTEM_TOTAL}" -gt 0 ]]; then
  pass "all ${SYSTEM_TOTAL} kube-system pods are Running"
else
  warn "${SYSTEM_RUNNING} of ${SYSTEM_TOTAL} kube-system pods are Running"
fi
printf "\n"

# 6. CNI
info "checking CNI networking..."
CNI_RUNNING="$(kubectl get pods -n kube-system -l app=kindnet --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${CNI_RUNNING}" -gt 0 ]]; then
  pass "CNI (kindnet) is running"
else
  warn "CNI (kindnet) does not appear to be running"
fi
printf "\n"

# Summary
printf "==================================================\n"
if [[ "${ERRORS}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
  pass "all health checks passed — environment is ready"
  printf "==================================================\n"
  exit 0
elif [[ "${ERRORS}" -eq 0 ]]; then
  warn "health checks passed with ${WARNINGS} warning(s)"
  printf "==================================================\n"
  exit 0
else
  fail "health check failed with ${ERRORS} error(s) and ${WARNINGS} warning(s)"
  printf "==================================================\n"
  printf "Common fixes:\n"
  printf "  - Reinstall cluster: ./install-kind.sh --recreate\n"
  printf "  - See troubleshooting: exercises/common/troubleshooting.md\n"
  exit 1
fi
