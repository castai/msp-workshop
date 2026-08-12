#!/usr/bin/env bash
#
# create.sh
#
# Master orchestrator that provisions all AWS resources for one workshop
# participant, in dependency order:
#
#   1. create-user.sh         -> IAM user + access key
#   2. create-user-policy.sh  -> per-user policy (created or reused)
#   3. (here)                 -> attach the policy to the user, then
#                                fill in the policy placeholders in the
#                                credentials markdown.
#   4. create-eks-roles.sh    -> cluster + nodegroup IAM roles
#   5. create-eks-cluster.sh  -> EKS cluster via eksctl + aws-auth mapping
#
# Usage:
#   ./setup-class/eks/create.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - eksctl on PATH (only needed when create-eks-cluster.sh runs)
#   - AWS_REGION must be set (or available via `aws configure get region`)
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

# Resolve AWS region once so each child script does not have to re-resolve
# it; pass it explicitly so behaviour does not silently change if a child's
# resolution path returns something different.
AWS_REGION="${AWS_REGION:-}"
if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="$(aws "${AWS_PROFILE_ARGS[@]}" configure get region 2>/dev/null || true)"
    # Trim whitespace in case the AWS CLI returned extra padding.
    AWS_REGION="$(printf '%s' "${AWS_REGION}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -z "${AWS_REGION}" ]; then
    fail "AWS_REGION is not set and could not be determined from the AWS CLI configuration."
fi

# Defensive: reject regions with unexpected characters early so child scripts
# don't receive a corrupted value.
if [[ "${AWS_REGION}" =~ [^a-z0-9-] ]]; then
    fail "AWS_REGION contains invalid characters: '${AWS_REGION}'. Expected a value like 'us-east-1'."
fi

export AWS_REGION

# ---------------------------------------------------------------------------
# Helper: parse KEY=VALUE lines emitted by child scripts.
# ---------------------------------------------------------------------------
# Child scripts print machine-readable lines like `USER_NAME=...` to
# stdout. We capture full stdout (so progress lines remain visible) and
# then extract KEY=VALUE pairs into the parent shell.
#
# Usage:
#   eval "$(parse_kv_lines <(child_output))"
parse_kv_lines() {
    # Only accept simple, well-formed KEY=VALUE tokens where KEY matches
    # uppercase letters / underscores. This deliberately rejects anything
    # that could be smuggled in via output that looks like a command.
    grep -E '^[A-Z][A-Z0-9_]*=' "$1" || true
}

# ---------------------------------------------------------------------------
# Step 1: create the IAM user and access key
# ---------------------------------------------------------------------------
echo "============================================================"
echo "Step 1/5: creating IAM user and access key"
echo "============================================================"
USER_OUTPUT_FILE="$(mktemp)"
trap 'rm -f "${USER_OUTPUT_FILE}"' EXIT

bash "${SCRIPT_DIR}/create-user.sh" "${UNIQUE_ID}" > "${USER_OUTPUT_FILE}"

USER_KV="$(mktemp)"
trap 'rm -f "${USER_OUTPUT_FILE}" "${USER_KV}"' EXIT
parse_kv_lines "${USER_OUTPUT_FILE}" > "${USER_KV}"

# shellcheck disable=SC1090
USER_NAME="$(grep '^USER_NAME=' "${USER_KV}" | head -n1 | cut -d= -f2-)"
ACCESS_KEY_ID="$(grep '^ACCESS_KEY_ID=' "${USER_KV}" | head -n1 | cut -d= -f2-)"
OUTPUT_FILE="$(grep '^OUTPUT_FILE=' "${USER_KV}" | head -n1 | cut -d= -f2-)"

if [ -z "${USER_NAME:-}" ] || [ -z "${ACCESS_KEY_ID:-}" ] || [ -z "${OUTPUT_FILE:-}" ]; then
    fail "create-user.sh did not emit the expected USER_NAME / ACCESS_KEY_ID / OUTPUT_FILE lines."
fi

# The secret access key is stored only in the markdown credentials file and
# in the generated .env.<uniqueId> handoff file. It is never printed to stdout.
if [ -f "${OUTPUT_FILE}" ]; then
    SECRET_ACCESS_KEY="$(grep -E '^\| AWS_SECRET_ACCESS_KEY \|' "${OUTPUT_FILE}" | sed -E 's/^.*\| `([^`]+)` \|$/\1/')"
else
    fail "Credentials file '${OUTPUT_FILE}' was not created by create-user.sh."
fi

