#!/usr/bin/env bash
#
# install-kind.sh — Idempotent kind cluster setup for the MSP workshop.
#
# Checks Docker, kubectl, helm, and kind; installs any missing CLI, then
# creates the workshop kind cluster if it does not already exist.
#
# Usage:
#   ./install-kind.sh          create cluster if absent
#   ./install-kind.sh --recreate  delete and recreate the cluster

set -euo pipefail

# ANSI colors for messages.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[install-kind]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[install-kind]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[install-kind]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[install-kind]${NC} %s\n" "$*"; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *)
      err "unsupported architecture: ${arch}. Only x86_64 (amd64) and aarch64/arm64 are supported."
      return 1
      ;;
  esac
}

detect_os() {
  local os
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${os}" in
    linux) printf 'linux\n' ;;
    darwin) printf 'darwin\n' ;;
    *)
      err "unsupported OS: ${os}. Only Linux and macOS are supported."
      return 1
      ;;
  esac
}

# Return a writable directory suitable for installing binaries.
# Prefers /usr/local/bin; falls back to $HOME/.local/bin.
install_dir() {
  if [[ -w /usr/local/bin ]]; then
    printf '/usr/local/bin\n'
  else
    printf '%s/.local/bin\n' "${HOME}"
  fi
}

# Ensure the given directory is on PATH for the rest of this script and
# print a note for the user if it was not already there.
ensure_path() {
  local dir="$1"
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *)
      export PATH="${dir}:${PATH}"
      info "added ${dir} to PATH for this session"
      info "to persist, add: export PATH=\"${dir}:\$PATH\" to your shell profile"
      ;;
  esac
}

# Install a binary from a URL into the chosen install directory.
# Usage: install_binary <url> <target-name>
install_binary() {
  local url="$1" target="$2"
  local tmp dir
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"; trap - RETURN' RETURN

  if ! curl -fsSL "${url}" -o "${tmp}/${target}"; then
    err "failed to download ${target} from ${url}"
    return 1
  fi

  chmod +x "${tmp}/${target}"

  dir="$(install_dir)"
  mkdir -p "${dir}"

  if [[ -w "${dir}" ]]; then
    install -m 0755 "${tmp}/${target}" "${dir}/${target}"
  else
    sudo install -m 0755 "${tmp}/${target}" "${dir}/${target}"
  fi

  ensure_path "${dir}"
}

check_docker() {
  log "checking Docker..."
  if ! command_exists docker; then
    warn "Docker not found; running installer..."
    local installer
    installer="$(dirname "$0")/install-docker.sh"
    if ! bash "${installer}"; then
      err "Docker installer failed. Install Docker manually and try again."
      return 1
    fi
    if ! command_exists docker; then
      err "Docker install reported success but 'docker' is still not on PATH."
      return 1
    fi
  fi

  if ! docker info >/dev/null 2>&1; then
    warn "Docker daemon is not running; attempting to start it..."
    local started=0
    if command_exists systemctl; then
      if sudo systemctl start docker; then
        started=1
      fi
    elif command_exists service; then
      if sudo service docker start; then
        started=1
      fi
    fi

    if [[ "${started}" -ne 1 ]]; then
      err "could not start Docker daemon. Start it manually and try again."
      return 1
    fi

    if ! docker info >/dev/null 2>&1; then
      err "Docker daemon did not become available after start. Check 'systemctl status docker' or 'docker info' manually."
      return 1
    fi
  fi

  local mem_gb
  mem_gb="$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{print int($1/1024/1024/1024)}')"
  if [[ -z "${mem_gb}" || "${mem_gb}" -lt 1 ]]; then
    warn "could not determine Docker memory. Ensure at least 6-8 GB is allocated."
  elif [[ "${mem_gb}" -lt 6 ]]; then
    warn "Docker has only ${mem_gb}GB memory allocated; 6-8 GB is recommended."
  else
    log "Docker is running with ${mem_gb}GB memory"
  fi
}

check_install_kubectl() {
  log "checking kubectl..."
  if command_exists kubectl; then
    log "kubectl already installed: $(kubectl version --client 2>/dev/null | head -n1)"
    return 0
  fi

  warn "kubectl not found; installing..."
  local arch version tmp dir
  arch="$(detect_arch)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"; trap - RETURN' RETURN

  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl" -o "${tmp}/kubectl"
  chmod +x "${tmp}/kubectl"

  dir="$(install_dir)"
  mkdir -p "${dir}"
  if [[ -w "${dir}" ]]; then
    install -m 0755 "${tmp}/kubectl" "${dir}/kubectl"
  else
    sudo install -m 0755 "${tmp}/kubectl" "${dir}/kubectl"
  fi

  ensure_path "${dir}"
  log "kubectl installed: $(kubectl version --client 2>/dev/null | head -n1)"
}

