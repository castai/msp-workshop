#!/usr/bin/env bash
#
# create-eks-roles.sh
#
# Admin-only script that creates the two IAM roles required by an EKS
# cluster for a single workshop participant:
#
#   - workshop-<uniqueId>-cluster-role
#       Trust policy : eks.amazonaws.com
#       Managed policy: arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
#
#   - workshop-<uniqueId>-nodegroup-role
#       Trust policy : ec2.amazonaws.com
#       Managed policies:
#         arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
#         arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
#         arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
#
# Both roles are tagged with `workshop-participant=<uniqueId>` so cleanup
# scripts can find them. If a role already exists, it is left in place and
# reused; this script does not fail on re-runs.
#
# Usage:
#   ./setup-class/eks/create-eks-roles.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - One of the following authentication methods:
#       * AWS_PROFILE pointing to a configured AWS CLI profile, OR
#       * AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optional
#         AWS_SESSION_TOKEN) for direct credential injection.
#
# Output (stdout):
#   - The ARNs of both roles, one per line:
#       CLUSTER_ROLE_ARN=arn:aws:iam::<account>:role/workshop-<uniqueId>-cluster-role
#       NODEGROUP_ROLE_ARN=arn:aws:iam::<account>:role/workshop-<uniqueId>-nodegroup-role

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

# Restrict uniqueId to a safe character set so the constructed role names
# cannot be smuggled into an unexpected aws CLI call.
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

# Resolve the AWS account ID so we can construct the role ARNs.
CALLER_IDENTITY="$(aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json)"
AWS_ACCOUNT_ID="$(printf '%s' "${CALLER_IDENTITY}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Account"])')"

# ---------------------------------------------------------------------------
# Ensure attached managed policy is present on a role (idempotent)
# ---------------------------------------------------------------------------
ensure_role_policy_attached() {
    local role_name="$1"
    local policy_arn="$2"

    # list-attached-role-policies returns a JSON array of {PolicyArn, PolicyName}.
    # We filter for the target ARN and check whether the result is non-empty.
    local already_attached
    already_attached="$(aws "${AWS_PROFILE_ARGS[@]}" iam list-attached-role-policies \
        --role-name "${role_name}" \
        --output json 2>/dev/null \
        | python3 -c '
import sys, json
target = sys.argv[1]
data = json.load(sys.stdin)
for p in data.get("AttachedPolicies", []):
    if p.get("PolicyArn") == target:
        print("yes")
        break
else:
    print("no")
' "${policy_arn}")"

    if [ "${already_attached}" = "yes" ]; then
        echo "  Policy ${policy_arn} already attached to '${role_name}'."
    else
        echo "  Attaching policy ${policy_arn} to '${role_name}'..."
        aws "${AWS_PROFILE_ARGS[@]}" iam attach-role-policy \
            --role-name "${role_name}" \
            --policy-arn "${policy_arn}" >/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Create (or reuse) a role and attach a list of managed policies
# ---------------------------------------------------------------------------
create_or_reuse_role() {
    local role_name="$1"
    local trust_policy_file="$2"
    local tag_key="workshop-participant"
    local tag_value="${UNIQUE_ID}"
    shift 2
    local -a policy_arns=("$@")

    if aws "${AWS_PROFILE_ARGS[@]}" iam get-role \
        --role-name "${role_name}" \
        --output json >/dev/null 2>&1; then
        echo "Role '${role_name}' already exists; reusing it."
    else
        echo "Creating role '${role_name}'..."
        aws "${AWS_PROFILE_ARGS[@]}" iam create-role \
            --role-name "${role_name}" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --tags "Key=${tag_key},Value=${tag_value}" \
            --output json >/dev/null
    fi

    local policy_arn
    for policy_arn in "${policy_arns[@]}"; do
        ensure_role_policy_attached "${role_name}" "${policy_arn}"
    done
}

# ---------------------------------------------------------------------------
# Trust policy: EKS cluster service role
# ---------------------------------------------------------------------------
CLUSTER_TRUST_POLICY_FILE="$(mktemp)"
trap 'rm -f "${CLUSTER_TRUST_POLICY_FILE}" "${NODEGROUP_TRUST_POLICY_FILE:-}"' EXIT

cat > "${CLUSTER_TRUST_POLICY_FILE}" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

create_or_reuse_role "${CLUSTER_ROLE_NAME}" "${CLUSTER_TRUST_POLICY_FILE}" \
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

# ---------------------------------------------------------------------------
# Trust policy: EC2 worker node role
# ---------------------------------------------------------------------------
NODEGROUP_TRUST_POLICY_FILE="$(mktemp)"
# Re-register the trap now that NODEGROUP_TRUST_POLICY_FILE exists.
trap 'rm -f "${CLUSTER_TRUST_POLICY_FILE}" "${NODEGROUP_TRUST_POLICY_FILE}"' EXIT

cat > "${NODEGROUP_TRUST_POLICY_FILE}" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

create_or_reuse_role "${NODEGROUP_ROLE_NAME}" "${NODEGROUP_TRUST_POLICY_FILE}" \
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" \
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

# ---------------------------------------------------------------------------
# Output role ARNs (used by create-eks-cluster.sh)
# ---------------------------------------------------------------------------
CLUSTER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_ROLE_NAME}"
NODEGROUP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${NODEGROUP_ROLE_NAME}"

echo ""
echo "EKS IAM roles ready."
echo "  Cluster role ARN:    ${CLUSTER_ROLE_ARN}"
echo "  Nodegroup role ARN:  ${NODEGROUP_ROLE_ARN}"
echo ""
# Machine-readable lines for downstream callers (create-eks-cluster.sh).
echo "CLUSTER_ROLE_ARN=${CLUSTER_ROLE_ARN}"
echo "NODEGROUP_ROLE_ARN=${NODEGROUP_ROLE_ARN}"
