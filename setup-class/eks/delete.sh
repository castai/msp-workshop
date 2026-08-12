#!/usr/bin/env bash
#
# delete.sh
#
# Master orchestrator that tears down all AWS resources for one workshop
# participant, in reverse dependency order so the IAM / cluster pieces
# come apart cleanly:
#
#   1. delete-eks-cluster.sh    -> EKS cluster + its generated YAML config
#   2. delete-eks-roles.sh      -> cluster + nodegroup IAM roles
#   3. delete-user-policy.sh    -> detach + delete per-user policy
#   4. delete-user.sh           -> access keys + IAM user + credentials file
#
# Each child script is best-effort: missing / already-deleted resources
# are logged but do not abort the orchestrator. The cluster is deleted
# FIRST so eksctl can drop the nodegroup + cluster service roles it
# adopted before delete-eks-roles.sh runs.
#
# Usage:
#   ./setup-class/eks/delete.sh <uniqueId>
#   ./setup-class/eks/delete.sh --yes <uniqueId>     # skip interactive confirmation
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - eksctl on PATH (only needed when a cluster exists to delete)
#   - AWS_REGION must be set if a cluster is to be deleted
#   - One of the following authentication methods:
#       * AWS_PROFILE pointing to a configured AWS CLI profile, OR
#       * AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optional
#         AWS_SESSION_TOKEN) for direct credential injection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CONFIRMED=false

if [ "$#" -ge 2 ] && [ "$1" = "--yes" ]; then
    CONFIRMED=true
    shift
fi

if [ "$#" -ne 1 ]; then
    fail "Usage: $0 [--yes] <uniqueId>"
fi

UNIQUE_ID="$1"
if [ -z "${UNIQUE_ID}" ]; then
    fail "uniqueId must not be empty"
fi

if ! [[ "${UNIQUE_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "uniqueId must match [A-Za-z0-9._-]+  (got: '${UNIQUE_ID}')"
fi

USER_NAME="workshop-participant-${UNIQUE_ID}"
POLICY_NAME="CastAIEKSWorkshopPolicy-${UNIQUE_ID}"
CLUSTER_NAME="workshop-${UNIQUE_ID}"
CLUSTER_ROLE_NAME="workshop-${UNIQUE_ID}-cluster-role"
NODEGROUP_ROLE_NAME="workshop-${UNIQUE_ID}-nodegroup-role"
EKSCTL_CONFIG_FILE="${SCRIPT_DIR}/${CLUSTER_NAME}-eksctl.yaml"
OUTPUT_FILE="${SCRIPT_DIR}/workshop-participant-IAM.md"

# ---------------------------------------------------------------------------
# AWS CLI profile / credential handling
# ---------------------------------------------------------------------------
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_PROFILE_ARGS=()
if [ -n "${AWS_PROFILE}" ]; then
    AWS_PROFILE_ARGS=(--profile "${AWS_PROFILE}")
fi

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
    fail "AWS CLI (aws) is not installed or not on PATH"
fi

if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is not installed or not on PATH (required for JSON parsing)"
fi

if [ -n "${AWS_PROFILE}" ]; then
    if ! aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json >/dev/null 2>&1; then
        fail "AWS profile '${AWS_PROFILE}' is set but could not authenticate. Check ~/.aws/credentials and ~/.aws/config."
    fi
elif [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    fail "Either AWS_PROFILE must be set, or both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set."
fi

# ---------------------------------------------------------------------------
# Confirm destructive action
# ---------------------------------------------------------------------------
if [ "${CONFIRMED}" = false ]; then
    echo "This will permanently delete:"
    echo "  - EKS cluster: ${CLUSTER_NAME} (via eksctl, if it exists)"
    echo "  - Generated eksctl config file: ${EKSCTL_CONFIG_FILE}"
    echo "  - IAM roles: ${CLUSTER_ROLE_NAME}, ${NODEGROUP_ROLE_NAME}"
    echo "  - IAM policy: ${POLICY_NAME}"
    echo "  - IAM user: ${USER_NAME}"
    echo "  - All access keys attached to that user"
    echo "  - Local file: ${OUTPUT_FILE}"
    echo ""
    read -rp "Are you sure? Type 'yes' to proceed: " answer
    if [ "${answer}" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Step 1: delete the EKS cluster (and its generated eksctl config)
# ---------------------------------------------------------------------------
echo "============================================================"
echo "Step 1/5: deleting EKS cluster"
echo "============================================================"
bash "${SCRIPT_DIR}/delete-eks-cluster.sh" "${UNIQUE_ID}"

# ---------------------------------------------------------------------------
# Step 2: delete the EKS IAM roles
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 2/5: deleting EKS IAM roles"
echo "============================================================"
bash "${SCRIPT_DIR}/delete-eks-roles.sh" "${UNIQUE_ID}"

# ---------------------------------------------------------------------------
# Step 3: detach and delete the per-user policy
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 3/5: deleting per-user IAM policy"
echo "============================================================"
bash "${SCRIPT_DIR}/delete-user-policy.sh" "${UNIQUE_ID}"

# ---------------------------------------------------------------------------
# Step 4: delete the IAM user (access keys + user + credentials file)
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 4/5: deleting IAM user"
echo "============================================================"
bash "${SCRIPT_DIR}/delete-user.sh" "${UNIQUE_ID}"

# ---------------------------------------------------------------------------
# Step 5: remove participant env example file from the repo root
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 5/5: removing env example file"
echo "============================================================"
ENV_FILE="${REPO_ROOT}/.env.${UNIQUE_ID}"
if [ -f "${ENV_FILE}" ]; then
    rm -f "${ENV_FILE}"
    echo "  Removed ${ENV_FILE}."
else
    echo "  Env file '${ENV_FILE}' not found; skipping."
fi

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
cat <<EOF

============================================================
Cleanup finished for '${UNIQUE_ID}'
============================================================
  EKS cluster:   ${CLUSTER_NAME}     (best effort)
  IAM roles:     ${CLUSTER_ROLE_NAME}, ${NODEGROUP_ROLE_NAME}   (best effort)
  IAM policy:    ${POLICY_NAME}      (best effort)
  IAM user:      ${USER_NAME}        (best effort)
  Local file:    ${OUTPUT_FILE}      (best effort)
  Env handoff:   ${REPO_ROOT}/.env.${UNIQUE_ID}   (best effort)
EOF
