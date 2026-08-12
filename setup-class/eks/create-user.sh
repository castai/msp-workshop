#!/usr/bin/env bash
#
# create-user.sh
#
# Creates an IAM user named "workshop-participant-<uniqueId>" for the EKS
# workshop and issues a fresh access key for it. Writes the credentials
# (and a placeholder for the per-user policy that will be attached by
# create.sh / create-user-policy.sh) to
# setup-class/eks/workshop-participant-IAM.md.
#
# This script does NOT create or attach the per-user policy. That is the
# job of create-user-policy.sh, which is invoked by the master orchestrator
# create.sh. After the policy is attached, create.sh will update the
# placeholders in the markdown file in place.
#
# Usage:
#   ./setup-class/eks/create-user.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - One of the following authentication methods:
#       * AWS_PROFILE pointing to a configured AWS CLI profile, OR
#       * AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optional
#         AWS_SESSION_TOKEN) for direct credential injection.
#
# Output:
#   setup-class/eks/workshop-participant-IAM.md -- contains the new access key pair
#   and placeholder rows for the policy that will be attached by create.sh.
#   This file is git-ignored via setup-class/eks/.gitignore.
#   The following machine-readable lines are printed to stdout for
#   downstream scripts (create.sh):
#       USER_NAME=workshop-participant-<uniqueId>
#       ACCESS_KEY_ID=...
#       SECRET_ACCESS_KEY=...
#       OUTPUT_FILE=setup-class/eks/workshop-participant-IAM.md

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

# Basic sanity check on the uniqueId: restrict to a safe character set so the
# constructed user name cannot be smuggled into an unexpected aws CLI call.
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

# Accept either an explicit AWS_PROFILE or direct access-key credentials.
if [ -n "${AWS_PROFILE}" ]; then
    # Verify the profile can authenticate. This also surfaces a helpful error
    # if the profile name is unknown or its credentials are expired.
    if ! aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json >/dev/null 2>&1; then
        fail "AWS profile '${AWS_PROFILE}' is set but could not authenticate. Check ~/.aws/credentials and ~/.aws/config."
    fi
elif [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    fail "Either AWS_PROFILE must be set, or both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set."
fi

# ---------------------------------------------------------------------------
# Existing-user guard
# ---------------------------------------------------------------------------
# `aws iam get-user` exits 0 when the user exists and non-zero (NoSuchEntity)
# when it does not. Using the command inside an `if` keeps `set -e` happy.
if aws "${AWS_PROFILE_ARGS[@]}" iam get-user --user-name "${USER_NAME}" --output json >/dev/null 2>&1; then
    fail "IAM user '${USER_NAME}' already exists. Aborting to avoid overwriting credentials."
fi

# ---------------------------------------------------------------------------
# Create the IAM user
# ---------------------------------------------------------------------------
echo "Creating IAM user '${USER_NAME}'..." >&2
aws "${AWS_PROFILE_ARGS[@]}" iam create-user \
    --user-name "${USER_NAME}" \
    --output json >/dev/null

# ---------------------------------------------------------------------------
# Create an access key for the new user
# ---------------------------------------------------------------------------
echo "Creating access key for '${USER_NAME}'..." >&2
ACCESS_KEY_JSON="$(aws "${AWS_PROFILE_ARGS[@]}" iam create-access-key \
    --user-name "${USER_NAME}" \
    --output json)"

ACCESS_KEY_ID="$(printf '%s' "${ACCESS_KEY_JSON}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["AccessKey"]["AccessKeyId"])')"
SECRET_ACCESS_KEY="$(printf '%s' "${ACCESS_KEY_JSON}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["AccessKey"]["SecretAccessKey"])')"
CREATED_AT="$(printf '%s' "${ACCESS_KEY_JSON}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["AccessKey"]["CreateDate"])')"

# ---------------------------------------------------------------------------
# Write the credentials markdown file
# ---------------------------------------------------------------------------
# The policy rows use sentinel placeholders that create.sh replaces in place
# after attaching the per-user policy. Using placeholders (rather than
# appending a section later) keeps the file as a single document and makes
# the script idempotent w.r.t. repeated runs by create.sh.
CREATED_AT_HUMAN="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "${OUTPUT_FILE}" <<EOF
# Workshop participant IAM credentials

> **SECURITY WARNING:** This file contains AWS access credentials. Treat it as
> secret material. Do not commit it to source control, do not paste it into
> chat or tickets, and delete it once you have stored the values in a
> secret manager or Codespaces secrets.

| Field | Value |
|-------|-------|
| User name | \`${USER_NAME}\` |
| Created at | ${CREATED_AT_HUMAN} |
| AccessKey CreateDate (AWS) | ${CREATED_AT} |
| AWS_ACCESS_KEY_ID | \`${ACCESS_KEY_ID}\` |
| AWS_SECRET_ACCESS_KEY | \`${SECRET_ACCESS_KEY}\` |
| Attached policy name | \`__POLICY_NAME__\` |
| Attached policy ARN | \`__POLICY_ARN__\` |

## Notes

- The IAM user was created. The per-user policy is created and attached by
  create.sh via create-user-policy.sh; create.sh updates the placeholders
  above with the actual values after attachment.
- The policy scopes resources to this participant's cluster and tagged
  EC2/ASG resources.
- The secret access key is shown only here. If you lose this file, delete
  the access key in the IAM console and re-run create.sh to issue a new
  pair.
- This file is matched by \`setup-class/eks/.gitignore\` (\`workshop-participant-IAM.md\`)
  so it will not be committed accidentally.
EOF

# Restrict file permissions so only the owner can read the credentials.
chmod 600 "${OUTPUT_FILE}"

# ---------------------------------------------------------------------------
# Machine-readable output for downstream callers (create.sh)
# ---------------------------------------------------------------------------
# NOTE: do not emit SECRET_ACCESS_KEY here; stdout is intended to be safe to
# display by the orchestrator. The secret is already stored in OUTPUT_FILE.
echo "USER_NAME=${USER_NAME}"
echo "ACCESS_KEY_ID=${ACCESS_KEY_ID}"
echo "OUTPUT_FILE=${OUTPUT_FILE}"

# ---------------------------------------------------------------------------
# Success summary (stderr, so stdout stays machine-parseable)
# ---------------------------------------------------------------------------
echo "" >&2
echo "User created." >&2
echo "  User name:        ${USER_NAME}" >&2
echo "  Access key ID:    ${ACCESS_KEY_ID}" >&2
echo "  Created at:       ${CREATED_AT_HUMAN}" >&2
echo "  Credentials file: ${OUTPUT_FILE}" >&2
