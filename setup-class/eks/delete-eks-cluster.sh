#!/usr/bin/env bash
#
# delete-eks-cluster.sh
#
# Deletes the EKS cluster "workshop-<uniqueId>" using eksctl. If the
# generated eksctl ClusterConfig YAML (workshop-<uniqueId>-eksctl.yaml) is
# present it is used so the deletion matches the create configuration
# exactly; otherwise the cluster is deleted by name and region.
#
# The YAML file is removed at the end so re-running create.sh produces a
# fresh, current config.
#
# Usage:
#   ./setup-class/eks/delete-eks-cluster.sh <uniqueId>
#
# Prerequisites (must be present in the environment):
#   - aws CLI on PATH
#   - eksctl on PATH (https://eksctl.io) -- only needed when the cluster
#     exists
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
EKSCTL_CONFIG_FILE="${SCRIPT_DIR}/${CLUSTER_NAME}-eksctl.yaml"

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

if [ -n "${AWS_PROFILE}" ]; then
    if ! aws "${AWS_PROFILE_ARGS[@]}" sts get-caller-identity --output json >/dev/null 2>&1; then
        fail "AWS profile '${AWS_PROFILE}' is set but could not authenticate. Check ~/.aws/credentials and ~/.aws/config."
    fi
elif [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    fail "Either AWS_PROFILE must be set, or both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set."
fi

# Resolve AWS_REGION. Only required when we actually need to delete the
# cluster (i.e. the YAML is missing or the cluster exists). When neither
# applies we exit without invoking eksctl so IAM-only cleanup still works.
AWS_REGION="${AWS_REGION:-}"
if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="$(aws "${AWS_PROFILE_ARGS[@]}" configure get region 2>/dev/null || true)"
    # Trim whitespace in case the AWS CLI returned extra padding.
    AWS_REGION="$(printf '%s' "${AWS_REGION}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -z "${AWS_REGION}" ]; then
    echo "WARNING: AWS_REGION is not set and could not be determined from the AWS CLI configuration." >&2
    echo "         EKS cluster deletion will be skipped if it is required." >&2
elif [[ "${AWS_REGION}" =~ [^a-z0-9-] ]]; then
    echo "WARNING: AWS_REGION contains invalid characters: '${AWS_REGION}'. Expected a value like 'us-east-1'." >&2
    echo "         EKS cluster deletion will be skipped." >&2
    AWS_REGION=""
fi

# ---------------------------------------------------------------------------
# Clean up demo LoadBalancer Services before deleting the cluster
# ---------------------------------------------------------------------------
# The demo apps expose their frontends via Services of type LoadBalancer.
# On EKS those create AWS ALB/NLB (elbv2) and classic ELB resources whose
# ENIs live on the cluster's VPC subnets. If they still exist when
# eksctl tears down the cluster's CloudFormation stack, the deletion fails
# on those orphan ENIs. So we delete the Services first and wait for the
# corresponding AWS LoadBalancers to disappear before invoking eksctl.

# Stream the DNSName of every AWS LoadBalancer visible to this account
# (ALB/NLB from elbv2 plus any classic ELBs). One DNSName per line. Returns
# empty output if the AWS CLI is missing or no LBs are visible.
_fetch_all_lb_dnsnames() {
    if ! command -v aws >/dev/null 2>&1; then
        return 0
    fi
    local json
    json="$(aws "${AWS_PROFILE_ARGS[@]}" elbv2 describe-load-balancers \
        --output json 2>/dev/null || true)"
    if [ -n "${json}" ]; then
        printf '%s' "${json}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for lb in data.get("LoadBalancers", []):
    dns = lb.get("DNSName", "")
    if dns:
        print(dns)
' || true
    fi
    json="$(aws "${AWS_PROFILE_ARGS[@]}" elb describe-load-balancers \
        --output json 2>/dev/null || true)"
    if [ -n "${json}" ]; then
        printf '%s' "${json}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for lb in data.get("LoadBalancerDescriptions", []):
    dns = lb.get("DNSName", "")
    if dns:
        print(dns)
' || true
    fi
}

