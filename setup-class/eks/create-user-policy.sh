#!/usr/bin/env bash
#
# create-user-policy.sh
#
# Renders the per-user IAM policy from
# setup-class/eks/cast-ai-eks-policy-per-user.json.template (substituting
# ${UNIQUE_ID}, ${AWS_ACCOUNT_ID}, and ${AWS_REGION}), then either creates
# the policy in AWS or reuses an existing one with the same name.
#
# The policy is scoped to a single workshop participant's resources
# (cluster, nodegroup, tagged EC2/ASG resources).
#
# Usage:
#   AWS_PROFILE=workshop ./setup-class/eks/create-user-policy.sh <uniqueId>
#
# Output:
#   - Human-readable progress on stdout.
#   - One machine-readable line on stdout for downstream callers
#     (create.sh):
#         POLICY_ARN=arn:aws:iam::<account>:policy/CastAIEKSWorkshopPolicy-<uniqueId>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/cast-ai-eks-policy-per-user.json.template"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ "$#" -ne 1 ]; then
    fail "Usage: $0 <uniqueId>"
fi

UNIQUE_ID="$1"
if [ -z "${UNIQUE_ID}" ]; then
    fail "uniqueId must not be empty"
fi

if ! [[ "${UNIQUE_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "uniqueId must match [A-Za-z0-9._-]+  (got: '${UNIQUE_ID}')"
fi

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

if [ ! -f "${TEMPLATE_FILE}" ]; then
    fail "Policy template not found: ${TEMPLATE_FILE}"
fi

# ---------------------------------------------------------------------------
# Resolve account and region
# ---------------------------------------------------------------------------
CALLER_IDENTITY="$(aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json)"
AWS_ACCOUNT_ID="$(printf '%s' "${CALLER_IDENTITY}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Account"])')"

AWS_REGION="${AWS_REGION:-}"
if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="$(aws "${AWS_PROFILE_ARGS[@]}" configure get region 2>/dev/null || true)"
    # Trim whitespace in case the AWS CLI returned extra padding.
    AWS_REGION="$(printf '%s' "${AWS_REGION}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -z "${AWS_REGION}" ]; then
    fail "AWS_REGION is not set and could not be determined from the AWS CLI configuration."
fi

if [[ "${AWS_REGION}" =~ [^a-z0-9-] ]]; then
    fail "AWS_REGION contains invalid characters: '${AWS_REGION}'. Expected a value like 'us-east-1'."
fi

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

# ---------------------------------------------------------------------------
# Render the policy document from the template
# ---------------------------------------------------------------------------
POLICY_DOCUMENT_FILE="$(mktemp)"
trap 'rm -f "${POLICY_DOCUMENT_FILE}"' EXIT

python3 -c '
import sys, json
unique_id = sys.argv[1]
account_id = sys.argv[2]
region = sys.argv[3]
with open(sys.argv[4]) as f:
    template = f.read()
policy = (
    template
    .replace("${UNIQUE_ID}", unique_id)
    .replace("${AWS_ACCOUNT_ID}", account_id)
    .replace("${AWS_REGION}", region)
)
# Minify the policy document. AWS IAM customer-managed policies are limited
# to 6,144 characters; removing whitespace keeps the rendered document under
# the quota while leaving the template itself readable. Sort keys so that
# drift detection below is order-independent.
print(json.dumps(json.loads(policy), separators=(",", ":"), sort_keys=True))
' "${UNIQUE_ID}" "${AWS_ACCOUNT_ID}" "${AWS_REGION}" "${TEMPLATE_FILE}" > "${POLICY_DOCUMENT_FILE}"

RENDERED_POLICY_DOCUMENT="$(cat "${POLICY_DOCUMENT_FILE}")"

# ---------------------------------------------------------------------------
# Existing-policy guard / drift detection
# ---------------------------------------------------------------------------
if aws "${AWS_PROFILE_ARGS[@]}" iam get-policy --policy-arn "${POLICY_ARN}" --output json >/dev/null 2>&1; then
    echo "Policy '${POLICY_NAME}' exists; checking for drift against the template..."

    CURRENT_VERSION_ID="$(aws "${AWS_PROFILE_ARGS[@]}" iam get-policy \
        --policy-arn "${POLICY_ARN}" \
        --output json | python3 -c 'import sys, json; print(json.load(sys.stdin)["Policy"]["DefaultVersionId"])')"

    CURRENT_POLICY_DOCUMENT="$(aws "${AWS_PROFILE_ARGS[@]}" iam get-policy-version \
        --policy-arn "${POLICY_ARN}" \
        --version-id "${CURRENT_VERSION_ID}" \
        --output json | python3 -c '
import sys, json
doc = json.load(sys.stdin)["PolicyVersion"]["Document"]
print(json.dumps(doc, separators=(",", ":"), sort_keys=True))
')"

    if [ "${CURRENT_POLICY_DOCUMENT}" = "${RENDERED_POLICY_DOCUMENT}" ]; then
        echo "Policy '${POLICY_NAME}' is up to date; reusing."
        echo "POLICY_ARN=${POLICY_ARN}"
        exit 0
    fi

    echo "Policy drift detected; creating new default version..."
    aws "${AWS_PROFILE_ARGS[@]}" iam create-policy-version \
        --policy-arn "${POLICY_ARN}" \
        --policy-document "file://${POLICY_DOCUMENT_FILE}" \
        --set-as-default

    echo "POLICY_ARN=${POLICY_ARN}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Create the policy
# ---------------------------------------------------------------------------
echo "Creating policy '${POLICY_NAME}'..."
POLICY_ARN="$(aws "${AWS_PROFILE_ARGS[@]}" iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document "file://${POLICY_DOCUMENT_FILE}" \
    --output json | python3 -c 'import sys, json; print(json.load(sys.stdin)["Policy"]["Arn"])')"

echo "POLICY_ARN=${POLICY_ARN}"
