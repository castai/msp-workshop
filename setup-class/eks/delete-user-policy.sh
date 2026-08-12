#!/usr/bin/env bash
#
# delete-user-policy.sh
#
# Detaches the per-user IAM policy "CastAIEKSWorkshopPolicy-<uniqueId>"
# from the participant's IAM user (ignoring "not attached" errors) and
# then deletes the policy itself (ignoring "does not exist" errors).
#
# The detach step is best-effort: even if the user has already been
# removed, the policy is still deleted from the account so the cleanup
# completes cleanly on partially-failed runs.
#
# Usage:
#   ./setup-class/eks/delete-user-policy.sh <uniqueId>
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

USER_NAME="workshop-participant-${UNIQUE_ID}"
POLICY_NAME="CastAIEKSWorkshopPolicy-${UNIQUE_ID}"

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

# Resolve the AWS account ID so we can construct the policy ARN.
CALLER_IDENTITY="$(aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json)"
AWS_ACCOUNT_ID="$(printf '%s' "${CALLER_IDENTITY}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Account"])')"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

# ---------------------------------------------------------------------------
# Detach the per-user policy (best-effort)
# ---------------------------------------------------------------------------
echo "Detaching policy '${POLICY_NAME}' from '${USER_NAME}'..."
if aws "${AWS_PROFILE_ARGS[@]}" iam detach-user-policy \
    --user-name "${USER_NAME}" \
    --policy-arn "${POLICY_ARN}" 2>/dev/null; then
    echo "  Policy detached."
else
    echo "  Could not detach policy (it may not be attached or does not exist)."
fi

# ---------------------------------------------------------------------------
# Delete the policy (best-effort)
# ---------------------------------------------------------------------------
echo "Deleting policy '${POLICY_NAME}'..."
if aws "${AWS_PROFILE_ARGS[@]}" iam delete-policy \
    --policy-arn "${POLICY_ARN}" 2>/dev/null; then
    echo "  Policy deleted."
else
    echo "  Could not delete policy (it may not exist or is still attached elsewhere)."
fi