cleanup_loadbalancers() {
    local -a demo_namespaces=("demo-ecommerce" "online-boutique" "bank-of-anthos" "locust")
    local -a deleted_endpoints=()
    local ns svc_json svc_name endpoint svc_count=0
    local timeout=300 poll_interval=15 elapsed=0
    local lb_dnsnames dnsname still_present

    if ! command -v kubectl >/dev/null 2>&1; then
        echo "  kubectl not on PATH; skipping LoadBalancer cleanup."
        return 0
    fi
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "  No reachable Kubernetes cluster; skipping LoadBalancer cleanup."
        return 0
    fi

    for ns in "${demo_namespaces[@]}"; do
        if ! kubectl get namespace "${ns}" >/dev/null 2>&1; then
            continue
        fi
        svc_json="$(kubectl get services -n "${ns}" \
            -o json 2>/dev/null || true)"
        [ -n "${svc_json}" ] || continue
        while IFS= read -r svc_name; do
            [ -n "${svc_name}" ] || continue
            # Capture the AWS endpoint (hostname or IP) before deletion so
            # we know which AWS LoadBalancer to wait for.
            endpoint="$(kubectl get service "${svc_name}" -n "${ns}" \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
                2>/dev/null || true)"
            if [ -z "${endpoint}" ]; then
                endpoint="$(kubectl get service "${svc_name}" -n "${ns}" \
                    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' \
                    2>/dev/null || true)"
            fi
            echo "  Deleting LoadBalancer Service '${svc_name}' in namespace '${ns}'..."
            kubectl delete service "${svc_name}" -n "${ns}" \
                --wait=true --timeout=180s || true
            svc_count=$((svc_count + 1))
            if [ -n "${endpoint}" ]; then
                deleted_endpoints+=("${endpoint}")
            fi
        done < <(printf '%s' "${svc_json}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for item in data.get("items", []):
    if item.get("spec", {}).get("type") != "LoadBalancer":
        continue
    name = item.get("metadata", {}).get("name", "")
    if name:
        print(name)
')
    done

    if [ "${svc_count}" -eq 0 ]; then
        echo "no LoadBalancer Services found"
        return 0
    fi

    echo "  Waiting up to ${timeout}s for AWS LoadBalancers matching deleted Services to disappear..."
    while [ "${elapsed}" -lt "${timeout}" ]; do
        lb_dnsnames="$(_fetch_all_lb_dnsnames)"
        still_present=0
        for dnsname in "${deleted_endpoints[@]}"; do
            [ -n "${dnsname}" ] || continue
            if printf '%s\n' "${lb_dnsnames}" | grep -Fqx -- "${dnsname}"; then
                still_present=1
                break
            fi
        done
        if [ "${still_present}" -eq 0 ]; then
            echo "  All matching LoadBalancers are gone."
            return 0
        fi
        sleep "${poll_interval}"
        elapsed=$((elapsed + poll_interval))
    done

    # Timeout reached. Report which endpoints are still backed by an LB so
    # the operator can clean them up manually before retrying.
    lb_dnsnames="$(_fetch_all_lb_dnsnames)"
    echo "WARNING: LoadBalancer(s) still present after ${timeout}s:" >&2
    for dnsname in "${deleted_endpoints[@]}"; do
        [ -n "${dnsname}" ] || continue
        if printf '%s\n' "${lb_dnsnames}" | grep -Fqx -- "${dnsname}"; then
            echo "  - ${dnsname}" >&2
        fi
    done
    return 0
}

cleanup_loadbalancers

# ---------------------------------------------------------------------------
# Delete the EKS cluster
# ---------------------------------------------------------------------------
# Doing this BEFORE the IAM roles because eksctl tears down the
# nodegroup / cluster service roles it created (or, in our case, the
# ones we passed via iam.serviceRoleARN / iam.instanceRoleARN).
if [ -n "${AWS_REGION}" ] && command -v eksctl >/dev/null 2>&1; then
    if [ -f "${EKSCTL_CONFIG_FILE}" ]; then
        echo "Deleting EKS cluster using ${EKSCTL_CONFIG_FILE}..."
        if eksctl delete cluster -f "${EKSCTL_CONFIG_FILE}" --wait; then
            echo "  Cluster and its VPC deleted."
        else
            echo "  Could not delete cluster via config (falling back to name/region)." >&2
            eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --wait || true
        fi
    else
        echo "Deleting EKS cluster '${CLUSTER_NAME}' in ${AWS_REGION}..."
        if eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --wait; then
            echo "  Cluster and its VPC deleted."
        else
            echo "  Could not delete cluster (it may not exist or has leftover dependencies)." >&2
            echo "  Common cause: LoadBalancers, ingress controllers, or pod ENIs still exist." >&2
            echo "  Delete those manually, then run eksctl delete cluster again." >&2
        fi
    fi
else
    echo "Skipping EKS cluster deletion (eksctl not installed or AWS_REGION unset)."
fi

# ---------------------------------------------------------------------------
# Remove the generated eksctl config file
# ---------------------------------------------------------------------------
if [ -f "${EKSCTL_CONFIG_FILE}" ]; then
    echo "Removing generated eksctl config file '${EKSCTL_CONFIG_FILE}'..."
    rm -f "${EKSCTL_CONFIG_FILE}"
fi