check_install_helm() {
  log "checking helm..."
  if command_exists helm; then
    log "helm already installed: $(helm version --short 2>/dev/null)"
    return 0
  fi

  warn "helm not found; installing..."
  local tmp dir
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"; trap - RETURN' RETURN

  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${tmp}/get_helm.sh"

  dir="$(install_dir)"
  mkdir -p "${dir}"

  local helm_install_dir="${dir}"
  local use_sudo=0
  if [[ ! -w "${helm_install_dir}" ]] && command_exists sudo; then
    use_sudo=1
  fi

  local install_ok=0
  if [[ "${use_sudo}" == "1" ]]; then
    if sudo -nE HELM_INSTALL_DIR="${helm_install_dir}" bash "${tmp}/get_helm.sh"; then
      install_ok=1
    fi
  else
    if HELM_INSTALL_DIR="${helm_install_dir}" bash "${tmp}/get_helm.sh"; then
      install_ok=1
    fi
  fi

  if [[ "${install_ok}" -ne 1 ]]; then
    warn "helm install into ${helm_install_dir} failed; falling back to ${HOME}/.local/bin"
    helm_install_dir="${HOME}/.local/bin"
    mkdir -p "${helm_install_dir}"
    HELM_INSTALL_DIR="${helm_install_dir}" bash "${tmp}/get_helm.sh"
  fi

  ensure_path "${helm_install_dir}"
  log "helm installed: $(helm version --short 2>/dev/null)"
}

check_install_kind() {
  log "checking kind..."
  if command_exists kind; then
    log "kind already installed: $(kind version 2>/dev/null | head -n1)"
    return 0
  fi

  warn "kind not found; installing..."
  local os arch
  os="$(detect_os)"
  arch="$(detect_arch)"
  install_binary "https://kind.sigs.k8s.io/dl/latest/kind-${os}-${arch}" "kind"
  log "kind installed: $(kind version 2>/dev/null | head -n1)"
}

create_cluster() {
  local recreate="${1:-0}"
  local cluster_name="workshop-cluster"
  local script_dir config_file

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  config_file="${script_dir}/kind-cluster-config.yaml"

  if [[ ! -f "${config_file}" ]]; then
    err "kind config not found: ${config_file}"
    return 1
  fi

  if kind get clusters 2>/dev/null | grep -q "^${cluster_name}$"; then
    if [[ "${recreate}" == "1" ]]; then
      warn "cluster '${cluster_name}' exists; deleting for recreation..."
      kind delete cluster --name "${cluster_name}"
    else
      info "cluster '${cluster_name}' already exists; skipping creation (use --recreate to replace it)"
      return 0
    fi
  fi

  log "creating kind cluster '${cluster_name}' (this may take 2-5 minutes)..."
  kind create cluster --config "${config_file}"
  log "cluster created"
}

verify_cluster() {
  local cluster_name="workshop-cluster"
  log "verifying cluster..."

  if ! kubectl cluster-info --context "kind-${cluster_name}" >/dev/null 2>&1; then
    err "cannot connect to cluster kind-${cluster_name}"
    return 1
  fi

  log "waiting for nodes to be ready..."
  kubectl wait --for=condition=ready nodes --all --timeout=120s --context "kind-${cluster_name}"

  log "cluster nodes:"
  kubectl get nodes -o wide --context "kind-${cluster_name}"
}

main() {
  local recreate=0

  for arg in "$@"; do
    case "${arg}" in
      --recreate)
        recreate=1
        ;;
      -h|--help)
        printf 'Usage: %s [--recreate]\n' "$0"
        printf '  --recreate  delete and recreate the workshop kind cluster\n'
        exit 0
        ;;
      *)
        err "unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  check_docker
  check_install_kubectl
  check_install_helm
  check_install_kind
  create_cluster "${recreate}"
  verify_cluster

  log "setup complete!"
  info "cluster: workshop-cluster"
  info "context: kind-workshop-cluster"
  info "next: ./verify-kind.sh"
}

main "$@"