if [ -z "${SECRET_ACCESS_KEY:-}" ]; then
    fail "Could not extract AWS_SECRET_ACCESS_KEY from '${OUTPUT_FILE}'."
fi

# ---------------------------------------------------------------------------
# Step 2: create (or reuse) the per-user policy
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 2/5: creating per-user IAM policy"
echo "============================================================"
POLICY_OUTPUT_FILE="$(mktemp)"
trap 'rm -f "${USER_OUTPUT_FILE}" "${USER_KV}" "${POLICY_OUTPUT_FILE}" "${POLICY_KV:-}"' EXIT

bash "${SCRIPT_DIR}/create-user-policy.sh" "${UNIQUE_ID}" > "${POLICY_OUTPUT_FILE}"
cat "${POLICY_OUTPUT_FILE}"

POLICY_KV="$(mktemp)"
trap 'rm -f "${USER_OUTPUT_FILE}" "${USER_KV}" "${POLICY_OUTPUT_FILE}" "${POLICY_KV}"' EXIT
parse_kv_lines "${POLICY_OUTPUT_FILE}" > "${POLICY_KV}"

POLICY_ARN="$(grep '^POLICY_ARN=' "${POLICY_KV}" | head -n1 | cut -d= -f2-)"
POLICY_NAME="CastAIEKSWorkshopPolicy-${UNIQUE_ID}"

if [ -z "${POLICY_ARN:-}" ]; then
    fail "create-user-policy.sh did not emit the expected POLICY_ARN line."
fi

# ---------------------------------------------------------------------------
# Step 3: attach the policy to the user, then update the markdown
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 3/5: attaching policy '${POLICY_NAME}' to '${USER_NAME}'"
echo "============================================================"
aws "${AWS_PROFILE_ARGS[@]}" iam attach-user-policy \
    --user-name "${USER_NAME}" \
    --policy-arn "${POLICY_ARN}"

# Replace the placeholder rows created by create-user.sh with the real
# policy name and ARN. Using a fixed-string sed replacement keeps the
# substitution safe even if POLICY_ARN contained regex metacharacters.
if [ -f "${OUTPUT_FILE}" ]; then
    sed -i.bak \
        -e "s|__POLICY_NAME__|${POLICY_NAME}|g" \
        -e "s|__POLICY_ARN__|${POLICY_ARN}|g" \
        "${OUTPUT_FILE}"
    rm -f "${OUTPUT_FILE}.bak"
    chmod 600 "${OUTPUT_FILE}"
    echo "  Updated ${OUTPUT_FILE} with policy details."
else
    echo "  WARNING: expected credentials file '${OUTPUT_FILE}' was not found."
fi

# ---------------------------------------------------------------------------
# Helper: create a participant env file in the repo root
# ---------------------------------------------------------------------------
# This file contains secrets and is intended to be handed directly to the
# participant. It is git-ignored via the root .gitignore pattern `.env.*`.
ENV_FILE="${REPO_ROOT}/.env.${UNIQUE_ID}"
cat > "${ENV_FILE}" <<EOF
# Workshop environment variables for participant '${UNIQUE_ID}'
# Source this file or set the values as Codespaces / dev container secrets.
# DO NOT commit this file to git.

AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION}
WORKSHOP_UNIQUE_ID=${UNIQUE_ID}
EKS_CLUSTER_NAME=workshop-${UNIQUE_ID}
EOF
chmod 600 "${ENV_FILE}"
echo "  Created ${ENV_FILE}."

# ---------------------------------------------------------------------------
# Step 4: create the EKS IAM roles
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 4/5: creating EKS IAM roles"
echo "============================================================"
bash "${SCRIPT_DIR}/create-eks-roles.sh" "${UNIQUE_ID}"

# ---------------------------------------------------------------------------
# Step 5: create the EKS cluster
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Step 5/5: creating EKS cluster"
echo "============================================================"
bash "${SCRIPT_DIR}/create-eks-cluster.sh" "${UNIQUE_ID}"

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
cat <<EOF

============================================================
Workshop environment ready for '${UNIQUE_ID}'
============================================================
  IAM user:           ${USER_NAME}
  IAM policy:         ${POLICY_NAME}
  IAM policy ARN:     ${POLICY_ARN}
  Access key ID:      ${ACCESS_KEY_ID}
  Credentials file:   ${OUTPUT_FILE}
  Region:             ${AWS_REGION}
  Env handoff file:   ${ENV_FILE}

Hand '${OUTPUT_FILE}' and '${ENV_FILE}' to the participant. They can either
source the env file or set the values as Codespaces / dev container secrets:
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
EOF
