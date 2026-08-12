#!/usr/bin/env bash
#
# create-eks-cluster.sh
#
# Admin-only script that creates an EKS cluster for a single workshop
# participant. Steps performed:
#
#   1. Validates arguments, AWS CLI / python3, and AWS credentials.
#   2. Resolves the AWS account ID and region.
#   3. Calls ./setup-class/eks/create-eks-roles.sh to ensure the cluster and nodegroup
#      IAM roles exist (idempotent).
#   4. Renders an eksctl ClusterConfig YAML file at
#      setup-class/eks/workshop-<uniqueId>-eksctl.yaml.
#   5. Runs `eksctl create cluster -f <yaml>`.
#   6. Adds the participant IAM user to the cluster's aws-auth ConfigMap
#      via `eksctl create iamidentitymapping` with `system:masters`.
#   7. Prints a success summary including the post-create command the
#      participant will run inside their dev container.
#
# Usage:
#   ./setup-class/eks/create-eks-cluster.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - python3 on PATH (for JSON parsing)
#   - eksctl on PATH (https://eksctl.io)
#   - AWS_REGION must be set (or available via `aws configure get region`)
#   - One of the following authentication methods:
#       * AWS_PROFILE pointing to a configured AWS CLI profile, OR
#       * AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optional
#         AWS_SESSION_TOKEN) for direct credential injection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

CLUSTER_NAME="workshop-${UNIQUE_ID}"
NODEGROUP_NAME="${CLUSTER_NAME}-ng"
CONFIG_FILE="${SCRIPT_DIR}/${CLUSTER_NAME}-eksctl.yaml"
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

if ! command -v eksctl >/dev/null 2>&1; then
    fail "eksctl is not installed or not on PATH. Install it before running this script."
fi

if [ -n "${AWS_PROFILE}" ]; then
    if ! aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json >/dev/null 2>&1; then
        fail "AWS profile '${AWS_PROFILE}' is set but could not authenticate. Check ~/.aws/credentials and ~/.aws/config."
    fi
elif [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    fail "Either AWS_PROFILE must be set, or both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set."
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

# Defensive: reject regions with unexpected characters (spaces, commas, etc.)
# which can silently corrupt CLI flags or the generated YAML.
if [[ "${AWS_REGION}" =~ [^a-z0-9-] ]]; then
    fail "AWS_REGION contains invalid characters: '${AWS_REGION}'. Expected a value like 'us-east-1'."
fi

CLUSTER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/workshop-${UNIQUE_ID}-cluster-role"
NODEGROUP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/workshop-${UNIQUE_ID}-nodegroup-role"

# ---------------------------------------------------------------------------
# Resolve the latest stable Kubernetes version supported by EKS
# ---------------------------------------------------------------------------
echo "Resolving latest stable Kubernetes version in ${AWS_REGION}..."
K8S_VERSION=""

# Try the addon-versions API first; fall back to a known recent stable
# version if the API is unavailable or returns no usable data.
if K8S_VERSION_JSON="$(aws "${AWS_PROFILE_ARGS[@]}" eks describe-addon-versions \
    --addon-name vpc-cni \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null)"; then
    K8S_VERSION="$(printf '%s' "${K8S_VERSION_JSON}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    versions = set(
        c["clusterVersion"]
        for av in data.get("addons", [{}])[0].get("addonVersions", [])
        for c in av.get("compatibilities", [])
    )
    if versions:
        print(max(versions, key=lambda v: tuple(int(x) for x in v.split("."))))
except Exception:
    pass
')"
fi

if [ -z "${K8S_VERSION:-}" ]; then
    K8S_VERSION="${KUBERNETES_VERSION:-1.31}"
    echo "  Could not query EKS for latest version; falling back to ${K8S_VERSION}."
    echo "  Set KUBERNETES_VERSION to override."
fi

echo "  Using Kubernetes version ${K8S_VERSION}."

# ---------------------------------------------------------------------------
# Ensure IAM roles exist (delegate to create-eks-roles.sh)
# ---------------------------------------------------------------------------
echo "Ensuring IAM roles for cluster '${CLUSTER_NAME}' exist..."
# Capture both stdout and stderr so we can show role ARNs while also letting
# the helper script print its own progress lines.
ROLES_OUTPUT="$(bash "${SCRIPT_DIR}/create-eks-roles.sh" "${UNIQUE_ID}")"
printf '%s\n' "${ROLES_OUTPUT}"

# Re-derive the role ARNs in case the helper's stderr path changed anything.
CLUSTER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/workshop-${UNIQUE_ID}-cluster-role"
NODEGROUP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/workshop-${UNIQUE_ID}-nodegroup-role"

# ---------------------------------------------------------------------------
# Render the eksctl ClusterConfig YAML
# ---------------------------------------------------------------------------
echo ""
echo "Writing eksctl config to ${CONFIG_FILE}..."

# Use a heredoc with literal `${...}` placeholders so the shell does not try
# to expand them. We only want UNIQUE_ID, AWS_REGION, AWS_ACCOUNT_ID expanded.
cat > "${CONFIG_FILE}" <<EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${K8S_VERSION}"
  tags:
    workshop-participant: ${UNIQUE_ID}

iam:
  serviceRoleARN: ${CLUSTER_ROLE_ARN}
  withOIDC: true

managedNodeGroups:
  - name: ${NODEGROUP_NAME}
    iam:
      instanceRoleARN: ${NODEGROUP_ROLE_ARN}
    instanceTypes:
      - m4.large
      - m5.large
      - m5.xlarge
      - c5.large
      - c5.xlarge
      - c6i.large
    desiredCapacity: 6
    minSize: 6
    maxSize: 6
    volumeSize: 20
    tags:
      workshop-participant: ${UNIQUE_ID}
EOF

echo "  Wrote ${CONFIG_FILE}."

# ---------------------------------------------------------------------------
# Create the cluster
# ---------------------------------------------------------------------------
echo ""
echo "Creating EKS cluster '${CLUSTER_NAME}' in ${AWS_REGION} (this takes ~10-15 minutes)..."
aws "${AWS_PROFILE_ARGS[@]}" eks wait cluster-active --help >/dev/null 2>&1 || true
eksctl create cluster -f "${CONFIG_FILE}"

# ---------------------------------------------------------------------------
# Grant the participant IAM user admin access via aws-auth
# ---------------------------------------------------------------------------
echo ""
echo "Granting '${USER_NAME}' system:masters on '${CLUSTER_NAME}'..."
eksctl create iamidentitymapping \
    --cluster "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${USER_NAME}" \
    --group system:masters \
    --username "${USER_NAME}"

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
cat <<EOF

============================================================
EKS cluster '${CLUSTER_NAME}' is ready.
============================================================
  Region:               ${AWS_REGION}
  Cluster ARN:          arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}
  Cluster role ARN:     ${CLUSTER_ROLE_ARN}
  Nodegroup role ARN:   ${NODEGROUP_ROLE_ARN}
  eksctl config file:   ${CONFIG_FILE}

Next steps for the participant:

  1. Make sure WORKSHOP_UNIQUE_ID is set in their Codespaces / Codespaces
     secrets and re-open the dev container so postCreateCommand runs.

  2. Verify with:

       kubectl get nodes
       kubectl get nodes -L workshop-participant
EOF
