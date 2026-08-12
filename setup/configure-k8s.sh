#!/usr/bin/env bash
#
# configure-k8s.sh — Configure AWS credentials and pull the EKS kubeconfig
# for the MSP workshop.
#
# This script creates an AWS CLI profile named "workshop", exports
# AWS_PROFILE=workshop, verifies the caller identity, and pulls the
# kubeconfig for the provided EKS cluster.
#
# Usage:
#   source ./configure-k8s.sh
#
# Sourcing is recommended so AWS_PROFILE persists in the current shell.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[configure-k8s]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[configure-k8s]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[configure-k8s]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[configure-k8s]${NC} %s\n" "$*"; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

read_nonempty() {
  local prompt="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -p "${prompt}" value
    if [[ -z "${value}" ]]; then
      warn "value is required"
    fi
  done
  printf '%s' "${value}"
}

main() {
  info "MSP Workshop — Kubernetes environment configuration"
  info "---------------------------------------------------"
  printf '\n'

  if ! command_exists aws; then
    err "aws CLI is not installed. Run ./setup/validate-setup.sh first."
    exit 1
  fi
  log "aws CLI found"

  if ! command_exists kubectl; then
    err "kubectl is not installed. Run ./setup/validate-setup.sh first."
    exit 1
  fi
  log "kubectl found"

  # 1. AWS credentials
  info "Enter the AWS credentials provided by your workshop host."
  local aws_access_key_id aws_secret_access_key aws_region
  aws_access_key_id="$(read_nonempty "AWS Access Key ID: ")"
  read -r -s -p "AWS Secret Access Key: " aws_secret_access_key
  printf '\n'
  aws_region="$(read_nonempty "AWS Default Region (e.g. ap-southeast-1): ")"

  info "configuring aws CLI profile 'workshop'..."
  aws configure set aws_access_key_id "${aws_access_key_id}" --profile workshop
  aws configure set aws_secret_access_key "${aws_secret_access_key}" --profile workshop
  aws configure set region "${aws_region}" --profile workshop

  export AWS_PROFILE=workshop
  log "AWS_PROFILE set to 'workshop' for this shell"

  # 2. Verify caller identity and derive cluster name
  info "checking which AWS identity these credentials belong to..."
  local caller_arn iam_user_name cluster_name
  caller_arn="$(aws sts get-caller-identity --query Arn --output text)"
  if [[ -z "${caller_arn}" ]]; then
    err "could not determine AWS caller identity. Check your credentials."
    exit 1
  fi
  log "caller ARN: ${caller_arn}"

  iam_user_name="${caller_arn##*/}"
  log "IAM user name: ${iam_user_name}"

  # Derive cluster name from IAM user name.
  # Example: workshop-participant-uniqueIdentifier -> workshop-uniqueIdentifier
  cluster_name="${iam_user_name/workshop-participant-/workshop-}"
  log "derived EKS cluster name: ${cluster_name}"

  # 3. Pull kubeconfig
  info "pulling kubeconfig for cluster '${cluster_name}' in region '${aws_region}'..."
  if ! aws eks update-kubeconfig --name "${cluster_name}" --region "${aws_region}"; then
    err "failed to pull kubeconfig. Check the cluster name, region, and that your AWS user has access."
    exit 1
  fi
  log "kubeconfig updated"

  # 4. Validate
  info "validating cluster access..."
  if ! kubectl get nodes >/dev/null 2>&1; then
    err "cannot list cluster nodes. Check your kubeconfig and AWS credentials."
    exit 1
  fi

  printf '\n'
  log "environment configured successfully"
  info "AWS_PROFILE=workshop is active in this shell"
  kubectl get nodes
  printf '\n'
  info "next: proceed to the next workshop lesson"
  info "tip: run 'export AWS_PROFILE=workshop' in new terminals, or add it to your shell profile."
}

main "$@"
