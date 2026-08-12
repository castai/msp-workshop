#!/usr/bin/env bash
#
# delete-eks-roles.sh
#
# Deletes the two IAM roles required by an EKS cluster for a single
# workshop participant:
#   - workshop-<uniqueId>-cluster-role
#   - workshop-<uniqueId>-nodegroup-role
#
# Managed policies must be detached before `aws iam delete-role` will
# succeed, so we list attached policies for each role and detach them
# first. Failures on detach / delete are logged but do not abort the
# script; this lets delete.sh complete a best-effort teardown even when
# intermediate resources are already gone.
#
# Usage:
#   ./setup-class/eks/delete-eks-roles.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - One of the following authentication methods:
#       * AWS_PROFILE pointing to a configured AWS CLI profile, OR
#       * AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optional
#         AWS_SESSION_TOKEN) for direct credential injection.

set -euo pipefail

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ "$#" -ne 1 ]; then
    fail "Usage: $0 <uniqueId>  (expected exactly one positional argument)"
fi

UNIQUE_ID="$1"
if [ -z "${UNIQUE_ID}" ]; then
    fail "uniqueId must not be empty"
fi

if ! [[ "${UNIQUE_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "uniqueId must match [A-Za-z0-9._-]+  (got: '${UNIQUE_ID}')"
fi

CLUSTER_ROLE_NAME="workshop-${UNIQUE_ID}-cluster-role"
NODEGROUP_ROLE_NAME="workshop-${UNIQUE_ID}-nodegroup-role"

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
# Delete a role after detaching its managed policies
# ---------------------------------------------------------------------------
delete_role_with_managed_policies() {
    local role_name="$1"

    if ! aws "${AWS_PROFILE_ARGS[@]}" iam get-role \
        --role-name "${role_name}" \
        --output json >/dev/null 2>&1; then
        echo "  Role '${role_name}' does not exist; skipping."
        return 0
    fi

    echo "  Detaching managed policies from '${role_name}'..."
    local attached_json
    attached_json="$(aws "${AWS_PROFILE_ARGS[@]}" iam list-attached-role-policies \
        --role-name "${role_name}" \
        --output json 2>/dev/null || true)"

    if [ -n "${attached_json}" ]; then
        while IFS= read -r policy_arn; do
            [ -n "${policy_arn}" ] || continue
            echo "    Detaching ${policy_arn}..."
            aws "${AWS_PROFILE_ARGS[@]}" iam detach-role-policy \
                --role-name "${role_name}" \
                --policy-arn "${policy_arn}" >/dev/null 2>&1 || true
        done < <(printf '%s' "${attached_json}" | python3 -c 'import sys, json; data=json.load(sys.stdin); [print(p["PolicyArn"]) for p in data.get("AttachedPolicies", [])]')
    fi

    echo "  Deleting role '${role_name}'..."
    if aws "${AWS_PROFILE_ARGS[@]}" iam delete-role \
        --role-name "${role_name}" 2>/dev/null; then
        echo "    Role deleted."
    else
        echo "    Could not delete role (it may have inline policies or be in use)."
    fi
}

echo "Deleting IAM role '${CLUSTER_ROLE_NAME}'..."
delete_role_with_managed_policies "${CLUSTER_ROLE_NAME}"

echo ""
echo "Deleting IAM role '${NODEGROUP_ROLE_NAME}'..."
delete_role_with_managed_policies "${NODEGROUP_ROLE_NAME}"
