#!/usr/bin/env bash
#
# verify-kind.sh — Verify the MSP workshop kind cluster is ready.
#
# Usage:
#   ./verify-kind.sh

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
printf "  MSP Workshop — kind Cluster Verification\n"
printf "==================================================\n\n"

# 1. Cluster exists
info "checking cluster existence..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  pass "cluster '${CLUSTER_NAME}' exists"
else
  fail "cluster '${CLUSTER_NAME}' not found"
  info "run: ./install-kind.sh"
  exit 1
fi
printf "\n"

# 2. kubectl context
info "checking kubectl context..."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${CURRENT_CONTEXT}" == "${EXPECTED_CONTEXT}" ]]; then
  pass "kubectl context is '${EXPECTED_CONTEXT}'"
else
  warn "kubectl context is '${CURRENT_CONTEXT}', expected '${EXPECTED_CONTEXT}'"
  info "run: kubectl config use-context ${EXPECTED_CONTEXT}"
fi
printf "\n"

# 3. Connectivity
info "checking cluster connectivity..."
if kubectl cluster-info >/dev/null 2>&1; then
  pass "can connect to cluster"
else
  fail "cannot connect to cluster"
fi
printf "\n"

# 4. Nodes
info "checking nodes..."
NODE_COUNT="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
READY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"

if [[ "${NODE_COUNT}" -eq 4 ]]; then
  pass "found 4 nodes (1 control-plane + 3 workers)"
else
  warn "found ${NODE_COUNT} nodes, expected 4"
fi

if [[ "${READY_NODES}" -eq "${NODE_COUNT}" && "${NODE_COUNT}" -gt 0 ]]; then
  pass "all ${NODE_COUNT} nodes are Ready"
else
  fail "only ${READY_NODES} of ${NODE_COUNT} nodes are Ready"
fi

printf "\n"
info "node details:"
kubectl get nodes -o wide
printf "\n"

# 5. Node labels
info "checking node labels..."
CONTROL_PLANE_COUNT="$(kubectl get nodes -l workshop-role=control-plane --no-headers 2>/dev/null | wc -l | tr -d ' ')"
WORKER_COUNT="$(kubectl get nodes -l workshop-role=worker --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [[ "${CONTROL_PLANE_COUNT}" -eq 1 ]]; then
  pass "found 1 control-plane node with workshop-role label"
else
  warn "found ${CONTROL_PLANE_COUNT} control-plane nodes with workshop-role label"
fi

if [[ "${WORKER_COUNT}" -eq 3 ]]; then
  pass "found 3 worker nodes with workshop-role labels"
else
  warn "found ${WORKER_COUNT} worker nodes with workshop-role labels"
fi
printf "\n"

# 6. System pods
info "checking kube-system pods..."
SYSTEM_PODS_TOTAL="$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')"
SYSTEM_PODS_RUNNING="$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [[ "${SYSTEM_PODS_RUNNING}" -eq "${SYSTEM_PODS_TOTAL}" && "${SYSTEM_PODS_TOTAL}" -gt 0 ]]; then
  pass "all ${SYSTEM_PODS_TOTAL} kube-system pods are Running"
else
  warn "${SYSTEM_PODS_RUNNING} of ${SYSTEM_PODS_TOTAL} kube-system pods are Running"
  kubectl get pods -n kube-system
fi
printf "\n"

# 7. CNI
info "checking CNI networking..."
CNI_PODS="$(kubectl get pods -n kube-system -l app=kindnet --no-headers 2>/dev/null | wc -l | tr -d ' ')"
CNI_RUNNING="$(kubectl get pods -n kube-system -l app=kindnet --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [[ "${CNI_RUNNING}" -gt 0 ]]; then
  pass "CNI (kindnet) is running (${CNI_RUNNING}/${CNI_PODS} pods)"
else
  warn "CNI (kindnet) does not appear to be running"
fi
printf "\n"

# Summary
printf "==================================================\n"
if [[ "${ERRORS}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
  pass "all checks passed — cluster is ready"
  printf "==================================================\n"
  exit 0
elif [[ "${ERRORS}" -eq 0 ]]; then
  warn "checks passed with ${WARNINGS} warning(s)"
  printf "==================================================\n"
  exit 0
else
  fail "verification failed with ${ERRORS} error(s) and ${WARNINGS} warning(s)"
  printf "==================================================\n"
  exit 1
fi
