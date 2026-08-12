#!/usr/bin/env bash
#
# delete-user.sh
#
# Removes the IAM user "workshop-participant-<uniqueId>" and all of its
# access keys, plus the local credentials markdown file written by
# create-user.sh.
#
# This script does NOT detach or delete the per-user policy; that is the
# job of delete-user-policy.sh. The master orchestrator delete.sh calls
# delete-user-policy.sh before delete-user.sh so the policy detaches
# cleanly. When this script is run on its own, any still-attached policy
# will cause `aws iam delete-user` to fail.
#
# Usage:
#   ./setup-class/eks/delete-user.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - One of the following authentication methods:
#       * AWS_PROFILE pointing to a configured AWS CLI profile, OR
#       * AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optional
#         AWS_SESSION_TOKEN) for direct credential injection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/workshop-participant-IAM.md"

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
# Delete access keys
# ---------------------------------------------------------------------------
echo "Looking up access keys for '${USER_NAME}'..."
ACCESS_KEYS_JSON="$(aws "${AWS_PROFILE_ARGS[@]}" iam list-access-keys \
    --user-name "${USER_NAME}" \
    --output json 2>/dev/null || true)"

if [ -n "${ACCESS_KEYS_JSON}" ]; then
    FOUND_KEYS=false
    while IFS= read -r key_id; do
        [ -n "${key_id}" ] || continue
        FOUND_KEYS=true
        echo "  Deleting access key ${key_id}..."
        aws "${AWS_PROFILE_ARGS[@]}" iam delete-access-key \
            --user-name "${USER_NAME}" \
            --access-key-id "${key_id}"
    done < <(printf '%s' "${ACCESS_KEYS_JSON}" | python3 -c 'import sys, json; data=json.load(sys.stdin); [print(k["AccessKeyId"]) for k in data.get("AccessKeyMetadata", [])]')

    if [ "${FOUND_KEYS}" = false ]; then
        echo "  No access keys found."
    fi
else
    echo "  Could not list access keys (user may not exist)."
fi

# ---------------------------------------------------------------------------
# Delete the IAM user
# ---------------------------------------------------------------------------
echo "Deleting IAM user '${USER_NAME}'..."
if aws "${AWS_PROFILE_ARGS[@]}" iam delete-user --user-name "${USER_NAME}" 2>/dev/null; then
    echo "  User deleted."
else
    echo "  Could not delete user (it may not exist or has dependencies)."
fi

# ---------------------------------------------------------------------------
# Remove the local credentials file
# ---------------------------------------------------------------------------
if [ -f "${OUTPUT_FILE}" ]; then
    echo "Removing local credentials file '${OUTPUT_FILE}'..."
    rm -f "${OUTPUT_FILE}"
else
    echo "No local credentials file found at '${OUTPUT_FILE}'."
fi
